#!/usr/bin/env python3
"""Avoid glob(3) on Android API 21 — bionic only exposes glob from API 28."""
from pathlib import Path

path = Path("src/common/impl/io_unix.c")
text = path.read_text()

include_old = """#if FF_HAVE_WORDEXP
    #include <wordexp.h>
#else
    #include <glob.h>
#endif"""

include_new = """#if FF_HAVE_WORDEXP
    #include <wordexp.h>
#elif !defined(__ANDROID__)
    #include <glob.h>
#endif"""

if include_old not in text:
    raise SystemExit("io_unix.c glob include anchor missing")
text = text.replace(include_old, include_new, 1)

glob_block_old = """    glob_t gb;
    if (glob(in, GLOB_NOSORT
    #ifdef GLOB_TILDE
                | GLOB_TILDE
    #endif
    #ifdef GLOB_BRACE
                | GLOB_BRACE
    #endif
            ,
            NULL,
            &gb) != 0)
        return false;

    if (gb.gl_pathc >= 1) {
        result = true;
        ffStrbufSetS(out, gb.gl_pathv[gb.gl_pathc > 1 ? ffTimeGetNow() % (unsigned) gb.gl_pathc : 0]);
    }

    globfree(&gb);"""

glob_block_new = """#if defined(__ANDROID__)
    // glob(3) is unavailable on NDK API 21; use the path verbatim.
    ffStrbufSetS(out, in);
    result = true;
#else
    glob_t gb;
    if (glob(in, GLOB_NOSORT
    #ifdef GLOB_TILDE
                | GLOB_TILDE
    #endif
    #ifdef GLOB_BRACE
                | GLOB_BRACE
    #endif
            ,
            NULL,
            &gb) != 0)
        return false;

    if (gb.gl_pathc >= 1) {
        result = true;
        ffStrbufSetS(out, gb.gl_pathv[gb.gl_pathc > 1 ? ffTimeGetNow() % (unsigned) gb.gl_pathc : 0]);
    }

    globfree(&gb);
#endif"""

if glob_block_old not in text:
    raise SystemExit("io_unix.c glob block anchor missing")
text = text.replace(glob_block_old, glob_block_new, 1)

path.write_text(text)

cpu = Path("src/detection/cpu/cpu_linux.c")
text = cpu.read_text()
cpu_old = """    cpu->coresLogical = (uint16_t) get_nprocs_conf();
    cpu->coresOnline = (uint16_t) get_nprocs();"""
cpu_new = """#if defined(__ANDROID__)
    cpu->coresLogical = (uint16_t) sysconf(_SC_NPROCESSORS_CONF);
    cpu->coresOnline = (uint16_t) sysconf(_SC_NPROCESSORS_ONLN);
#else
    cpu->coresLogical = (uint16_t) get_nprocs_conf();
    cpu->coresOnline = (uint16_t) get_nprocs();
#endif"""
if cpu_old not in text:
    raise SystemExit("cpu_linux.c get_nprocs anchor missing")
cpu.write_text(text.replace(cpu_old, cpu_new, 2))

ogl = Path("src/detection/opengl/opengl_linux.c")
text = ogl.read_text()
ogl_anchor = """#if __ANDROID__ && !defined(FF_HAVE_EGL)
    // On Android, installing OpenGL headers is enough (mesa-dev)
    #if __has_include(<EGL/egl.h>)
        #define FF_HAVE_EGL 1
    #endif
#endif"""
ogl_patch = "/* OpenGL/EGL detection disabled for Wawona Android NDK builds. */"
if ogl_anchor not in text:
    raise SystemExit("opengl_linux.c EGL anchor missing")
ogl.write_text(text.replace(ogl_anchor, ogl_patch, 1))

users = Path("src/detection/users/users_linux.c")
text = users.read_text()
users_anchor = """    #define setutxent setutent
    #define getutxent getutent
#endif"""
users_patch = """    #define setutxent setutent
    #define getutxent getutent
    #define endutxent endutent
#endif"""
if users_patch not in text:
    if users_anchor not in text:
        raise SystemExit("users_linux.c utmp alias anchor missing")
    users.write_text(text.replace(users_anchor, users_patch, 1))
