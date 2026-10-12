#include "wwn_cube_hud.h"

#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/time.h>

#ifdef WWN_CUBE_HUD_GL
/* GLES headers come from the including cube (ANGLE GLES2/GLES3). */
#endif

static const uint64_t wwn_hud_font[95] = {
    0x0000000000000000ULL, 0x0000040004040400ULL, 0x00000000000a0a00ULL,
    0x0000040e040e0400ULL, 0x0000040e040e0400ULL, 0x00000a0204080a00ULL,
    0x00000c0a040a0400ULL, 0x0000000000040400ULL, 0x0000080404040800ULL,
    0x0000020404040200ULL, 0x0000000a040a0000ULL, 0x000000040e040000ULL,
    0x0000020400000000ULL, 0x000000000e000000ULL, 0x0000040000000000ULL,
    0x0000020204080800ULL, 0x00000e0a0a0a0e00ULL, 0x00000e0404060400ULL,
    0x00000e020e080e00ULL, 0x00000e080e080e00ULL, 0x000008080e0a0a00ULL,
    0x00000e080e020e00ULL, 0x00000e0a0e020e00ULL, 0x0000040404080e00ULL,
    0x00000e0a0e0a0e00ULL, 0x00000e080e0a0e00ULL, 0x0000000400040000ULL,
    0x0000020400040000ULL, 0x0000080402040800ULL, 0x0000000e000e0000ULL,
    0x0000020408040200ULL, 0x0000040004080400ULL, 0x00000c020e0a0400ULL,
    0x00000a0a0e0a0400ULL, 0x0000060a060a0600ULL, 0x00000c0202020c00ULL,
    0x0000060a0a0a0600ULL, 0x00000e0206020e00ULL, 0x0000020206020e00ULL,
    0x00000c0a0a020c00ULL, 0x00000a0a0e0a0a00ULL, 0x00000e0404040e00ULL,
    0x0000040a08080800ULL, 0x00000a0a060a0a00ULL, 0x00000e0202020200ULL,
    0x00000a0a0e0e0a00ULL, 0x00000a0e0e0e0a00ULL, 0x0000040a0a0a0400ULL,
    0x00000202060a0600ULL, 0x00000c0e0a0a0400ULL, 0x00000a0a060a0600ULL,
    0x0000060804020c00ULL, 0x0000040404040e00ULL, 0x00000c0a0a0a0a00ULL,
    0x0000040a0a0a0a00ULL, 0x00000a0e0e0a0a00ULL, 0x00000a0a040a0a00ULL,
    0x00000404040a0a00ULL, 0x00000e0204080e00ULL, 0x00000c0404040c00ULL,
    0x0000080804020200ULL, 0x0000060404040600ULL, 0x00000000000a0400ULL,
    0x00000e0000000000ULL, 0x0000000000080400ULL, 0x00000a0a0e0a0400ULL,
    0x0000060a060a0600ULL, 0x00000c0202020c00ULL, 0x0000060a0a0a0600ULL,
    0x00000e0206020e00ULL, 0x0000020206020e00ULL, 0x00000c0a0a020c00ULL,
    0x00000a0a0e0a0a00ULL, 0x00000e0404040e00ULL, 0x0000040a08080800ULL,
    0x00000a0a060a0a00ULL, 0x00000e0202020200ULL, 0x00000a0a0e0e0a00ULL,
    0x00000a0e0e0e0a00ULL, 0x0000040a0a0a0400ULL, 0x00000202060a0600ULL,
    0x00000c0e0a0a0400ULL, 0x00000a0a060a0600ULL, 0x0000060804020c00ULL,
    0x0000040404040e00ULL, 0x00000c0a0a0a0a00ULL, 0x0000040a0a0a0a00ULL,
    0x00000a0e0e0a0a00ULL, 0x00000a0a040a0a00ULL, 0x00000404040a0a00ULL,
    0x00000e0204080e00ULL, 0x0000080406040800ULL, 0x0000040404040400ULL,
    0x000002040c040200ULL, 0x00000000060c0000ULL,
};

static double hud_now(void)
{
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return (double)tv.tv_sec + (double)tv.tv_usec * 1e-6;
}

static void hud_copy_trunc(char *dst, size_t n, const char *src)
{
  if (!dst || n == 0)
    return;
  if (!src || !src[0]) {
    dst[0] = '-';
    dst[1] = 0;
    return;
  }
  snprintf(dst, n, "%s", src);
}

