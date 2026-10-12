/* Small WASIX compatibility shims for the GTK4 link.
 *
 * - wayland-client uses ppoll(); wasi has poll() but no ppoll(). Ignore the
 *   signal mask and defer to poll().
 * - libepoxy dlopens the GL driver; wasi has no dynamic loading, and we use
 *   GSK_RENDERER=cairo, so return "not found".
 */
#include <poll.h>
#include <signal.h>
#include <time.h>
#include <dlfcn.h>

int
ppoll (struct pollfd *fds,
       nfds_t nfds,
       const struct timespec *timeout,
       const sigset_t *sigmask)
{
  (void) sigmask;

  int ms = -1;
  if (timeout)
    ms = (int) (timeout->tv_sec * 1000 + timeout->tv_nsec / 1000000);
  return poll (fds, nfds, ms);
}

void *
dlopen (const char *filename, int flags)
{
  (void) filename;
  (void) flags;
  return 0;
}

void *
dlsym (void *handle, const char *symbol)
{
  (void) handle;
  (void) symbol;
  return 0;
}

char *
dlerror (void)
{
  return (char *) "dynamic loading is not supported on wasi";
}

int
dlclose (void *handle)
{
  (void) handle;
  return -1;
}
