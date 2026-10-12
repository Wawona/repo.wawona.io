/* Wawona Wasm Wayland transport: the guest side of the Wayland fd bridge.
 *
 * libwayland-client talks to the compositor over a unix socket and passes
 * wl_shm pool fds with SCM_RIGHTS. Under Wawona Relay a WASIX/WASI guest has
 * neither a unix connect into the host nor fd passing, so the host exposes a
 * small ABI (import module "env", also registered as "wawona_socket"):
 *
 *   wawona_wayland_connect(fd_out)                -> errno
 *   wawona_wayland_sendmsg(wl_fd, buf, len, scm)  -> bytes | -errno
 *   wawona_socket_recv(fd, buf, len, n_out)       -> 0 | -errno
 *   wawona_socket_close(fd)                       -> 0 | -errno
 *   wawona_wayland_shm_create(size, fd_out)       -> errno
 *   wawona_wayland_shm_write(shm_fd, off, buf,len)-> errno
 *
 * `wawona_wayland_connect` returns a synthetic host fd (an index into the
 * host socket table), so plain send/recv/poll/close on it do not work. These
 * --wrap shims map the guest fd libwayland got from connect() to the host fd
 * and route the transport through the imports. Everything that is not a
 * Wawona Wayland connection falls back to the real libc call, so linking this
 * into a native or non-Relay build is a no-op.
 *
 * Link with:
 *   -Wl,--wrap=connect -Wl,--wrap=sendmsg -Wl,--wrap=recvmsg \
 *   -Wl,--wrap=poll -Wl,--wrap=close -Wl,--allow-undefined
 */
#include <errno.h>
#include <poll.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

/* The wasm-EH headers hide struct cmsghdr / CMSG_* / SCM_RIGHTS. */
#ifndef CMSG_LEN
struct cmsghdr { socklen_t cmsg_len; int cmsg_level; int cmsg_type; };
#define __WW_CMSG_ALIGN(len) (((len) + sizeof(size_t) - 1) & (size_t) ~(sizeof(size_t) - 1))
#define CMSG_ALIGN(len) __WW_CMSG_ALIGN(len)
#define CMSG_SPACE(len) (CMSG_ALIGN(len) + CMSG_ALIGN(sizeof(struct cmsghdr)))
#define CMSG_LEN(len) (CMSG_ALIGN(sizeof(struct cmsghdr)) + (len))
#define CMSG_DATA(cmsg) ((unsigned char *)(((struct cmsghdr *)(cmsg)) + 1))
#define __WW_CMSG_LEN(cmsg) (((cmsg)->cmsg_len + sizeof(long) - 1) & ~(long)(sizeof(long) - 1))
#define __WW_CMSG_NEXT(cmsg) ((unsigned char *)(cmsg) + __WW_CMSG_LEN(cmsg))
#define __WW_MHDR_END(mhdr) ((unsigned char *)(mhdr)->msg_control + (mhdr)->msg_controllen)
#define CMSG_FIRSTHDR(mhdr) ((size_t)(mhdr)->msg_controllen >= sizeof(struct cmsghdr) ? (struct cmsghdr *)(mhdr)->msg_control : (struct cmsghdr *)0)
#define CMSG_NXTHDR(mhdr, cmsg) ((cmsg)->cmsg_len < sizeof(struct cmsghdr) || __WW_CMSG_LEN(cmsg) + sizeof(struct cmsghdr) >= __WW_MHDR_END(mhdr) - (unsigned char *)(cmsg) ? 0 : (struct cmsghdr *)__WW_CMSG_NEXT(cmsg))
#endif
#ifndef SCM_RIGHTS
#define SCM_RIGHTS 0x01
#endif
#ifndef SOL_SOCKET
#define SOL_SOCKET 1
#endif

/* ---- host imports (import module "env") --------------------------------- */

__attribute__((import_module("env"), import_name("wawona_wayland_connect")))
extern int wawona_wayland_connect(int *fd_out);
__attribute__((import_module("env"), import_name("wawona_wayland_sendmsg")))
extern int wawona_wayland_sendmsg(int wl_fd, const uint8_t *buf, int len, int scm_fd);
__attribute__((import_module("env"), import_name("wawona_socket_recv")))
extern int wawona_socket_recv(int fd, uint8_t *buf, int len, int *n_out);
__attribute__((import_module("env"), import_name("wawona_socket_close")))
extern int wawona_socket_close(int fd);
__attribute__((import_module("env"), import_name("wawona_wayland_shm_create")))
extern int wawona_wayland_shm_create(int size, int *fd_out);
__attribute__((import_module("env"), import_name("wawona_wayland_shm_write")))
extern int wawona_wayland_shm_write(int shm_fd, int offset, const uint8_t *buf, int len);

/* ---- real libc entry points, supplied by --wrap ------------------------- */

extern int __real_connect(int fd, const struct sockaddr *addr, socklen_t len);
extern ssize_t __real_sendmsg(int fd, const struct msghdr *msg, int flags);
extern ssize_t __real_recvmsg(int fd, struct msghdr *msg, int flags);
extern int __real_poll(struct pollfd *fds, nfds_t nfds, int timeout);
extern int __real_close(int fd);

