/*
 * OpenGL Cube — c2d7fa/opengl-cube ported off GLFW/GLEW onto Wayland + EGL, so
 * it runs as a real client of Wawona's compositor (wl_surface + xdg-shell +
 * wl_egl_window), not on iland's virtual KMS.
 *
 * This is the distinction between the three cube clients:
 *   kmscube      — iland's userspace DRM/KMS/GBM, direct scanout emulation.
 *   opengl-cube  — this file: OpenGL ES over Wayland-EGL on the compositor.
 *   vkcube       — Vulkan over Wayland on the compositor.
 *
 * The Wayland-EGL winsys itself lives in wwn-iland (shims/egl/src/egl_wayland.c
 * + shims/wayland-egl): eglSwapBuffers posts the IOSurface ANGLE rendered into
 * as a linux-dmabuf wl_buffer, so this client is zero-copy to the compositor.
 *
 * Renderer (geometry, colours, shaders, animation, matrix.h) comes from
 * https://github.com/c2d7fa/opengl-cube @ daba3b8, CC0-1.0 (see ./LICENSE).
 * It is a genuinely different demo from kmscube: flat vertex-interpolated
 * colours on a dark blue ground, versus kmscube's diffuse-lit cube.
 *
 * Port notes, all forced by the target rather than preference:
 *  - GLFW window/context/swap  -> xdg_toplevel + wl_egl_window + eglSwapBuffers.
 *  - GLEW                      -> ANGLE GLES3 headers.
 *  - GLSL 450                  -> GLSL ES 300 (adds a precision qualifier).
 *  - Shaders read from vertex.glsl / fragment.glsl at runtime -> embedded, since
 *    there is no cwd beside the binary once this is linked into an app bundle.
 *  - glfwGetTime               -> CLOCK_MONOTONIC.
 *  - Upstream's projection assumes the 800x800 window it created; the toplevel
 *    can be any size, so aspect is corrected with a scale matrix in front of the
 *    projection. matrix.h itself is kept verbatim.
 */

#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <wayland-client.h>
#include <wayland-egl-core.h>

#include "xdg-shell-client-protocol.h"

#include <EGL/egl.h>
#include <GLES3/gl3.h>

#include "matrix.h"

#define WWN_CUBE_HUD_GL 1
#include "../wwn_cube_hud.h"
#include "../wwn_cube_hud.c"

/* Provided by wwn-iland's EGL shim. Declared rather than pulled from a vendor
 * EGL header so the client does not depend on which extension headers ANGLE
 * happens to install. */
extern EGLDisplay eglGetPlatformDisplayEXT(EGLenum platform,
                                           void *native_display,
                                           const EGLint *attrib_list);
#ifndef EGL_PLATFORM_WAYLAND_KHR
#define EGL_PLATFORM_WAYLAND_KHR 0x31D8
#endif

#define DEFAULT_WIDTH  800
#define DEFAULT_HEIGHT 800

static struct {
	struct wl_display *display;
	struct wl_registry *registry;
	struct wl_compositor *compositor;
	struct xdg_wm_base *wm_base;
	struct wl_surface *surface;
	struct xdg_surface *xdg_surface;
	struct xdg_toplevel *toplevel;
	struct wl_egl_window *egl_window;
	bool configured;
	bool running;
} wl;

static struct {
	EGLDisplay display;
	EGLConfig config;
	EGLContext context;
	EGLSurface surface;

	GLuint program;
	GLuint vao;
	GLint uniform_transform;

	int width;
	int height;
} gl = {
	.width = DEFAULT_WIDTH,
	.height = DEFAULT_HEIGHT,
};

static struct wwn_cube_hud g_hud;

/* ------------------------------------------------------------------ *
 * Wayland host
 * ------------------------------------------------------------------ */

static void wm_base_ping(void *data, struct xdg_wm_base *wm_base,
			 uint32_t serial)
{
	(void)data;
	xdg_wm_base_pong(wm_base, serial);
}

static const struct xdg_wm_base_listener wm_base_listener = {
	wm_base_ping,
};

static void registry_global(void *data, struct wl_registry *registry,
			    uint32_t name, const char *interface,
			    uint32_t version)
{
	(void)data;

	if (strcmp(interface, "wl_compositor") == 0) {
		/* v4 for wl_surface.damage_buffer, which the winsys prefers. */
		uint32_t want = version < 4 ? version : 4;
		wl.compositor = wl_registry_bind(registry, name,
						 &wl_compositor_interface, want);
	} else if (strcmp(interface, "xdg_wm_base") == 0) {
		wl.wm_base = wl_registry_bind(registry, name,
					      &xdg_wm_base_interface, 1);
		xdg_wm_base_add_listener(wl.wm_base, &wm_base_listener, NULL);
	}
}

