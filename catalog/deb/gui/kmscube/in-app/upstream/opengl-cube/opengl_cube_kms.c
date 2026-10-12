/*
 * OpenGL Cube, KMS-hosted variant — INTERIM, Android only.
 *
 * The real opengl-cube (opengl_cube.c) is a Wayland client: xdg-shell +
 * wl_egl_window on Wawona's compositor. Android cannot run that yet because two
 * pieces are missing — an AHardwareBuffer-backed Wayland-EGL winsys in
 * wwn-iland (the Apple side posts IOSurfaces, see shims/egl/src/egl_wayland.c),
 * and an AHB import path in the compositor's zwp_linux_dmabuf_v1 handler, which
 * today accepts only IOSurface-id modifiers.
 *
 * Until both land, Android keeps this KMS-hosted build so the client does not
 * regress. Delete this file once Android has the winsys; do not add features
 * here, and do not let Apple targets drift back onto it.
 *
 * c2d7fa/opengl-cube ported off GLFW/GLEW onto iland's virtual DRM/GBM/EGL
 * stack, running in-process exactly like kmscube does.
 *
 * Renderer (geometry, colours, shaders, animation, matrix.h) comes from
 * https://github.com/c2d7fa/opengl-cube @ daba3b8, CC0-1.0 (see ./LICENSE).
 * This is a genuinely different demo from kmscube: flat vertex-interpolated
 * colours on a dark blue ground, versus kmscube's diffuse-lit cube.
 *
 * The KMS/GBM/EGL host sequence below follows embtom/kmscube (Arvin Schnell,
 * Rob Clark, Anand Balagopalakrishnan; MIT) — see ../kmscube.c. It is
 * duplicated rather than shared because kmscube is the proven acceptance
 * client and must not be refactored underneath it; a later extraction into a
 * common host is tracked in docs/issues/opengl-vulkan-cube-port.md.
 *
 * Port notes, all forced by the target rather than preference:
 *  - GLFW window/context/swap  -> gbm_surface + eglCreateWindowSurface + page flip.
 *  - GLEW                      -> ANGLE GLES3 headers.
 *  - GLSL 450                  -> GLSL ES 300 (adds a precision qualifier).
 *  - Shaders read from vertex.glsl / fragment.glsl at runtime -> embedded, since
 *    there is no cwd beside the binary once this is linked into an app bundle.
 *  - glfwGetTime               -> CLOCK_MONOTONIC.
 *  - Upstream's projection assumes the 800x800 window it created. A KMS mode is
 *    not square, so aspect is corrected with a scale matrix in front of the
 *    projection; matrix.h itself is kept verbatim.
 */

#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#include <drm_fourcc.h>
#include <gbm.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

#include <EGL/egl.h>
#include <GLES3/gl3.h>

#include "matrix.h"

static struct {
	EGLDisplay display;
	EGLConfig config;
	EGLContext context;
	EGLSurface surface;
	GLuint program;
	GLuint vao;
	GLint uniform_transform;
	int width, height;
} gl;

static struct {
	struct gbm_device *dev;
	struct gbm_surface *surface;
} gbm;

static struct {
	int fd;
	uint32_t crtc_id;
	uint32_t connector_id;
	uint32_t format;
	drmModeRes *resources;
	drmModeEncoder *encoder;
	drmModeConnector *connector;
	drmModeModeInfo *mode;
} drm;

struct drm_fb {
	struct gbm_bo *bo;
	uint32_t fb_id;
};

static const char *device = "/dev/dri/card0";

/* ------------------------------------------------------------------ *
 * DRM / GBM / EGL host (see ../kmscube.c)
 * ------------------------------------------------------------------ */

static uint32_t drm_fmt_to_gbm_fmt(uint32_t fmt)
{
	switch (fmt) {
	case DRM_FORMAT_XRGB8888:
		return GBM_FORMAT_XRGB8888;
	case DRM_FORMAT_ARGB8888:
		return GBM_FORMAT_ARGB8888;
	case DRM_FORMAT_RGB565:
		return GBM_FORMAT_RGB565;
	default:
		printf("opengl-cube: unsupported DRM format 0x%x, assuming XRGB8888\n", fmt);
		return GBM_FORMAT_XRGB8888;
	}
}

static bool plane_has_format(uint32_t desired, int count, uint32_t *formats)
{
	for (int i = 0; i < count; i++)
		if (desired == formats[i])
			return true;
	return false;
}

