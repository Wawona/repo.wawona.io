/* Minimal, inert <librsvg/rsvg.h> for the wasi GTK4 build.
 *
 * GTK4's gtk/gdktextureutils.c includes <librsvg/rsvg.h> unconditionally and
 * uses it for SVG textures. librsvg is a large Rust project that we have not
 * ported, so this header provides the API surface GTK4 uses with static
 * inline no-ops: SVG textures simply fail to load (the callers already handle
 * a NULL handle / FALSE result). No librsvg symbols are emitted, so nothing
 * needs to link against -lrsvg-2.
 *
 * The version is reported as 2.61.3 so GTK4 takes its LIBRSVG >= 2.52 path.
 */
#ifndef WASIX_LIBRSVG_STUB_H
#define WASIX_LIBRSVG_STUB_H

#include <glib.h>
#include <cairo.h>

#define LIBRSVG_MAJOR_VERSION 2
#define LIBRSVG_MINOR_VERSION 61
#define LIBRSVG_MICRO_VERSION 3
#define LIBRSVG_VERSION "2.61.3"
#define LIBRSVG_CHECK_VERSION(major, minor, micro)                                     \
  (LIBRSVG_MAJOR_VERSION > (major)                                                     \
   || (LIBRSVG_MAJOR_VERSION == (major) && LIBRSVG_MINOR_VERSION > (minor))            \
   || (LIBRSVG_MAJOR_VERSION == (major) && LIBRSVG_MINOR_VERSION == (minor)            \
       && LIBRSVG_MICRO_VERSION >= (micro)))

typedef struct _RsvgHandle RsvgHandle;

typedef enum {
  RSVG_HANDLE_FLAGS_NONE = 0,
  RSVG_HANDLE_FLAG_UNLIMITED = 1 << 0,
  RSVG_HANDLE_FLAG_KEEP_IMAGE_DATA = 1 << 1,
} RsvgHandleFlags;

typedef enum {
  RSVG_UNIT_EM,
  RSVG_UNIT_EX,
  RSVG_UNIT_PX,
  RSVG_UNIT_IN,
  RSVG_UNIT_CM,
  RSVG_UNIT_MM,
  RSVG_UNIT_PT,
  RSVG_UNIT_PC,
  RSVG_UNIT_PERCENT,
} RsvgUnit;

typedef struct {
  double length;
  RsvgUnit unit;
} RsvgLength;

typedef struct {
  double x;
  double y;
  double width;
  double height;
} RsvgRectangle;

typedef struct {
  int width;
  int height;
  double em;
  double ex;
} RsvgDimensionData;

static inline RsvgHandle *
rsvg_handle_new_from_data (const guint8 *data, gsize data_len, GError **error)
{
  if (error)
    *error = NULL;
  return NULL;
}

static inline RsvgHandle *
rsvg_handle_new_from_stream_sync (GInputStream *input_stream,
                                  GFile *base_file,
                                  RsvgHandleFlags flags,
                                  GCancellable *cancellable,
                                  GError **error)
{
  if (error)
    *error = NULL;
  return NULL;
}

static inline RsvgHandle *
rsvg_handle_new_from_gfile_sync (GFile *file,
                                 RsvgHandleFlags flags,
                                 GCancellable *cancellable,
                                 GError **error)
{
  if (error)
    *error = NULL;
  return NULL;
}

static inline gboolean
rsvg_handle_get_intrinsic_size_in_pixels (RsvgHandle *handle,
                                          gdouble *out_width,
                                          gdouble *out_height)
{
  return FALSE;
}

static inline gboolean
rsvg_handle_get_intrinsic_dimensions (RsvgHandle *handle,
                                      gboolean *out_has_width,
                                      RsvgLength *out_width,
                                      gboolean *out_has_height,
                                      RsvgLength *out_height,
                                      gboolean *out_has_viewbox,
                                      RsvgRectangle *out_viewbox)
{
  return FALSE;
}

static inline gboolean
rsvg_handle_render_document (RsvgHandle *handle,
                             cairo_t *cr,
                             const RsvgRectangle *viewport,
                             GError **error)
{
  if (error)
    *error = NULL;
  return FALSE;
}

static inline gboolean
rsvg_handle_set_stylesheet (RsvgHandle *handle,
                            const guint8 *css,
                            gsize css_len,
                            GError **error)
{
  if (error)
    *error = NULL;
  return FALSE;
}

static inline void
rsvg_handle_get_dimensions (RsvgHandle *handle, RsvgDimensionData *dimension_data)
{
  if (dimension_data)
    {
      dimension_data->width = 0;
      dimension_data->height = 0;
      dimension_data->em = 0;
      dimension_data->ex = 0;
    }
}

static inline gboolean
rsvg_handle_render_cairo (RsvgHandle *handle, cairo_t *cr)
{
  return FALSE;
}

#endif /* WASIX_LIBRSVG_STUB_H */