static void registry_global_remove(void *data, struct wl_registry *registry,
				   uint32_t name)
{
	(void)data;
	(void)registry;
	(void)name;
}

static const struct wl_registry_listener registry_listener = {
	registry_global,
	registry_global_remove,
};

static void xdg_surface_configure(void *data, struct xdg_surface *xdg_surface,
				  uint32_t serial)
{
	(void)data;
	xdg_surface_ack_configure(xdg_surface, serial);
	wl.configured = true;
}

static const struct xdg_surface_listener xdg_surface_listener = {
	xdg_surface_configure,
};

static void toplevel_configure(void *data, struct xdg_toplevel *toplevel,
			       int32_t width, int32_t height,
			       struct wl_array *states)
{
	(void)data;
	(void)toplevel;
	(void)states;

	/* 0x0 means "pick your own size" — keep what we have. */
	if (width <= 0 || height <= 0)
		return;
	if (width == gl.width && height == gl.height)
		return;

	gl.width = width;
	gl.height = height;
	if (wl.egl_window)
		wl_egl_window_resize(wl.egl_window, width, height, 0, 0);
}

static void toplevel_close(void *data, struct xdg_toplevel *toplevel)
{
	(void)data;
	(void)toplevel;
	wl.running = false;
}

static const struct xdg_toplevel_listener toplevel_listener = {
	toplevel_configure,
	toplevel_close,
};

