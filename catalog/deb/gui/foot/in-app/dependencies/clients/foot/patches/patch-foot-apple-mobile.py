#!/usr/bin/env python3
"""Patch foot for Apple-mobile in-process launch (App Store–safe PTY).

Replaces posix_openpt + fork/exec slave_spawn with wawona-pty, mirrors
weston-terminal's Apple-mobile path. Also renames main → foot_main and turns
the foot executable meson target into a static library for -force_load.
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(".").resolve()


def patch_main() -> None:
    main = ROOT / "main.c"
    text = main.read_text()
    if "foot_main(" in text:
        return
    # foot declares `main(int argc, char *const *argv)` without a return type
    # on some lines; match the definition at file scope.
    new, n = re.subn(
        r"(?m)^main\s*\(",
        "foot_main(",
        text,
        count=1,
    )
    if n != 1:
        raise SystemExit("failed to rename main → foot_main in main.c")
    main.write_text(new)


def patch_meson() -> None:
    meson = ROOT / "meson.build"
    text = meson.read_text()
    if "static_library(\n  'foot'," in text or "static_library(\n  'foot'" in text:
        return
    old = "executable(\n  'foot',"
    new = "static_library(\n  'foot',"
    if old not in text:
        raise SystemExit("foot executable() target not found in meson.build")
    text = text.replace(old, new, 1)
    # static_library has no install: true in the same way; keep install.
    # Meson allows install: true on static_library.
    meson.write_text(text)


def patch_terminal() -> None:
    path = ROOT / "terminal.c"
    text = path.read_text()
    if "wwn_pty.h" in text:
        return

    include = """
#if defined(__APPLE__)
#include <TargetConditionals.h>
#ifndef TARGET_OS_VISION
#define TARGET_OS_VISION 0
#endif
#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH || TARGET_OS_VISION
#include "wwn_pty.h"
#include <unistd.h>
extern char **environ;
#undef waitpid
#define waitpid(pid, status, options) wwn_pty_ios_waitpid((pid), (status), (options))
#define WAWONA_FOOT_APPLE_MOBILE 1
#endif
#endif
"""
    anchor = '#include "slave.h"'
    if anchor not in text:
        raise SystemExit("slave.h include missing in terminal.c")
    text = text.replace(anchor, anchor + include, 1)

    # Declare apple_slave_fd next to other locals.
    old_locals = """    int ptmx = -1;
    int flash_fd = -1;"""
    new_locals = """    int ptmx = -1;
#if defined(WAWONA_FOOT_APPLE_MOBILE)
    int apple_slave_fd = -1;
#endif
    int flash_fd = -1;"""
    if old_locals not in text:
        raise SystemExit("ptmx locals block not found in terminal.c")
    text = text.replace(old_locals, new_locals, 1)

    old_open = """    ptmx = pty_path ? open(pty_path, PTY_OPEN_FLAGS) : posix_openpt(PTY_OPEN_FLAGS);
    if (ptmx < 0) {
        LOG_ERRNO("failed to open PTY");
        goto close_fds;
    }"""
    new_open = """#if defined(WAWONA_FOOT_APPLE_MOBILE)
    if (pty_path) {
        ptmx = open(pty_path, PTY_OPEN_FLAGS);
        if (ptmx < 0) {
            LOG_ERRNO("failed to open PTY path");
            goto close_fds;
        }
    } else if (wwn_pty_open(&ptmx, &apple_slave_fd, NULL) != 0) {
        LOG_ERRNO("failed to open wawona-pty");
        goto close_fds;
    }
#else
    ptmx = pty_path ? open(pty_path, PTY_OPEN_FLAGS) : posix_openpt(PTY_OPEN_FLAGS);
    if (ptmx < 0) {
        LOG_ERRNO("failed to open PTY");
        goto close_fds;
    }
