#ifndef WWN_ANDROID_SIGNAL_POLYFILL_H
#define WWN_ANDROID_SIGNAL_POLYFILL_H
/*
 * Shared Android NDK signal polyfills for wwn-weston cross builds.
 *
 * Force-include (-include) before any system header. Meson may pass -D_GNU_SOURCE
 * after -include, so feature macros are established here first.
 *
 * Compositor: pull in bits/signal_types.h (sigset_t + sigset64_t) early.
 * WWN_ANDROID_SHM_POLYFILL: minimal typedefs for weston-simple-shm only.
 */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#if defined(WWN_ANDROID_SHM_POLYFILL)
#ifndef _SIGSET_T
typedef unsigned long sigset_t;
#define _SIGSET_T 1
#endif
#ifndef _SIGSET64_T
typedef struct {
	unsigned long __bits[128 / sizeof(long)];
} sigset64_t;
#define _SIGSET64_T 1
#endif
#else
#include <sys/cdefs.h>
#include <sys/types.h>
#include <limits.h>
#include <bits/signal_types.h>
#ifndef PATH_MAX
#define PATH_MAX 4096
#endif
#endif
#endif
