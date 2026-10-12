/* wasi has nftw() but not ftw(). GTK4's gtk4-update-icon-cache uses ftw();
 * provide an inert inline replacement so the tool compiles and links. The
 * icon cache update is not needed for the first WASIX bring-up.
 */
#ifndef WASIX_FTW_SHIM_H
#define WASIX_FTW_SHIM_H

#include <sys/stat.h>
#include <ftw.h>

static inline int
ftw (const char *path,
     int (*fn) (const char *, const struct stat *, int),
     int descriptors)
{
  (void) path;
  (void) fn;
  (void) descriptors;
  return -1;
}

#endif /* WASIX_FTW_SHIM_H */