static int get_drm_prop_val(int fd, drmModeObjectPropertiesPtr props,
			    const char *name, unsigned int *p_val)
{
	drmModePropertyPtr p = NULL;
	unsigned int i, prop_id = 0; /* Property ID is always > 0 */

	for (i = 0; !prop_id && i < props->count_props; i++) {
		p = drmModeGetProperty(fd, props->props[i]);
		if (!p)
			continue;
		if (!strcmp(p->name, name)) {
			prop_id = p->prop_id;
			break;
		}
		drmModeFreeProperty(p);
		p = NULL;
	}

	if (!prop_id) {
		printf("opengl-cube: could not find %s property\n", name);
		return -1;
	}

	drmModeFreeProperty(p);
	*p_val = props->prop_values[i];
	return 0;
}

/* Pick a scanout format the primary plane actually advertises, in preference
 * order. iland's virtual plane decides what the IOSurface / AHardwareBuffer
 * ends up being, so this must be asked rather than assumed. */
static bool set_drm_format(void)
{
	static const uint32_t drm_formats[] = { DRM_FORMAT_XRGB8888,
						DRM_FORMAT_ARGB8888,
						DRM_FORMAT_RGB565 };
	bool found = false;

	drmSetClientCap(drm.fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1);

	drmModePlaneRes *plane_res = drmModeGetPlaneResources(drm.fd);
	if (!plane_res) {
		printf("opengl-cube: drmModeGetPlaneResources failed: %s\n", strerror(errno));
		drmSetClientCap(drm.fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 0);
		return false;
	}

	for (uint32_t i = 0; i < plane_res->count_planes && !found; i++) {
		drmModePlane *plane = drmModeGetPlane(drm.fd, plane_res->planes[i]);
		if (!plane)
			continue;

		drmModeObjectProperties *props = drmModeObjectGetProperties(
			drm.fd, plane->plane_id, DRM_MODE_OBJECT_PLANE);
		unsigned int plane_type = 0;
		if (props &&
		    get_drm_prop_val(drm.fd, props, "type", &plane_type) == 0 &&
		    plane_type == DRM_PLANE_TYPE_PRIMARY) {
			for (size_t k = 0; k < sizeof(drm_formats) / sizeof(drm_formats[0]); k++) {
				if (plane_has_format(drm_formats[k], plane->count_formats,
						     plane->formats)) {
					drm.format = drm_formats[k];
					found = true;
					break;
				}
			}
		}

		if (props)
			drmModeFreeObjectProperties(props);
		drmModeFreePlane(plane);
	}

	drmModeFreePlaneResources(plane_res);
	drmSetClientCap(drm.fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 0);
	return found;
}

static int init_drm(void)
{
	drm.fd = open(device, O_RDWR | O_CLOEXEC);
	if (drm.fd < 0) {
		printf("opengl-cube: could not open drm device %s\n", device);
		return -1;
	}

	drm.resources = drmModeGetResources(drm.fd);
	if (!drm.resources) {
		printf("opengl-cube: drmModeGetResources failed: %s\n", strerror(errno));
		return -1;
	}

	for (int i = 0; i < drm.resources->count_connectors; i++) {
		drmModeConnector *connector =
			drmModeGetConnector(drm.fd, drm.resources->connectors[i]);
		if (!connector)
			continue;
		if (connector->connection != DRM_MODE_CONNECTED ||
		    connector->count_modes < 1) {
			drmModeFreeConnector(connector);
			continue;
		}

		drmModeEncoder *encoder = NULL;
		for (int j = 0; j < connector->count_encoders; j++) {
			encoder = drmModeGetEncoder(drm.fd, connector->encoders[j]);
			if (!encoder)
				continue;
			if (!connector->encoder_id)
				connector->encoder_id = encoder->encoder_id;
			if (encoder->encoder_id == connector->encoder_id) {
				if (!encoder->crtc_id) {
					for (int k = 0; k < drm.resources->count_crtcs; k++) {
						if (!(encoder->possible_crtcs & (1 << k)))
							continue;
						encoder->crtc_id = drm.resources->crtcs[k];
						break;
					}
				}
				if (encoder->crtc_id)
					break;
			}
			drmModeFreeEncoder(encoder);
			encoder = NULL;
		}

		if (!encoder) {
			printf("opengl-cube: connector %d has no usable encoder\n",
			       connector->connector_id);
			drmModeFreeConnector(connector);
			continue;
		}

		/* Prefer the mode the CRTC is already programmed with, else the
		 * connector's first (preferred) mode. */
		drmModeCrtc *crtc = drmModeGetCrtc(drm.fd, encoder->crtc_id);
		drm.mode = &connector->modes[0];
		if (crtc && crtc->mode_valid) {
			for (int j = 0; j < connector->count_modes; j++) {
				if (connector->modes[j].hdisplay == crtc->width &&
				    connector->modes[j].vdisplay == crtc->height) {
					drm.mode = &connector->modes[j];
					break;
				}
			}
		}
		if (crtc)
			drmModeFreeCrtc(crtc);

		drm.connector = connector;
		drm.connector_id = connector->connector_id;
		drm.encoder = encoder;
		drm.crtc_id = encoder->crtc_id;

		if (!set_drm_format()) {
			printf("opengl-cube: no desired pixel format found!\n");
			return -1;
		}

		printf("opengl-cube: CRTC %d, connector %d, format 0x%x, mode %s %dx%d@%d\n",
		       drm.crtc_id, drm.connector_id, drm.format, drm.mode->name,
		       drm.mode->hdisplay, drm.mode->vdisplay, drm.mode->vrefresh);
		return 0;
	}

	printf("opengl-cube: no connected connector found\n");
	return -1;
}

