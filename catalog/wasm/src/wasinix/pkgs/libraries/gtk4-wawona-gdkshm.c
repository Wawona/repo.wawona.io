/*
 * Copyright © 2025 Red Hat, Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library. If not, see <http://www.gnu.org/licenses/>.
 */

/*
 * Wawona/WASIX SHM adapter.
 *
 * Upstream creates a guest memfd, mmaps it MAP_SHARED, and hands the fd to
 * the compositor over SCM_RIGHTS. A Wawona Relay guest has no shared mmap
 * with the host and no fd passing, so the host owns the SHM file:
 *
 *   wawona_wayland_shm_create(size, &fd)  -> host file, synthetic fd
 *   wawona_wayland_shm_write(fd, off, buf, len)
 *
 * The guest draws into ordinary heap memory (the cairo image surface) and
 * flushes it to the host file immediately before the buffer is attached.
 * The synthetic fd is passed to wl_shm.create_pool and resolved by the host
 * in wawona_wayland_sendmsg.
 */

#include "config.h"

#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>

#ifdef HAVE_SYS_MMAN_H
#include <sys/mman.h>
#endif

#include "gdkshm-private.h"

__attribute__((import_module("env"), import_name("wawona_wayland_shm_create")))
extern int wawona_wayland_shm_create (int size, int *fd_out);
__attribute__((import_module("env"), import_name("wawona_wayland_shm_write")))
extern int wawona_wayland_shm_write (int shm_fd, int offset, const void *buf, int len);
__attribute__((import_module("env"), import_name("wawona_socket_close")))
extern int wawona_socket_close (int fd);

/* {{{ Shm buffer handling */

static const cairo_user_data_key_t gdk_wayland_shm_surface_cairo_key;

typedef struct _GdkWaylandCairoSurfaceData {
  gpointer buf;
  size_t buf_length;
  int shm_fd;
  struct wl_shm_pool *pool;
  struct wl_buffer *buffer;
  GdkWaylandDisplay *display;
} GdkWaylandCairoSurfaceData;

static struct wl_shm_pool *
create_shm_pool (struct wl_shm  *shm,
                 int             size,
                 size_t         *buf_length,
                 void          **data_out,
                 int            *fd_out)
{
  struct wl_shm_pool *pool;
  int fd = -1;
  void *data;

  if (wawona_wayland_shm_create (size, &fd) != 0 || fd < 0)
    goto fail;

  /* Guest-side drawing buffer; flushed to the host file at attach time. */
  data = g_malloc0 (size);

  if (data == NULL)
    {
      g_critical (G_STRLOC ": allocating shared memory buffer failed");
      wawona_socket_close (fd);
      goto fail;
    }

  pool = wl_shm_create_pool (shm, fd, size);

  *data_out = data;
  *buf_length = size;
  *fd_out = fd;

  return pool;

fail:
  *data_out = NULL;
  *buf_length = 0;
  *fd_out = -1;
  return NULL;
}

static void
gdk_wayland_cairo_surface_destroy (void *p)
{
  GdkWaylandCairoSurfaceData *data = p;

  if (data->buffer)
    wl_buffer_destroy (data->buffer);

  if (data->pool)
    wl_shm_pool_destroy (data->pool);

  if (data->shm_fd >= 0)
    wawona_socket_close (data->shm_fd);

  g_free (data->buf);
  g_free (data);
}

cairo_surface_t *
gdk_wayland_display_create_shm_surface (GdkWaylandDisplay *display,
                                        uint32_t           width,
                                        uint32_t           height)
{
  GdkWaylandCairoSurfaceData *data;
  cairo_surface_t *surface = NULL;
  cairo_status_t status;
  int stride;

  data = g_new (GdkWaylandCairoSurfaceData, 1);
  data->display = display;
  data->buffer = NULL;
  data->shm_fd = -1;

  stride = cairo_format_stride_for_width (CAIRO_FORMAT_ARGB32, width);

  data->pool = create_shm_pool (display->shm,
                                height * stride,
                                &data->buf_length,
                                &data->buf,
                                &data->shm_fd);
  if (G_UNLIKELY (data->pool == NULL))
    g_error ("Unable to create shared memory pool");

  surface = cairo_image_surface_create_for_data (data->buf,
                                                 CAIRO_FORMAT_ARGB32,
                                                 width,
                                                 height,
                                                 stride);

  data->buffer = wl_shm_pool_create_buffer (data->pool, 0,
                                            width, height,
                                            stride, WL_SHM_FORMAT_ARGB8888);

  cairo_surface_set_user_data (surface, &gdk_wayland_shm_surface_cairo_key,
                               data, gdk_wayland_cairo_surface_destroy);

  status = cairo_surface_status (surface);
  if (status != CAIRO_STATUS_SUCCESS)
    {
      g_critical (G_STRLOC ": Unable to create Cairo image surface: %s",
                  cairo_status_to_string (status));
    }

  return surface;
}

struct wl_buffer *
_gdk_wayland_shm_surface_get_wl_buffer (cairo_surface_t *surface)
{
  GdkWaylandCairoSurfaceData *data = cairo_surface_get_user_data (surface, &gdk_wayland_shm_surface_cairo_key);
  return data->buffer;
}

gboolean
_gdk_wayland_is_shm_surface (cairo_surface_t *surface)
{
  return cairo_surface_get_user_data (surface, &gdk_wayland_shm_surface_cairo_key) != NULL;
}

void
_gdk_wayland_shm_surface_flush (cairo_surface_t *surface)
{
  GdkWaylandCairoSurfaceData *data;

  if (surface == NULL)
    return;

  data = cairo_surface_get_user_data (surface, &gdk_wayland_shm_surface_cairo_key);
  if (data == NULL || data->shm_fd < 0 || data->buf == NULL)
    return;

  cairo_surface_flush (surface);
  wawona_wayland_shm_write (data->shm_fd, 0, data->buf, (int) data->buf_length);
}

/* {{{2 wl_shm_buffer listener */

static void
shm_buffer_release (void             *data,
                    struct wl_buffer *buffer)
{
  cairo_surface_t *surface = data;

  /* Note: the wl_buffer is destroyed as cairo user data */
  cairo_surface_destroy (surface);
}

static const struct wl_buffer_listener shm_buffer_listener = {
  shm_buffer_release,
};

/* }}} */

struct wl_buffer *
_gdk_wayland_shm_texture_get_wl_buffer (GdkWaylandDisplay *display,
                                        GdkTexture        *texture)
{
  int width, height;
  cairo_surface_t *surface;
  GdkTextureDownloader *downloader;
  struct wl_buffer *buffer;

  width = gdk_texture_get_width (texture);
  height = gdk_texture_get_height (texture);
  surface = gdk_wayland_display_create_shm_surface (display, width, height);

  downloader = gdk_texture_downloader_new (texture);

  gdk_texture_downloader_download_into (downloader,
                                        cairo_image_surface_get_data (surface),
                                        cairo_image_surface_get_stride (surface));

  gdk_texture_downloader_free (downloader);

  _gdk_wayland_shm_surface_flush (surface);

  buffer = _gdk_wayland_shm_surface_get_wl_buffer (surface);
  wl_buffer_add_listener (buffer, &shm_buffer_listener, surface);

  return buffer;
}

/* }}} */

/* vim:set foldmethod=marker: */