#endif"""
    if old_open not in text:
        raise SystemExit("posix_openpt block not found in terminal.c")
    text = text.replace(old_open, new_open, 1)

    old_spawn = """    if (!pty_path) {
        /* Start the slave/client */
        if ((term->slave = slave_spawn(
                 term->ptmx, argc, term->cwd, argv, envp, &conf->env_vars,
                 conf->term, conf->shell, conf->login_shell,
                 &conf->notifications)) == -1)
        {
            goto err;
        }

        reaper_add(term->reaper, term->slave, &fdm_client_terminated, term);
    }"""
    new_spawn = """    if (!pty_path) {
#if defined(WAWONA_FOOT_APPLE_MOBILE)
        /* App Store path: in-process zsh via wawona-pty (no fork/exec). */
        {
            const char *shell_path = getenv("WAWONA_SHELL");
            char *const spawn_argv[] = {
                (char *)(shell_path && shell_path[0] ? shell_path : conf->shell),
                NULL,
            };
            if (!shell_path || !shell_path[0])
                shell_path = conf->shell;
            if (apple_slave_fd < 0) {
                LOG_ERR("wawona-pty slave fd missing");
                goto err;
            }
            setenv("TERM",
                   (conf->term && conf->term[0] &&
                    strcmp(conf->term, "foot") != 0 &&
                    strcmp(conf->term, "foot-extra") != 0)
                       ? conf->term
                       : "xterm-256color",
                   1);
            setenv("COLORTERM", "truecolor", 1);
            term->slave = wwn_pty_spawn_shell_paced(
                shell_path, spawn_argv, apple_slave_fd, -1, environ);
            close(apple_slave_fd);
            apple_slave_fd = -1;
            if (term->slave < 0) {
                LOG_ERRNO("failed to spawn in-process shell");
                goto err;
            }
            reaper_add(term->reaper, term->slave, &fdm_client_terminated, term);
        }
#else
        /* Start the slave/client */
        if ((term->slave = slave_spawn(
                 term->ptmx, argc, term->cwd, argv, envp, &conf->env_vars,
                 conf->term, conf->shell, conf->login_shell,
                 &conf->notifications)) == -1)
        {
            goto err;
        }

        reaper_add(term->reaper, term->slave, &fdm_client_terminated, term);
#endif
    }"""
    if old_spawn not in text:
        raise SystemExit("slave_spawn block not found in terminal.c")
    text = text.replace(old_spawn, new_spawn, 1)

    old_winsz = """    if (ioctl(ptmx, (unsigned int)TIOCSWINSZ,
              &(struct winsize){.ws_row = 24, .ws_col = 80}) < 0)
    {
        LOG_ERRNO("failed to set initial TIOCSWINSZ");
        goto close_fds;
    }"""
    new_winsz = """#if defined(WAWONA_FOOT_APPLE_MOBILE)
    /* socketpair PTY is not a TTY; TIOCSWINSZ is ENOTTY/EINVAL. Keep going. */
    if (wwn_pty_set_winsize(ptmx, &(struct winsize){.ws_row = 24, .ws_col = 80}) < 0)
        LOG_ERRNO("failed to set initial TIOCSWINSZ (ignored on Apple mobile)");
#else
    if (ioctl(ptmx, (unsigned int)TIOCSWINSZ,
              &(struct winsize){.ws_row = 24, .ws_col = 80}) < 0)
    {
        LOG_ERRNO("failed to set initial TIOCSWINSZ");
        goto close_fds;
    }
#endif"""
    if old_winsz not in text:
        raise SystemExit("initial TIOCSWINSZ block not found in terminal.c")
    text = text.replace(old_winsz, new_winsz, 1)
    path.write_text(text)