static const char *hud_yn(int v) { return v ? "yes" : "no"; }

static void hud_classify_gl_renderer(char *dst, size_t n, const char *renderer)
{
  if (!renderer || !renderer[0]) {
    hud_copy_trunc(dst, n, "-");
    return;
  }
  if (strstr(renderer, "ANGLE"))
    snprintf(dst, n, "ANGLE");
  else if (strstr(renderer, "SwiftShader") || strstr(renderer, "swiftshader"))
    snprintf(dst, n, "SwiftShader");
  else if (strstr(renderer, "llvmpipe") || strstr(renderer, "llvmpipe"))
    snprintf(dst, n, "llvmpipe");
  else
    hud_copy_trunc(dst, n, renderer);
}

static void hud_classify_vk(char *dst, size_t n, const char *path,
                            const char *device)
{
  const char *icd = NULL;
  if (path) {
    if (strstr(path, "KosmicKrisp") || strstr(path, "kosmickrisp"))
      icd = "KosmicKrisp";
    else if (strstr(path, "MoltenVK") || strstr(path, "moltenvk"))
      icd = "MoltenVK";
    else if (strstr(path, "swiftshader") || strstr(path, "SwiftShader"))
      icd = "SwiftShader";
    else if (strstr(path, "libvulkan"))
      icd = "system Vulkan";
  }
  if (icd && device && device[0] && strcmp(device, "-") != 0)
    snprintf(dst, n, "%s (%s)", icd, device);
  else if (icd)
    snprintf(dst, n, "%s", icd);
  else
    hud_copy_trunc(dst, n, device);
}

WWN_CUBE_HUD_API void wwn_cube_hud_init(struct wwn_cube_hud *h)
{
  if (!h)
    return;
  memset(h, 0, sizeof(*h));
  hud_copy_trunc(h->client, sizeof(h->client), "-");
  hud_copy_trunc(h->vulkan_backend, sizeof(h->vulkan_backend), "-");
  hud_copy_trunc(h->opengl_backend, sizeof(h->opengl_backend), "-");
  h->fps_t0 = hud_now();
}

WWN_CUBE_HUD_API void wwn_cube_hud_set_client(struct wwn_cube_hud *h,
                                               const char *name)
{
  if (!h)
    return;
  hud_copy_trunc(h->client, sizeof(h->client), name);
}

WWN_CUBE_HUD_API void wwn_cube_hud_tick(struct wwn_cube_hud *h)
{
  if (!h)
    return;
  h->fps_frames++;
  double now = hud_now();
  double dt = now - h->fps_t0;
  if (dt >= 0.5) {
    h->fps = (float)(h->fps_frames / dt);
    h->fps_frames = 0;
    h->fps_t0 = now;
  }
}

WWN_CUBE_HUD_API void wwn_cube_hud_fill_gl(struct wwn_cube_hud *h)
{
#ifdef WWN_CUBE_HUD_GL
  if (!h)
    return;
  h->opengl = 1;
  const GLubyte *r = glGetString(GL_RENDERER);
  hud_classify_gl_renderer(h->opengl_backend, sizeof(h->opengl_backend),
                           r ? (const char *)r : NULL);
#else
  (void)h;
#endif
}

WWN_CUBE_HUD_API void wwn_cube_hud_set_vk(struct wwn_cube_hud *h,
                                           const char *provider_path,
                                           const char *device_name)
{
  if (!h)
    return;
  h->vulkan = 1;
  hud_classify_vk(h->vulkan_backend, sizeof(h->vulkan_backend), provider_path,
                  device_name);
}

static uint64_t glyph_bits(int ch)
{
  if (ch < 32 || ch > 126)
    ch = '?';
  return wwn_hud_font[ch - 32];
}

static void put_px(uint8_t *rgba, int width, int height, int stride, int x,
                   int y, uint8_t r, uint8_t g, uint8_t b, uint8_t a, int bgra)
{
  if (x < 0 || y < 0 || x >= width || y >= height)
    return;
  uint8_t *p = rgba + (size_t)y * (size_t)stride + (size_t)x * 4u;
  if (bgra) {
    p[0] = b;
    p[1] = g;
    p[2] = r;
    p[3] = a;
  } else {
    p[0] = r;
    p[1] = g;
    p[2] = b;
    p[3] = a;
  }
}