static int init_wayland(void)
{
	wl.display = wl_display_connect(NULL);
	if (!wl.display) {
		printf("opengl-cube: wl_display_connect failed (WAYLAND_DISPLAY set?)\n");
		return -1;
	}

	wl.registry = wl_display_get_registry(wl.display);
	wl_registry_add_listener(wl.registry, &registry_listener, NULL);
	wl_display_roundtrip(wl.display);

	if (!wl.compositor || !wl.wm_base) {
		printf("opengl-cube: compositor lacks wl_compositor/xdg_wm_base\n");
		return -1;
	}

	wl.surface = wl_compositor_create_surface(wl.compositor);
	wl.xdg_surface = xdg_wm_base_get_xdg_surface(wl.wm_base, wl.surface);
	xdg_surface_add_listener(wl.xdg_surface, &xdg_surface_listener, NULL);

	wl.toplevel = xdg_surface_get_toplevel(wl.xdg_surface);
	xdg_toplevel_add_listener(wl.toplevel, &toplevel_listener, NULL);
	xdg_toplevel_set_title(wl.toplevel, "OpenGL Cube");
	xdg_toplevel_set_app_id(wl.toplevel, "org.wawona.opengl-cube");

	/* Roleless commit, then wait for the first configure before attaching. */
	wl_surface_commit(wl.surface);
	while (!wl.configured) {
		if (wl_display_dispatch(wl.display) < 0) {
			printf("opengl-cube: disconnected before first configure\n");
			return -1;
		}
	}

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

	gl.display = eglGetPlatformDisplayEXT(EGL_PLATFORM_WAYLAND_KHR,
					      wl.display, NULL);
	if (gl.display == EGL_NO_DISPLAY) {
		printf("opengl-cube: no EGL Wayland platform display\n");
		return -1;
	}

	if (!eglInitialize(gl.display, &major, &minor)) {
		printf("opengl-cube: eglInitialize failed "
		       "(compositor without linux-dmabuf?)\n");
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

	gl.context = eglCreateContext(gl.display, gl.config, EGL_NO_CONTEXT,
				      context_attribs);
	if (gl.context == EGL_NO_CONTEXT) {
		printf("opengl-cube: failed to create ES3 context\n");
		return -1;
	}

	wl.egl_window = wl_egl_window_create(wl.surface, gl.width, gl.height);
	if (!wl.egl_window) {
		printf("opengl-cube: wl_egl_window_create failed\n");
		return -1;
	}

	gl.surface = eglCreateWindowSurface(gl.display, gl.config,
					    (EGLNativeWindowType)wl.egl_window,
					    NULL);
	if (gl.surface == EGL_NO_SURFACE) {
		printf("opengl-cube: eglCreateWindowSurface failed\n");
		return -1;
	}

	if (!eglMakeCurrent(gl.display, gl.surface, gl.surface, gl.context)) {
		printf("opengl-cube: eglMakeCurrent failed\n");
		return -1;
	}

	printf("opengl-cube: GL_RENDERER \"%s\"\n", glGetString(GL_RENDERER));

	wwn_cube_hud_init(&g_hud);
	wwn_cube_hud_set_client(&g_hud, "opengl-cube");
	g_hud.kms = 0;
	g_hud.drm = 0;
	g_hud.gbm = 0;
	wwn_cube_hud_fill_gl(&g_hud);

	/* A config with EGL_DEPTH_SIZE does not guarantee the surface got a depth
	 * attachment, and without one GL_DEPTH_TEST silently does nothing and the
	 * cube's far faces draw over its near ones. Say so rather than let it look
	 * like a bug in the cube. */
	GLint depth_type = GL_NONE;
	glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, GL_DEPTH,
					      GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE,
					      &depth_type);
	printf("opengl-cube: default framebuffer depth attachment: %s\n",
	       depth_type == GL_NONE ? "NONE (depth test will not work)"
				     : "present");
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

/* >= 0 pins the animation so a frame can be rendered twice identically; used
 * only by the depth self-test. */
static float frozen_animation = -1.0f;

/* Fraction through a loop of `duration` seconds, as upstream's animation(). */
static float animation(float duration)
{
	if (frozen_animation >= 0.0f)
		return frozen_animation;

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

static void render(void);

/* WWN_CUBE_DEPTH_SELFTEST=1: render one frame twice, with and without the depth
 * test, and compare. A surface whose depth attachment exists but is not actually
 * bound produces byte-identical output both ways, which on screen looks like
 * wrong face culling rather than like a missing depth buffer. */
static void depth_selftest(void)
{
	size_t n = (size_t)gl.width * (size_t)gl.height * 4;
	unsigned char *with = malloc(n), *without = malloc(n);
	if (!with || !without) {
		free(with);
		free(without);
		return;
	}

	frozen_animation = 0.1f;

	render();
	glFinish();
	glReadPixels(0, 0, gl.width, gl.height, GL_RGBA, GL_UNSIGNED_BYTE, with);

	glDisable(GL_DEPTH_TEST);
	render();
	glFinish();
	glReadPixels(0, 0, gl.width, gl.height, GL_RGBA, GL_UNSIGNED_BYTE, without);
	glEnable(GL_DEPTH_TEST);

	printf("opengl-cube: depth self-test: %s\n",
	       memcmp(with, without, n) != 0
		   ? "depth test changes the image (working)"
		   : "IDENTICAL with and without GL_DEPTH_TEST — depth is not applied");
	fflush(stdout);

	frozen_animation = -1.0f;
	free(with);
	free(without);
}

static void render(void)
{
	report_fps();

	glViewport(0, 0, gl.width, gl.height);
	glClearColor(0.1f, 0.12f, 0.2f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

	glUseProgram(gl.program);

	/* Squeeze the wider axis so the cube stays square in a non-square
	 * toplevel. Applied before the projection so it acts in clip space. */
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

	wwn_cube_hud_tick(&g_hud);
	wwn_cube_hud_draw_gl(gl.width, gl.height, &g_hud);
}

/* ------------------------------------------------------------------ *
 * Frame loop
 * ------------------------------------------------------------------ */

static void frame_done(void *data, struct wl_callback *callback, uint32_t time);

static const struct wl_callback_listener frame_listener = {
	frame_done,
};

static void draw_frame(void)
{
	render();

	/* Request the next frame before the commit that eglSwapBuffers issues,
	 * so the callback is part of the same surface state. */
	struct wl_callback *callback = wl_surface_frame(wl.surface);
	wl_callback_add_listener(callback, &frame_listener, NULL);

	eglSwapBuffers(gl.display, gl.surface);
}

static void frame_done(void *data, struct wl_callback *callback, uint32_t time)
{
	(void)data;
	(void)time;
	wl_callback_destroy(callback);
	draw_frame();
}

int main(int argc, char *argv[])
{
	(void)argc;
	(void)argv;

	wl.running = true;

	if (init_wayland() < 0)
		return -1;
	if (init_egl() < 0)
		return -1;
	if (init_cube() < 0)
		return -1;

	printf("opengl-cube: running as a Wayland client at %dx%d\n",
	       gl.width, gl.height);

	if (getenv("WWN_CUBE_DEPTH_SELFTEST"))
		depth_selftest();
	fflush(stdout);

	draw_frame();

	while (wl.running && wl_display_dispatch(wl.display) != -1)
		;

	if (gl.display != EGL_NO_DISPLAY) {
		eglMakeCurrent(gl.display, EGL_NO_SURFACE, EGL_NO_SURFACE,
			       EGL_NO_CONTEXT);
		if (gl.surface != EGL_NO_SURFACE)
			eglDestroySurface(gl.display, gl.surface);
		if (gl.context != EGL_NO_CONTEXT)
			eglDestroyContext(gl.display, gl.context);
		eglTerminate(gl.display);
	}
	if (wl.egl_window)
		wl_egl_window_destroy(wl.egl_window);
	if (wl.toplevel)
		xdg_toplevel_destroy(wl.toplevel);
	if (wl.xdg_surface)
		xdg_surface_destroy(wl.xdg_surface);
	if (wl.surface)
		wl_surface_destroy(wl.surface);
	if (wl.display)
		wl_display_disconnect(wl.display);

	return 0;
}
