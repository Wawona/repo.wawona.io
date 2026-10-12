#ifndef WWN_CUBE_HUD_H
#define WWN_CUBE_HUD_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Diagnostic overlay for Wawona acceptance cubes (F7/F8/F9 and Wayland
 * opengl-cube / vkcube). Not an upstream kmscube/vkcube feature.
 *
 * Each client #includes wwn_cube_hud.c into its own TU. Default API is
 * static so the four in-process archives do not collide on
 * wwn_cube_hud_* at final app link. Override with
 * -DWWN_CUBE_HUD_API= (empty) only if compiling a shared HUD .o. */
#ifndef WWN_CUBE_HUD_API
#define WWN_CUBE_HUD_API static
#endif

struct wwn_cube_hud {
  int kms;
  int drm;
  int gbm;
  int vulkan;
  int opengl;
  char client[48];
  char vulkan_backend[80];
  char opengl_backend[80];
  float fps;
  double fps_t0;
  int fps_frames;
};

WWN_CUBE_HUD_API void wwn_cube_hud_init(struct wwn_cube_hud *h);
WWN_CUBE_HUD_API void wwn_cube_hud_set_client(struct wwn_cube_hud *h,
                                              const char *name);
WWN_CUBE_HUD_API void wwn_cube_hud_tick(struct wwn_cube_hud *h);
WWN_CUBE_HUD_API void wwn_cube_hud_fill_gl(struct wwn_cube_hud *h);
WWN_CUBE_HUD_API void wwn_cube_hud_set_vk(struct wwn_cube_hud *h,
                                          const char *provider_path,
                                          const char *device_name);
WWN_CUBE_HUD_API void wwn_cube_hud_blit_rgba(uint8_t *rgba, int width,
                                             int height, int stride,
                                             const struct wwn_cube_hud *h,
                                             int bgra);

#ifdef WWN_CUBE_HUD_GL
WWN_CUBE_HUD_API void wwn_cube_hud_draw_gl(int fb_w, int fb_h,
                                           const struct wwn_cube_hud *h);
#endif

#ifdef __cplusplus
}
#endif

#endif