static void draw_char(uint8_t *rgba, int width, int height, int stride, int x,
                      int y, int scale, int ch, int bgra)
{
  uint64_t bits = glyph_bits(ch);
  int row, col, sy, sx;
  for (row = 0; row < 8; row++) {
    unsigned g = (unsigned)((bits >> (8 * row)) & 0xFFu);
    for (col = 0; col < 8; col++) {
      if (!(g & (1u << col)))
        continue;
      for (sy = 0; sy < scale; sy++)
        for (sx = 0; sx < scale; sx++)
          put_px(rgba, width, height, stride, x + col * scale + sx,
                 y + row * scale + sy, 255, 255, 210, 255, bgra);
    }
  }
}

static void hud_format(const struct wwn_cube_hud *h, char *out, size_t n)
{
  snprintf(out, n,
           "%s  %.0f fps\n"
           "kms %s  drm %s  gbm %s\n"
           "vulkan %s  %s\n"
           "OpenGL %s  %s",
           h ? h->client : "-",
           h ? h->fps : 0.f,
           hud_yn(h ? h->kms : 0), hud_yn(h ? h->drm : 0),
           hud_yn(h ? h->gbm : 0),
           hud_yn(h ? h->vulkan : 0), h ? h->vulkan_backend : "-",
           hud_yn(h ? h->opengl : 0), h ? h->opengl_backend : "-");
}

static int hud_pad(int scale)
{
  int p = 4 + scale;
  if (p < 6)
    p = 6;
  if (p > 14)
    p = 14;
  return p;
}

/* Wrap on spaces. Hard-split tokens that are longer than max_chars so a long
 * GL renderer string cannot blow past the surface. */
static void hud_wrap_text(const char *in, char *out, size_t n, int max_chars)
{
  size_t o = 0;
  int col = 0;

  if (!out || n == 0)
    return;
  if (max_chars < 8)
    max_chars = 8;
  if (!in)
    in = "";

  while (*in && o + 1 < n) {
    const char *w;
    int wl;

    if (*in == '\n') {
      out[o++] = '\n';
      col = 0;
      in++;
      continue;
    }
    while (*in == ' ')
      in++;
    if (!*in)
      break;
    w = in;
    while (*in && *in != ' ' && *in != '\n')
      in++;
    wl = (int)(in - w);
    if (col > 0 && col + 1 + wl > max_chars) {
      out[o++] = '\n';
      col = 0;
      if (o + 1 >= n)
        break;
    }
    if (col > 0) {
      out[o++] = ' ';
      col++;
    }
    if (wl > max_chars && col == 0) {
      while (wl > 0 && o + 1 < n) {
        int take = wl > max_chars ? max_chars : wl;
        memcpy(out + o, w, (size_t)take);
        o += (size_t)take;
        w += take;
        wl -= take;
        col = take;
        if (wl > 0 && o + 1 < n) {
          out[o++] = '\n';
          col = 0;
        }
      }
    } else if (o + (size_t)wl < n) {
      memcpy(out + o, w, (size_t)wl);
      o += (size_t)wl;
      col += wl;
    } else {
      break;
    }
  }
  out[o] = 0;
}

static void hud_measure_text(const char *text, int scale, int *box_w,
                             int *box_h)
{
  const int pad = hud_pad(scale);
  const int gw = 8 * scale;
  const int gh = 8 * scale;
  int lines = 1, maxc = 0, cur = 0;
  const char *s;
  for (s = text ? text : ""; ; s++) {
    if (*s == '\n' || *s == 0) {
      if (cur > maxc)
        maxc = cur;
      cur = 0;
      if (!*s)
        break;
      lines++;
    } else {
      cur++;
    }
  }
  *box_w = pad * 2 + maxc * gw;
  *box_h = pad * 2 + lines * gh;
}

/* Pick a glyph scale that keeps the hub inside the surface. Recalculated every
 * frame so rotation / mode changes reflow. Cap height to the shorter side so a
 * portrait phone does not get a full-width Retina billboard. */