static int init_gbm(void)
{
	gbm.dev = gbm_create_device(drm.fd);
	if (!gbm.dev) {
		printf("opengl-cube: failed to create gbm device\n");
		return -1;
	}

	gbm.surface = gbm_surface_create(gbm.dev, drm.mode->hdisplay, drm.mode->vdisplay,
					 drm_fmt_to_gbm_fmt(drm.format),
					 GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING);
	if (!gbm.surface) {
		printf("opengl-cube: failed to create gbm surface\n");
		return -1;
	}

	printf("opengl-cube: init gbm success (%dx%d)\n", drm.mode->hdisplay,
	       drm.mode->vdisplay);
	return 0;
}

/* GLSL ES 300 ports of upstream vertex.glsl / fragment.glsl. `#version` must be
 * the first token, so these strings deliberately start flush. */
static const char *vertex_shader_source =
	"#version 300 es\n"
	"layout(location = 0) in vec3 pos;\n"
	"layout(location = 1) in vec3 vertex_color;\n"
	"uniform mat4 transform;\n"
	"out vec3 color;\n"
	"void main() {\n"
	"  gl_Position = transform * vec4(pos, 1.0);\n"
	"  color = vertex_color;\n"
	"}\n";

static const char *fragment_shader_source =
	"#version 300 es\n"
	"precision mediump float;\n"
	"in vec3 color;\n"
	"out vec4 frag_color;\n"
	"void main() {\n"
	"  frag_color = vec4(color, 1.0);\n"
	"}\n";

static int compile_shader(GLenum type, const char *source, GLuint *out)
{
	GLuint shader = glCreateShader(type);
	glShaderSource(shader, 1, &source, NULL);
	glCompileShader(shader);

	GLint status = 0;
	glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
	if (!status) {
		GLint len = 0;
		glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &len);
		if (len > 1) {
			char *log = malloc(len);
			glGetShaderInfoLog(shader, len, NULL, log);
			printf("opengl-cube: shader compile failed: %s\n", log);
			free(log);
		} else {
			printf("opengl-cube: shader compile failed (no log)\n");
		}
		return -1;
	}

	*out = shader;
	return 0;
}