def patch_render() -> None:
    """Interactive resize also ioctl(TIOCSWINSZ); same socketpair ENOTTY."""
    path = ROOT / "render.c"
    text = path.read_text()
    if "wwn_pty_set_winsize" in text:
        return

    include = """
#if defined(__APPLE__)
#include <TargetConditionals.h>
#ifndef TARGET_OS_VISION
#define TARGET_OS_VISION 0
#endif
#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH || TARGET_OS_VISION
#include "wwn_pty.h"
#define WAWONA_FOOT_APPLE_MOBILE 1
#endif
#endif
"""
    anchor = '#include <sys/ioctl.h>'
    if anchor not in text:
        raise SystemExit("sys/ioctl.h include missing in render.c")
    text = text.replace(anchor, anchor + include, 1)

    old = """        if (ioctl(term->ptmx, (unsigned int)TIOCSWINSZ,
                     &(struct winsize){
                         .ws_row = term->rows,
                         .ws_col = term->cols,
                         .ws_xpixel = term->cols * term->cell_width,
                         .ws_ypixel = term->rows * term->cell_height}) < 0)
        {
            LOG_ERRNO("TIOCSWINSZ");
        }"""
    new = """#if defined(WAWONA_FOOT_APPLE_MOBILE)
        if (wwn_pty_set_winsize(term->ptmx, &(struct winsize){
                         .ws_row = (unsigned short)term->rows,
                         .ws_col = (unsigned short)term->cols,
                         .ws_xpixel = (unsigned short)(term->cols * term->cell_width),
                         .ws_ypixel = (unsigned short)(term->rows * term->cell_height)}) < 0)
        {
            LOG_ERRNO("TIOCSWINSZ (ignored on Apple mobile)");
        }
#else
        if (ioctl(term->ptmx, (unsigned int)TIOCSWINSZ,
                     &(struct winsize){
                         .ws_row = term->rows,
                         .ws_col = term->cols,
                         .ws_xpixel = term->cols * term->cell_width,
                         .ws_ypixel = term->rows * term->cell_height}) < 0)
        {
            LOG_ERRNO("TIOCSWINSZ");
        }
#endif"""
    if old not in text:
        raise SystemExit("tiocswinsz() ioctl block not found in render.c")
    text = text.replace(old, new, 1)
    path.write_text(text)


def patch_spawn_stub() -> None:
    """Notifications / OSC helpers call spawn.c fork — stub on Apple mobile."""
    path = ROOT / "spawn.c"
    text = path.read_text()
    if "WAWONA_FOOT_APPLE_MOBILE" in text:
        return
    guard = """
#if defined(__APPLE__)
#include <TargetConditionals.h>
#ifndef TARGET_OS_VISION
#define TARGET_OS_VISION 0
#endif
#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH || TARGET_OS_VISION
#define WAWONA_FOOT_APPLE_MOBILE 1
#endif
#endif
"""
    text = guard + text
    needle = """{
    int pipe_fds[2] = {-1, -1};
    if (pipe2(pipe_fds, O_CLOEXEC) < 0) {"""
    repl = """{
#if defined(WAWONA_FOOT_APPLE_MOBILE)
    (void)reaper; (void)cwd; (void)argv;
    (void)stdin_fd; (void)stdout_fd; (void)stderr_fd;
    (void)cb; (void)cb_data; (void)xdg_activation_token;
    errno = ENOTSUP;
    LOG_ERR("spawn/fork unsupported on Apple mobile");
    return -1;
#else
    int pipe_fds[2] = {-1, -1};
    if (pipe2(pipe_fds, O_CLOEXEC) < 0) {"""
    if needle not in text:
        raise SystemExit("spawn() body not found in spawn.c")
    text = text.replace(needle, repl, 1)
    # Close #else before spawn()'s final closing brace.
    end_marker = """err:
    if (pipe_fds[0] != -1)
        close(pipe_fds[0]);
    if (pipe_fds[1] != -1)
        close(pipe_fds[1]);
    return -1;
}
"""
    end_repl = """err:
    if (pipe_fds[0] != -1)
        close(pipe_fds[0]);
    if (pipe_fds[1] != -1)
        close(pipe_fds[1]);
    return -1;
#endif /* !WAWONA_FOOT_APPLE_MOBILE */
}
"""
    if end_marker not in text:
        raise SystemExit("spawn() epilogue not found in spawn.c")
    text = text.replace(end_marker, end_repl, 1)
    path.write_text(text)