static int hud_fit_overlay(int fb_w, int fb_h, const char *src, char *wrapped,
                           size_t wrapped_n, int *box_w, int *box_h)
{
  int min_side = fb_w < fb_h ? fb_w : fb_h;
  int max_w = fb_w * 62 / 100;
  int max_h = min_side * 20 / 100;
  int fb_h_cap = fb_h * 18 / 100;
  int scale;

  if (fb_h_cap > 0 && fb_h_cap < max_h)
    max_h = fb_h_cap;
  if (max_w < 48)
    max_w = fb_w > 8 ? fb_w - 8 : fb_w;
  if (max_h < 40)
    max_h = fb_h / 5;
  if (max_h < 24)
    max_h = fb_h > 8 ? fb_h - 8 : fb_h;

  /* Retina phones have a short side > 1000px. Starting at min_side/320 made
   * a billboard. Fit to the plate instead, then shrink until it is inside. */
  scale = min_side / 480;
  if (scale < 1)
    scale = 1;
  if (scale > 3)
    scale = 3;

  for (;;) {
    int pad = hud_pad(scale);
    int max_chars = (8 * scale) > 0 ? (max_w - 2 * pad) / (8 * scale) : 8;
    if (max_chars < 8)
      max_chars = 8;
    hud_wrap_text(src, wrapped, wrapped_n, max_chars);
    hud_measure_text(wrapped, scale, box_w, box_h);
    if (*box_w <= max_w && *box_h <= max_h)
      break;
    if (scale <= 1)
      break;
    scale--;
  }
  if (*box_w > fb_w)
    *box_w = fb_w;
  if (*box_h > fb_h)
    *box_h = fb_h;
  return scale;
}

static void hud_blit_rgba_scaled(uint8_t *rgba, int width, int height,
                                 int stride, const struct wwn_cube_hud *h,
                                 int bgra, int scale, const char *text)
{
  if (!rgba || width <= 0 || height <= 0 || stride < width * 4)
    return;
  if (scale < 1)
    scale = 1;
  if (!text)
    text = "";
  (void)h;

  const int pad = hud_pad(scale);
  const int gw = 8 * scale;
  const int gh = 8 * scale;
  int box_w = 0, box_h = 0;
  hud_measure_text(text, scale, &box_w, &box_h);
  if (box_w > width)
    box_w = width;
  if (box_h > height)
    box_h = height;

  int x, y;
  for (y = 0; y < box_h; y++) {
    for (x = 0; x < box_w; x++) {
      uint8_t *p = rgba + (size_t)y * (size_t)stride + (size_t)x * 4u;
      p[0] = (uint8_t)(p[0] / 5);
      p[1] = (uint8_t)(p[1] / 5);
      p[2] = (uint8_t)(p[2] / 5);
      p[3] = 220;
    }
  }

  int cx = pad, cy = pad;
  const char *s;
  for (s = text; *s; s++) {
    if (*s == '\n') {
      cx = pad;
      cy += gh;
      continue;
    }
    draw_char(rgba, width, height, stride, cx, cy, scale, (unsigned char)*s,
              bgra);
    cx += gw;
  }
}

WWN_CUBE_HUD_API void wwn_cube_hud_blit_rgba(uint8_t *rgba, int width,
                                              int height, int stride,
                                              const struct wwn_cube_hud *h,
                                              int bgra)
{
  char raw[512], wrapped[768];
  int scale, box_w = 0, box_h = 0;
  hud_format(h, raw, sizeof(raw));
  scale = hud_fit_overlay(width, height, raw, wrapped, sizeof(wrapped), &box_w,
                          &box_h);
  (void)box_w;
  (void)box_h;
  hud_blit_rgba_scaled(rgba, width, height, stride, h, bgra, scale, wrapped);
}

#ifdef WWN_CUBE_HUD_GL

static GLuint hud_prog;
static GLuint hud_tex;
static GLuint hud_vbo;
static int hud_tex_w, hud_tex_h;
static uint8_t *hud_scratch;
static int hud_scratch_n;

static const char *hud_vs =
    "#version 100\n"
    "attribute vec2 a_pos;\n"
    "attribute vec2 a_uv;\n"
    "varying vec2 v_uv;\n"
    "void main() {\n"
    "  gl_Position = vec4(a_pos, 0.0, 1.0);\n"
    "  v_uv = a_uv;\n"
    "}\n";

/* ANGLE on Apple uploads CPU row 0 as texture v=0 (top). Desktop GL treats
 * that row as v=0 = bottom. Flip V on Apple so the hub is upright after the
 * same NDC quad the Linux path uses. */
#if defined(__APPLE__)
static const char *hud_fs =
    "#version 100\n"
    "precision mediump float;\n"
    "varying vec2 v_uv;\n"
    "uniform sampler2D u_tex;\n"
    "void main() {\n"
    "  gl_FragColor = texture2D(u_tex, vec2(v_uv.x, 1.0 - v_uv.y));\n"
    "}\n";
