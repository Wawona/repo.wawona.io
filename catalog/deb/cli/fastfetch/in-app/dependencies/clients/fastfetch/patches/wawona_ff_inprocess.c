#include "wawona_ff_inprocess.h"

#if defined(WAWONA_APPLE_MOBILE)

/* This TU implements the exit() redirect; it must call the real exit path. */
#ifdef exit
#undef exit
#endif

#include <setjmp.h>
#include <stdlib.h>
#include <stdint.h>
#include <pthread.h>

/* fastfetch's real entry: src/fastfetch.c compiled with -Dmain=fastfetch_main_impl. */
int fastfetch_main_impl(int argc, char** argv);

/*
 * Upstream registers these via atexit(); the Apple-mobile patch guards those
 * atexit() calls off (they would accumulate per in-process run and only fire at
 * host-app exit against a re-inited global). We invoke them per run instead.
 * Weak so the archive links even if a build omits one.
 */
extern void ffDestroyInstance(void) __attribute__((weak));
extern void restoreTerm(void) __attribute__((weak));

static _Thread_local jmp_buf wawona_ff_jmp;
static _Thread_local int wawona_ff_active = 0;
static _Thread_local int wawona_ff_code = 0;

void wawona_ff_inprocess_exit(int code) {
    if (wawona_ff_active) {
        wawona_ff_code = code;
        longjmp(wawona_ff_jmp, 1);
    }
    /*
     * exit() outside a wrapped run should never happen in-process, but if it
     * does, end only this (zsh) thread rather than killing the whole app.
     */
    pthread_exit((void*)(intptr_t)code);
}

int wawona_ff_inprocess_run(int (*fn)(int, char**), int argc, char** argv) {
    int rc = 0;
    wawona_ff_active = 1;
    wawona_ff_code = 0;

    /*
     * Start every invocation from a clean global FFinstance. If a prior run was
     * aborted (e.g. a fatal signal skipped the per-run cleanup below), the
     * singleton can be left half-torn. ffDestroyInstance is idempotent on Apple
     * mobile (guarded by an internal live flag), so this is a no-op on the first
     * run and safe on every subsequent one.
     */
    if (ffDestroyInstance) ffDestroyInstance();

    if (setjmp(wawona_ff_jmp) == 0) {
        rc = fn(argc, argv);
    } else {
        rc = wawona_ff_code;
    }

    wawona_ff_active = 0;

    /* Deterministic per-run cleanup (replaces the guarded atexit handlers). */
    if (restoreTerm) restoreTerm();
    if (ffDestroyInstance) ffDestroyInstance();

    return rc;
}

/*
 * Public entry weak-linked by wawona-dispatch.c. fastfetch.c is compiled with
 * -Dmain=fastfetch_main_impl, so this thin wrapper is the only fastfetch_main.
 */
int fastfetch_main(int argc, char** argv) {
    return wawona_ff_inprocess_run(fastfetch_main_impl, argc, argv);
}

#endif /* WAWONA_APPLE_MOBILE */