def patch_slave_stub() -> None:
    """slave.c uses fork/execve — unavailable on tvOS/watchOS; stub unused paths."""
    path = ROOT / "slave.c"
    text = path.read_text()
    if "WAWONA_FOOT_APPLE_MOBILE" in text:
        return
    guard = """
#if defined(__APPLE__)
#include <TargetConditionals.h>
#ifndef TARGET_OS_VISION
#define TARGET_OS_VISION 0
#endif
#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH || TARGET_OS_VISION
#define WAWONA_FOOT_APPLE_MOBILE 1
#endif
#endif
#if defined(WAWONA_FOOT_APPLE_MOBILE)
#pragma clang diagnostic ignored "-Wunused-function"
#endif
"""
    text = guard + text

    old_exec = """static int
foot_execvpe(const char *file, char *const argv[], char *const envp[])
{
    char *path = find_file_in_path(file);
    int ret = execve(path, argv, envp);"""
    new_exec = """static int
foot_execvpe(const char *file, char *const argv[], char *const envp[])
{
#if defined(WAWONA_FOOT_APPLE_MOBILE)
    (void)file; (void)argv; (void)envp;
    errno = ENOTSUP;
    return -1;
#else
    char *path = find_file_in_path(file);
    int ret = execve(path, argv, envp);"""
    if old_exec not in text:
        raise SystemExit("foot_execvpe() body not found in slave.c")
    text = text.replace(old_exec, new_exec, 1)

    exec_close = """    free(path);
    return ret;
}

#else   /* EXECVPE */"""
    exec_close_repl = """    free(path);
    return ret;
#endif /* !WAWONA_FOOT_APPLE_MOBILE */
}

#else   /* EXECVPE */"""
    if exec_close not in text:
        raise SystemExit("foot_execvpe() epilogue not found in slave.c")
    text = text.replace(exec_close, exec_close_repl, 1)

    old_spawn = """pid_t
slave_spawn(int ptmx, int argc, const char *cwd, char *const *argv,
            const char *const *envp, const env_var_list_t *extra_env_vars,
            const char *term_env, const char *conf_shell, bool login_shell,
            const user_notifications_t *notifications)
{
    int fork_pipe[2];
    if (pipe2(fork_pipe, O_CLOEXEC) < 0) {"""
    new_spawn = """pid_t
slave_spawn(int ptmx, int argc, const char *cwd, char *const *argv,
            const char *const *envp, const env_var_list_t *extra_env_vars,
            const char *term_env, const char *conf_shell, bool login_shell,
            const user_notifications_t *notifications)
{
#if defined(WAWONA_FOOT_APPLE_MOBILE)
    (void)ptmx; (void)argc; (void)cwd; (void)argv; (void)envp;
    (void)extra_env_vars; (void)term_env; (void)conf_shell;
    (void)login_shell; (void)notifications;
    errno = ENOTSUP;
    LOG_ERR("slave_spawn/fork unsupported on Apple mobile");
    return -1;
#else
    int fork_pipe[2];
    if (pipe2(fork_pipe, O_CLOEXEC) < 0) {"""
    if old_spawn not in text:
        raise SystemExit("slave_spawn() body not found in slave.c")
    text = text.replace(old_spawn, new_spawn, 1)

    spawn_end = """        break;
    }
    }

    return pid;
}
"""
    spawn_end_repl = """        break;
    }
    }

    return pid;
#endif /* !WAWONA_FOOT_APPLE_MOBILE */
}
"""
    if spawn_end not in text:
        raise SystemExit("slave_spawn() epilogue not found in slave.c")
    text = text.replace(spawn_end, spawn_end_repl, 1)
    path.write_text(text)


def main() -> int:
    patch_main()
    patch_meson()
    patch_terminal()
    patch_render()
    patch_spawn_stub()
    patch_slave_stub()
    # Shim probe symbol compiled separately into the archive by apple-mobile.nix
    print("patched foot for Apple mobile (foot_main + wawona-pty + static lib)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
