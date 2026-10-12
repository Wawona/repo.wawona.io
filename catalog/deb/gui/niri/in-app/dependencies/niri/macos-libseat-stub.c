/*
 * Minimal libseat for macOS Mode B niri (no VTs). Mirrors the iland
 * glibc-compat libseat stubs weston already uses. Session is always active.
 */
#include <libseat/libseat.h>
#include <fcntl.h>
#include <stdarg.h>
#include <unistd.h>

#define SEAT_PIPE_R_OFF 0

static void *seat_state(void) {
  static struct {
    int pipe_r;
    int pipe_w;
  } s = {-1, -1};
  if (s.pipe_r < 0) {
    int p[2];
    if (pipe(p) == 0) {
      fcntl(p[0], F_SETFL, fcntl(p[0], F_GETFL) | O_NONBLOCK);
      s.pipe_r = p[0];
      s.pipe_w = p[1];
    }
  }
  return &s;
}

struct libseat *libseat_open_seat(const struct libseat_seat_listener *l, void *data) {
  struct libseat *s = (struct libseat *)seat_state();
  if (l && l->enable_seat) {
    l->enable_seat(s, data);
  }
  return s;
}

void libseat_close_seat(struct libseat *s) { (void)s; }

int libseat_get_fd(struct libseat *s) {
  int *pipes = (int *)s;
  return pipes ? pipes[0] : -1;
}

int libseat_dispatch(struct libseat *s, int timeout) {
  (void)timeout;
  int *pipes = (int *)s;
  if (pipes && pipes[0] >= 0) {
    char buf[64];
    while (read(pipes[0], buf, sizeof(buf)) > 0) {
    }
  }
  return 0;
}

int libseat_get_vt(struct libseat *s) {
  (void)s;
  return -1;
}

int libseat_open_device(struct libseat *s, const char *path, int *fd) {
  (void)s;
  if (!path || !fd) {
    return -1;
  }
  int opened = open(path, O_RDWR);
  if (opened < 0) {
    return -1;
  }
  *fd = opened;
  return opened;
}

int libseat_close_device(struct libseat *s, int device_id) {
  (void)s;
  close(device_id);
  return 0;
}

int libseat_disable_seat(struct libseat *s) {
  (void)s;
  return 0;
}

int libseat_switch_session(struct libseat *s, int session) {
  (void)s;
  (void)session;
  return 0;
}

const char *libseat_seat_name(struct libseat *s) {
  (void)s;
  return "seat0";
}

const char *libseat_name(struct libseat *s) { return libseat_seat_name(s); }

typedef void (*libseat_log_handler)(int level, const char *fmt, void *ap);
void libseat_set_log_handler(libseat_log_handler handler) { (void)handler; }

void libseat_set_log_level(int level) { (void)level; }
