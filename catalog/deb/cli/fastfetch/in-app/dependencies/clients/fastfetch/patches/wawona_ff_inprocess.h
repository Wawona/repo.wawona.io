#ifndef WAWONA_FF_INPROCESS_H
#define WAWONA_FF_INPROCESS_H

/*
 * App Store-safe in-process execution shim (Apple mobile only).
 *
 * On iOS/iPadOS/tvOS/watchOS/visionOS, fastfetch runs in-process on the zsh
 * pthread inside the Wawona app (see wawona-dispatch.c) rather than via
 * fork/exec. fastfetch calls exit() on --help/--version/bad flags/parse errors;
 * in-process that would terminate the whole app. This shim redirects exit() to
 * a longjmp back to the dispatcher so the shell prompt is restored instead.
 *
 * The exit() redirect is installed as a macro by patch-fastfetch-apple-mobile.py
 * (injected into src/fastfetch.h under WAWONA_APPLE_MOBILE). stdlib.h is included
 * here first so the real libc declaration is not rewritten by the macro.
 */

#if defined(WAWONA_APPLE_MOBILE)

#include <stdlib.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Redirect target for exit(): stores the code and longjmps to the wrapper. */
__attribute__((noreturn)) void wawona_ff_inprocess_exit(int code);

#define exit wawona_ff_inprocess_exit


/*
 * Run fn(argc, argv) under a setjmp barrier. fn is fastfetch_main_impl, which
 * calls ffInitInstance() itself. On normal return the return code is used; on
 * an exit()->longjmp the stored code is used. Per-run cleanup (ffDestroyInstance,
 * restoreTerm) runs exactly once on either path so the global FFinstance and the
 * terminal state are reset for the next invocation.
 */
int wawona_ff_inprocess_run(int (*fn)(int, char**), int argc, char** argv);

#ifdef __cplusplus
}
#endif

#endif /* WAWONA_APPLE_MOBILE */

#endif /* WAWONA_FF_INPROCESS_H */