static int init_egl(void)
{
	static const EGLint context_attribs[] = {
		EGL_CONTEXT_CLIENT_VERSION, 3,
		EGL_NONE
	};

	/* Upstream enables GL_DEPTH_TEST, so unlike kmscube this needs a depth
	 * buffer in the config or back faces punch through. */
	static const EGLint config_attribs[] = {
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
		EGL_RED_SIZE, 1,
		EGL_GREEN_SIZE, 1,
		EGL_BLUE_SIZE, 1,
		EGL_ALPHA_SIZE, 0,
		EGL_DEPTH_SIZE, 16,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
		EGL_NONE
	};

	EGLint major, minor, n;

	gl.display = eglGetDisplay(gbm.dev);
	if (gl.display == EGL_NO_DISPLAY) {
		printf("opengl-cube: eglGetDisplay failed\n");
		return -1;
	}

	if (!eglInitialize(gl.display, &major, &minor)) {
		printf("opengl-cube: eglInitialize failed\n");
		return -1;
	}

	printf("opengl-cube: EGL %d.%d \"%s\"\n", major, minor,
	       eglQueryString(gl.display, EGL_VERSION));

	if (!eglBindAPI(EGL_OPENGL_ES_API)) {
		printf("opengl-cube: failed to bind EGL_OPENGL_ES_API\n");
		return -1;
	}

	if (!eglChooseConfig(gl.display, config_attribs, &gl.config, 1, &n) || n != 1) {
		printf("opengl-cube: failed to choose an ES3 config with depth\n");
		return -1;
	}

	gl.context = eglCreateContext(gl.display, gl.config, EGL_NO_CONTEXT, context_attribs);
	if (gl.context == EGL_NO_CONTEXT) {
		printf("opengl-cube: failed to create ES3 context\n");
		return -1;
	}

	gl.surface = eglCreateWindowSurface(gl.display, gl.config,
					    (EGLNativeWindowType)gbm.surface, NULL);
	if (gl.surface == EGL_NO_SURFACE) {
		printf("opengl-cube: failed to create egl surface\n");
		return -1;
	}

	if (!eglMakeCurrent(gl.display, gl.surface, gl.surface, gl.context)) {
		printf("opengl-cube: eglMakeCurrent failed\n");
		return -1;
	}

	printf("opengl-cube: GL_RENDERER \"%s\"\n", (const char *)glGetString(GL_RENDERER));
	return 0;
}

/* ------------------------------------------------------------------ *
 * Renderer — c2d7fa/opengl-cube
 * ------------------------------------------------------------------ */

static const unsigned int triangles = 6 * 2;
static const unsigned int vertices_index = 0;
static const unsigned int colors_index = 1;

static int init_cube(void)
{
	float vertices[] = {
		/* Front face */
		 0.5f,  0.5f,  0.5f,
		-0.5f,  0.5f,  0.5f,
		-0.5f, -0.5f,  0.5f,
		 0.5f, -0.5f,  0.5f,

		/* Back face */
		 0.5f,  0.5f, -0.5f,
		-0.5f,  0.5f, -0.5f,
		-0.5f, -0.5f, -0.5f,
		 0.5f, -0.5f, -0.5f,
	};

	float vertex_colors[] = {
		1.0f, 0.4f, 0.6f,
		1.0f, 0.9f, 0.2f,
		0.7f, 0.3f, 0.8f,
		0.5f, 0.3f, 1.0f,

		0.2f, 0.6f, 1.0f,
		0.6f, 1.0f, 0.4f,
		0.6f, 0.8f, 0.8f,
		0.4f, 0.8f, 0.8f,
	};

	unsigned short triangle_indices[] = {
		0, 1, 2,  2, 3, 0,   /* Front  */
		0, 3, 7,  7, 4, 0,   /* Right  */
		2, 6, 7,  7, 3, 2,   /* Bottom */
		1, 5, 6,  6, 2, 1,   /* Left   */
		4, 7, 6,  6, 5, 4,   /* Back   */
		5, 1, 0,  0, 4, 5,   /* Top    */
	};

	glEnable(GL_DEPTH_TEST);

	glGenVertexArrays(1, &gl.vao);
	glBindVertexArray(gl.vao);

	GLuint triangles_ebo;
	glGenBuffers(1, &triangles_ebo);
	glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, triangles_ebo);
	glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof triangle_indices, triangle_indices,
		     GL_STATIC_DRAW);

	GLuint vertices_vbo;
	glGenBuffers(1, &vertices_vbo);
	glBindBuffer(GL_ARRAY_BUFFER, vertices_vbo);
	glBufferData(GL_ARRAY_BUFFER, sizeof vertices, vertices, GL_STATIC_DRAW);
	glVertexAttribPointer(vertices_index, 3, GL_FLOAT, GL_FALSE, 0, NULL);
	glEnableVertexAttribArray(vertices_index);

	GLuint colors_vbo;
	glGenBuffers(1, &colors_vbo);
	glBindBuffer(GL_ARRAY_BUFFER, colors_vbo);
	glBufferData(GL_ARRAY_BUFFER, sizeof vertex_colors, vertex_colors, GL_STATIC_DRAW);
	glVertexAttribPointer(colors_index, 3, GL_FLOAT, GL_FALSE, 0, NULL);
	glEnableVertexAttribArray(colors_index);

	glBindVertexArray(0);
	glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
	glBindBuffer(GL_ARRAY_BUFFER, 0);

	GLuint vertex_shader, fragment_shader;
	if (compile_shader(GL_VERTEX_SHADER, vertex_shader_source, &vertex_shader) ||
	    compile_shader(GL_FRAGMENT_SHADER, fragment_shader_source, &fragment_shader))
		return -1;

	gl.program = glCreateProgram();
	glAttachShader(gl.program, vertex_shader);
	glAttachShader(gl.program, fragment_shader);
	glLinkProgram(gl.program);

	GLint status = 0;
	glGetProgramiv(gl.program, GL_LINK_STATUS, &status);
	if (!status) {
		GLint len = 0;
		glGetProgramiv(gl.program, GL_INFO_LOG_LENGTH, &len);
		if (len > 1) {
			char *log = malloc(len);
			glGetProgramInfoLog(gl.program, len, NULL, log);
			printf("opengl-cube: program link failed: %s\n", log);
			free(log);
		}
		return -1;
	}

	gl.uniform_transform = glGetUniformLocation(gl.program, "transform");
	return 0;
}