#else
static const char *hud_fs =
    "#version 100\n"
    "precision mediump float;\n"
    "varying vec2 v_uv;\n"
    "uniform sampler2D u_tex;\n"
    "void main() {\n"
    "  gl_FragColor = texture2D(u_tex, v_uv);\n"
    "}\n";
#endif

typedef struct {
  GLint enabled;
  GLint size;
  GLint stride;
  GLint type;
  GLint normalized;
  GLint buffer;
  const void *ptr;
} HudAttrib;

static void hud_save_attrib(GLuint i, HudAttrib *a)
{
  void *ptr = NULL;
  glGetVertexAttribiv(i, GL_VERTEX_ATTRIB_ARRAY_ENABLED, &a->enabled);
  glGetVertexAttribiv(i, GL_VERTEX_ATTRIB_ARRAY_SIZE, &a->size);
  glGetVertexAttribiv(i, GL_VERTEX_ATTRIB_ARRAY_STRIDE, &a->stride);
  glGetVertexAttribiv(i, GL_VERTEX_ATTRIB_ARRAY_TYPE, &a->type);
  glGetVertexAttribiv(i, GL_VERTEX_ATTRIB_ARRAY_NORMALIZED, &a->normalized);
  glGetVertexAttribiv(i, GL_VERTEX_ATTRIB_ARRAY_BUFFER_BINDING, &a->buffer);
  glGetVertexAttribPointerv(i, GL_VERTEX_ATTRIB_ARRAY_POINTER, &ptr);
  a->ptr = ptr;
}

static void hud_restore_attrib(GLuint i, const HudAttrib *a)
{
  glBindBuffer(GL_ARRAY_BUFFER, (GLuint)a->buffer);
  if (a->size > 0 && a->type != 0)
    glVertexAttribPointer(i, a->size, (GLenum)a->type,
                          (GLboolean)a->normalized, a->stride, a->ptr);
  if (a->enabled)
    glEnableVertexAttribArray(i);
  else
    glDisableVertexAttribArray(i);
}

static GLuint wwn_hud_compile_shader(GLenum type, const char *src)
{
  GLuint s = glCreateShader(type);
  glShaderSource(s, 1, &src, NULL);
  glCompileShader(s);
  return s;
}

static int hud_gl_ready(void)
{
  if (hud_prog)
    return 1;
  GLuint vs = wwn_hud_compile_shader(GL_VERTEX_SHADER, hud_vs);
  GLuint fs = wwn_hud_compile_shader(GL_FRAGMENT_SHADER, hud_fs);
  hud_prog = glCreateProgram();
  glAttachShader(hud_prog, vs);
  glAttachShader(hud_prog, fs);
  glBindAttribLocation(hud_prog, 0, "a_pos");
  glBindAttribLocation(hud_prog, 1, "a_uv");
  glLinkProgram(hud_prog);
  glDeleteShader(vs);
  glDeleteShader(fs);
  glGenTextures(1, &hud_tex);
  glGenBuffers(1, &hud_vbo);
  return hud_prog != 0;
}

WWN_CUBE_HUD_API void wwn_cube_hud_draw_gl(int fb_w, int fb_h,
                                            const struct wwn_cube_hud *h)
{
  if (fb_w <= 0 || fb_h <= 0 || !hud_gl_ready())
    return;

  char raw[512], wrapped[768];
  int overlay_w = 0, overlay_h = 0;
  hud_format(h, raw, sizeof(raw));
  int scale = hud_fit_overlay(fb_w, fb_h, raw, wrapped, sizeof(wrapped),
                              &overlay_w, &overlay_h);
  if (overlay_w < 1 || overlay_h < 1)
    return;

  int need = overlay_w * overlay_h * 4;
  if (!hud_scratch || hud_scratch_n < need) {
    free(hud_scratch);
    hud_scratch = (uint8_t *)calloc((size_t)need, 1);
    hud_scratch_n = need;
    if (!hud_scratch)
      return;
  } else {
    memset(hud_scratch, 0, (size_t)need);
  }

  hud_blit_rgba_scaled(hud_scratch, overlay_w, overlay_h, overlay_w * 4, h, 0,
                       scale, wrapped);

  GLint prev_prog = 0, prev_tex = 0, prev_buf = 0, prev_vao = 0;
  GLint prev_viewport[4];
  GLint prev_blend_src = 0, prev_blend_dst = 0;
  GLboolean prev_blend, prev_depth, prev_cull;
  HudAttrib attrib0, attrib1, attrib2;
  glGetIntegerv(GL_CURRENT_PROGRAM, &prev_prog);
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &prev_tex);
  glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &prev_buf);
