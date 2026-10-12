#ifndef WWN_NIRI_MACOS_LIBSEAT_H
#define WWN_NIRI_MACOS_LIBSEAT_H

#include <stdarg.h>

struct libseat;
struct libseat_device;
struct libseat_seat_listener {
  void (*enable_seat)(struct libseat *, void *);
  void (*disable_seat)(struct libseat *, void *);
};

struct libseat *libseat_open_seat(const struct libseat_seat_listener *, void *);
void libseat_close_seat(struct libseat *);
int libseat_get_fd(struct libseat *);
int libseat_dispatch(struct libseat *, int);
int libseat_get_vt(struct libseat *);
int libseat_open_device(struct libseat *, const char *, int *);
int libseat_close_device(struct libseat *, int);
int libseat_disable_seat(struct libseat *);
int libseat_switch_session(struct libseat *, int);
const char *libseat_seat_name(struct libseat *);
const char *libseat_name(struct libseat *);
typedef void (*libseat_log_handler)(int, const char *, void *);
void libseat_set_log_handler(libseat_log_handler);
void libseat_set_log_level(int);

#endif