static double now_seconds(void)
{
	static struct timespec start;
	static bool started = false;
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	if (!started) {
		start = ts;
		started = true;
	}
	return (double)(ts.tv_sec - start.tv_sec) +
	       (double)(ts.tv_nsec - start.tv_nsec) / 1e9;
}

/* Fraction through a loop of `duration` seconds, as upstream's animation(). */
static float animation(float duration)
{
	unsigned long ms_time = (unsigned long)(now_seconds() * 1000.0);
	unsigned int ms_duration = (unsigned int)(duration * 1000.0f);
	float ms_position = (float)(ms_time % ms_duration);

	return ms_position / (float)ms_duration;
}

/* Upstream reported FPS in the GLFW window title; there is no title here. */
static void report_fps(void)
{
	static double last_report = 0;
	static int frames = 0;

	double now = now_seconds();
	frames++;

	if (now - last_report > 2.0) {
		printf("opengl-cube: %.1f FPS\n", frames / (now - last_report));
		fflush(stdout);
		last_report = now;
		frames = 0;
	}
}

static void render(void)
{
	report_fps();

	glViewport(0, 0, gl.width, gl.height);
	glClearColor(0.1f, 0.12f, 0.2f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

	glUseProgram(gl.program);

	/* Squeeze the wider axis so the cube stays square in a non-square mode.
	 * Applied before the projection so it acts in clip space. */
	float sx = 1.0f, sy = 1.0f;
	if (gl.width >= gl.height)
		sx = (float)gl.height / (float)gl.width;
	else
		sy = (float)gl.width / (float)gl.height;

	struct mat4f transform = mat4f_identity;
	transform = mat4f_multiply(transform, mat4f_scale(sx, sy, 1.0f));
	transform = mat4f_multiply(transform, mat4f_perspective());
	transform = mat4f_multiply(transform, mat4f_translation(0, 0, -3));
	transform = mat4f_multiply(transform, mat4f_rotate_x(0.15f * pi));
	transform = mat4f_multiply(transform, mat4f_rotate_y(2 * pi * animation(4)));
	glUniformMatrix4fv(gl.uniform_transform, 1, GL_FALSE, mat4f_gl(&transform));

	glBindVertexArray(gl.vao);
	glDrawElements(GL_TRIANGLES, triangles * 3, GL_UNSIGNED_SHORT, NULL);
}

/* ------------------------------------------------------------------ *
 * Present loop
 * ------------------------------------------------------------------ */

static void drm_fb_destroy_callback(struct gbm_bo *bo, void *data)
{
	struct drm_fb *fb = data;
	(void)bo;

	if (fb->fb_id)
		drmModeRmFB(drm.fd, fb->fb_id);
	free(fb);
}

static struct drm_fb *drm_fb_get_from_bo(struct gbm_bo *bo)
{
	struct drm_fb *fb = gbm_bo_get_user_data(bo);
	uint32_t bo_handles[4] = { 0 }, offsets[4] = { 0 }, pitches[4] = { 0 };

	if (fb)
		return fb;

	fb = calloc(1, sizeof *fb);
	fb->bo = bo;

	uint32_t width = gbm_bo_get_width(bo);
	uint32_t height = gbm_bo_get_height(bo);
	pitches[0] = gbm_bo_get_stride(bo);
	bo_handles[0] = gbm_bo_get_handle(bo).u32;
	uint32_t format = gbm_bo_get_format(bo);

	if (drmModeAddFB2(drm.fd, width, height, format, bo_handles, pitches, offsets,
			  &fb->fb_id, 0)) {
		printf("opengl-cube: failed to create fb: %s\n", strerror(errno));
		free(fb);
		return NULL;
	}

	gbm_bo_set_user_data(bo, fb, drm_fb_destroy_callback);
	return fb;
}

static void page_flip_handler(int fd, unsigned int frame, unsigned int sec,
			      unsigned int usec, void *data)
{
	int *waiting_for_flip = data;
	(void)fd;
	(void)frame;
	(void)sec;
	(void)usec;

	*waiting_for_flip = *waiting_for_flip - 1;
}

static void print_usage(void)
{
	printf("Usage : opengl-cube <options>\n");
	printf("\t-h : Help\n");
	printf("\t-d /dev/dri/cardX : DRM device to be used [default /dev/dri/card0]\n");
	printf("\t-n <number> : Number of frames to render\n");
}

int main(int argc, char *argv[])
{
	fd_set fds;
	drmEventContext evctx = {
		.version = DRM_EVENT_CONTEXT_VERSION,
		.page_flip_handler = page_flip_handler,
	};
	struct gbm_bo *bo;
	struct drm_fb *fb;
	int frame_count = -1;
	int opt;

	while ((opt = getopt(argc, argv, "hd:n:")) != -1) {
		switch (opt) {
		case 'h':
			print_usage();
			return 0;
		case 'd':
			device = optarg;
			break;
		case 'n':
			frame_count = atoi(optarg);
			break;
		default:
			print_usage();
			return -1;
		}
	}

	if (init_drm()) {
		printf("opengl-cube: failed to initialize DRM\n");
		return -1;
	}

	FD_ZERO(&fds);
	FD_SET(drm.fd, &fds);

	if (init_gbm()) {
		printf("opengl-cube: failed to initialize GBM\n");
		return -1;
	}

	gl.width = drm.mode->hdisplay;
	gl.height = drm.mode->vdisplay;

	if (init_egl()) {
		printf("opengl-cube: failed to initialize EGL\n");
		return -1;
	}

	if (init_cube()) {
		printf("opengl-cube: failed to initialize cube\n");
		return -1;
	}

	/* First frame establishes the CRTC before flips can be queued. */
	render();
	eglSwapBuffers(gl.display, gl.surface);
	bo = gbm_surface_lock_front_buffer(gbm.surface);
	fb = drm_fb_get_from_bo(bo);
	if (!fb)
		return -1;

	if (drmModeSetCrtc(drm.fd, drm.crtc_id, fb->fb_id, 0, 0, &drm.connector_id, 1,
			   drm.mode)) {
		printf("opengl-cube: failed to set mode: %s\n", strerror(errno));
		return -1;
	}

	while (frame_count != 0) {
		int waiting_for_flip = 1;

		render();

		eglSwapBuffers(gl.display, gl.surface);
		struct gbm_bo *next_bo = gbm_surface_lock_front_buffer(gbm.surface);
		fb = drm_fb_get_from_bo(next_bo);
		if (!fb)
			return -1;

		if (drmModePageFlip(drm.fd, drm.crtc_id, fb->fb_id,
				    DRM_MODE_PAGE_FLIP_EVENT, &waiting_for_flip)) {
			printf("opengl-cube: failed to queue page flip: %s\n", strerror(errno));
			return -1;
		}

		while (waiting_for_flip) {
			int ret = select(drm.fd + 1, &fds, NULL, NULL, NULL);
			if (ret < 0) {
				printf("opengl-cube: select err: %s\n", strerror(errno));
				return ret;
			} else if (ret == 0) {
				printf("opengl-cube: select timeout!\n");
				return -1;
			} else if (FD_ISSET(0, &fds)) {
				continue;
			}
			drmHandleEvent(drm.fd, &evctx);
		}

		gbm_surface_release_buffer(gbm.surface, bo);
		bo = next_bo;

		if (frame_count >= 0)
			frame_count--;
	}

	printf("opengl-cube: exiting\n");
	return 0;
}