/* ---- guest fd -> host fd map -------------------------------------------- */

#define WW_MAX_FD 4096
/* ww_host[fd] == 0 means "not a Wawona fd"; otherwise it is host_fd + 1. */
static int ww_host[WW_MAX_FD];

static void
ww_bind (int fd, int host_fd)
{
  if (fd >= 0 && fd < WW_MAX_FD)
    ww_host[fd] = host_fd + 1;
}

static int
ww_host_fd (int fd)
{
  if (fd < 0 || fd >= WW_MAX_FD || ww_host[fd] == 0)
    return -1;
  return ww_host[fd] - 1;
}

static int
ww_wayland_path (const struct sockaddr *addr, socklen_t len)
{
  const struct sockaddr_un *un = (const struct sockaddr_un *) addr;

  if (addr == NULL || addr->sa_family != AF_UNIX)
    return 0;
  if (len < offsetof (struct sockaddr_un, sun_path) + 1)
    return 0;
  /* WAYLAND_DISPLAY is "wayland-0" (or wayland-N); match that substring. */
  return strstr (un->sun_path, "wayland-") != NULL;
}

/* Pull the first SCM_RIGHTS fd out of a sendmsg control buffer. */
static int
ww_scm_fd (const struct msghdr *msg)
{
  const struct cmsghdr *cmsg;
  int fd = -1;

  if (msg == NULL || msg->msg_control == NULL)
    return -1;
  for (cmsg = CMSG_FIRSTHDR (msg); cmsg != NULL; cmsg = CMSG_NXTHDR ((struct msghdr *) msg, cmsg))
    {
      if (cmsg->cmsg_level == SOL_SOCKET && cmsg->cmsg_type == SCM_RIGHTS
          && cmsg->cmsg_len >= CMSG_LEN (sizeof (int)))
        {
          memcpy (&fd, CMSG_DATA (cmsg), sizeof (int));
          break;
        }
    }
  return fd;
}

/* ---- the --wrap shims ---------------------------------------------------- */

int
__wrap_connect (int fd, const struct sockaddr *addr, socklen_t len)
{
  if (ww_wayland_path (addr, len))
    {
      int host = -1;
      int rc = wawona_wayland_connect (&host);

      if (rc == 0 && host >= 0)
        {
          ww_bind (fd, host);
          return 0;
        }
      errno = rc < 0 ? -rc : EIO;
      return -1;
    }
  return __real_connect (fd, addr, len);
}

ssize_t
__wrap_sendmsg (int fd, const struct msghdr *msg, int flags)
{
  int host = ww_host_fd (fd);

  if (host < 0)
    return __real_sendmsg (fd, msg, flags);

  /* Flatten the iovecs: libwayland sends a small, bounded request buffer. */
  uint8_t buf[8192];
  size_t off = 0;

  for (size_t i = 0; i < msg->msg_iovlen && off < sizeof (buf); i++)
    {
      size_t n = msg->msg_iov[i].iov_len;
      if (n > sizeof (buf) - off)
        n = sizeof (buf) - off;
      memcpy (buf + off, msg->msg_iov[i].iov_base, n);
      off += n;
    }

  int rc = wawona_wayland_sendmsg (host, buf, (int) off, ww_scm_fd (msg));
  if (rc < 0)
    {
      errno = -rc;
      return -1;
    }
  return (ssize_t) rc;
}

ssize_t
__wrap_recvmsg (int fd, struct msghdr *msg, int flags)
{
  int host = ww_host_fd (fd);

  if (host < 0)
    return __real_recvmsg (fd, msg, flags);

  if (msg->msg_iovlen < 1)
    return 0;

  size_t cap = msg->msg_iov[0].iov_len;
  int n = 0;
  int rc = wawona_socket_recv (host, (uint8_t *) msg->msg_iov[0].iov_base, (int) cap, &n);
  if (rc < 0)
    {
      errno = -rc;
      return -1;
    }
  msg->msg_iov[0].iov_len = (size_t) n;
  /* Wawona passes no ancillary data back to the guest. */
  msg->msg_controllen = 0;
  return (ssize_t) n;
}

int
__wrap_poll (struct pollfd *fds, nfds_t nfds, int timeout)
{
  /* The host fd is a blocking stream with no pollable guest handle, so report
   * every Wawona fd as readable and let the subsequent recvmsg block. If no
   * fd is a Wawona fd, this is the real poll. */
  int ready = 0;
  int any = 0;

  for (nfds_t i = 0; i < nfds; i++)
    {
      if (fds[i].fd >= 0 && ww_host_fd (fds[i].fd) >= 0)
        {
          fds[i].revents = POLLIN;
          ready++;
          any = 1;
        }
      else
        {
          fds[i].revents = 0;
        }
    }
  if (!any)
    return __real_poll (fds, nfds, timeout);
  return ready;
}

int
__wrap_close (int fd)
{
  int host = ww_host_fd (fd);

  if (host >= 0)
    {
      ww_host[fd] = 0;
      wawona_socket_close (host);
      return 0;
    }
  return __real_close (fd);
}