#ifdef GL_VERTEX_ARRAY_BINDING
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &prev_vao);
#endif
  glGetIntegerv(GL_VIEWPORT, prev_viewport);
  glGetIntegerv(GL_BLEND_SRC_RGB, &prev_blend_src);
  glGetIntegerv(GL_BLEND_DST_RGB, &prev_blend_dst);
  prev_blend = glIsEnabled(GL_BLEND);
  prev_depth = glIsEnabled(GL_DEPTH_TEST);
  prev_cull = glIsEnabled(GL_CULL_FACE);
  /* kmscube sets attribs 0-2 once at init and never again. Overwriting them
   * (and disabling 0/1) made the cube vanish after the first hub frame. */
  hud_save_attrib(0, &attrib0);
  hud_save_attrib(1, &attrib1);
  hud_save_attrib(2, &attrib2);

  glDisable(GL_DEPTH_TEST);
  glDisable(GL_CULL_FACE);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glViewport(0, 0, fb_w, fb_h);

  glBindTexture(GL_TEXTURE_2D, hud_tex);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  if (hud_tex_w != overlay_w || hud_tex_h != overlay_h) {
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, overlay_w, overlay_h, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, hud_scratch);
    hud_tex_w = overlay_w;
    hud_tex_h = overlay_h;
  } else {
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, overlay_w, overlay_h, GL_RGBA,
                    GL_UNSIGNED_BYTE, hud_scratch);
  }

  float ndc_w = 2.f * (float)overlay_w / (float)fb_w;
  float ndc_h = 2.f * (float)overlay_h / (float)fb_h;
#if defined(__APPLE__)
  /* Metal present flips GL y (bottom-left origin to UIKit top-left). A hub
   * at GL y=1 landed at the bottom of the iOS window. */
  float x0 = -1.f, y0 = -1.f, x1 = -1.f + ndc_w, y1 = -1.f + ndc_h;
#else
  /* Top-left in GL NDC (y up): x=-1, y=1 */
  float x0 = -1.f, y1 = 1.f, x1 = -1.f + ndc_w, y0 = 1.f - ndc_h;
#endif
  float verts[] = {
      x0, y0, 0.f, 1.f, x1, y0, 1.f, 1.f, x0, y1, 0.f, 0.f, x1, y1, 1.f, 0.f,
  };

  glUseProgram(hud_prog);
  glBindBuffer(GL_ARRAY_BUFFER, hud_vbo);
  glBufferData(GL_ARRAY_BUFFER, sizeof(verts), verts, GL_DYNAMIC_DRAW);
  glEnableVertexAttribArray(0);
  glEnableVertexAttribArray(1);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 16, (const void *)0);
  glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 16, (const void *)8);
  GLint loc = glGetUniformLocation(hud_prog, "u_tex");
  if (loc >= 0)
    glUniform1i(loc, 0);
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

  hud_restore_attrib(0, &attrib0);
  hud_restore_attrib(1, &attrib1);
  hud_restore_attrib(2, &attrib2);

  glUseProgram((GLuint)prev_prog);
  glBindTexture(GL_TEXTURE_2D, (GLuint)prev_tex);
  glBindBuffer(GL_ARRAY_BUFFER, (GLuint)prev_buf);
#ifdef GL_VERTEX_ARRAY_BINDING
  glBindVertexArray((GLuint)prev_vao);
#endif
  glViewport(prev_viewport[0], prev_viewport[1], prev_viewport[2],
             prev_viewport[3]);
  glBlendFunc((GLenum)prev_blend_src, (GLenum)prev_blend_dst);
  if (!prev_blend)
    glDisable(GL_BLEND);
  if (prev_depth)
    glEnable(GL_DEPTH_TEST);
  else
    glDisable(GL_DEPTH_TEST);
  if (prev_cull)
    glEnable(GL_CULL_FACE);
  else
    glDisable(GL_CULL_FACE);
}

#endif /* WWN_CUBE_HUD_GL */
