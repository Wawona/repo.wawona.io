#!/usr/bin/env python3
"""App Store–safe fastfetch on Apple mobile: no fork/exec/posix_spawn/system."""
from pathlib import Path

cmake_anchor = "    check_function_exists(malloc_usable_size HAVE_MALLOC_USABLE_SIZE)"
cmake_patch = """    if(WAWONA_APPLE_MOBILE)
        set(HAVE_MALLOC_USABLE_SIZE FALSE)
    else()
        check_function_exists(malloc_usable_size HAVE_MALLOC_USABLE_SIZE)
    endif()"""

path = Path("src/options/general.c")
text = path.read_text()
if "WAWONA_APPLE_MOBILE_PRERUN" not in text:
    anchor = "#include <unistd.h>"
    if anchor not in text:
        raise SystemExit("general.c unistd include missing")
    hdr = """
#if defined(__APPLE__)
#include <TargetConditionals.h>
#define WAWONA_APPLE_MOBILE_PRERUN() (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
#else
#define WAWONA_APPLE_MOBILE_PRERUN() 0
#endif
"""
    text = text.replace(anchor, anchor + hdr, 1)
    old = """        } else if (unsafe_yyjson_equals_str(key, "preRun")) {
            if (!yyjson_is_str(val)) {
                return "general.preRun must be a string";
            }
            if (system(unsafe_yyjson_get_str(val)) < 0) {
                return "Failed to execute preRun command";
            }"""
    new = """        } else if (unsafe_yyjson_equals_str(key, "preRun")) {
            if (!yyjson_is_str(val)) {
                return "general.preRun must be a string";
            }
#if !WAWONA_APPLE_MOBILE_PRERUN()
            if (system(unsafe_yyjson_get_str(val)) < 0) {
                return "Failed to execute preRun command";
            }
#endif"""
    if old not in text:
        raise SystemExit("general.c preRun block anchor missing")
    path.write_text(text.replace(old, new, 1))

cmake = Path("CMakeLists.txt")
text = cmake.read_text()
if "WAWONA_APPLE_MOBILE" not in text.split("malloc_usable_size")[0]:
    if cmake_anchor not in text:
        raise SystemExit("CMakeLists malloc_usable_size anchor missing")
    cmake.write_text(text.replace(cmake_anchor, cmake_patch, 1))

opencl = Path("src/detection/opencl/opencl.c")
text = opencl.read_text()
opencl_anchor = """#if !defined(FF_HAVE_OPENCL) && defined(__APPLE__) && defined(MAC_OS_X_VERSION_10_15)
    #define FF_HAVE_OPENCL 1
#endif"""
opencl_patch = """#if !defined(FF_HAVE_OPENCL) && defined(__APPLE__) && defined(MAC_OS_X_VERSION_10_15)
#include <TargetConditionals.h>
#if !(TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
    #define FF_HAVE_OPENCL 1
#endif
#endif"""
if "TARGET_OS_IPHONE" not in text.split("FF_HAVE_OPENCL")[0]:
    if opencl_anchor not in text:
        raise SystemExit("opencl.c FF_HAVE_OPENCL anchor missing")
    opencl.write_text(text.replace(opencl_anchor, opencl_patch, 1))

ogl_shared = Path("src/detection/opengl/opengl_shared.c")
text = ogl_shared.read_text()
ogl_anchor = """#if __has_include(<GL/gl.h>)
    #include <GL/gl.h>
#elif __APPLE__
    #define GL_SILENCE_DEPRECATION 1
    #include <OpenGL/gl.h>
#else
    #define FF_HAVE_NO_GL 1
#endif"""
ogl_patch = """#if __has_include(<GL/gl.h>)
    #include <GL/gl.h>
#elif defined(__APPLE__)
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH
    #define FF_HAVE_NO_GL 1
#else
    #define GL_SILENCE_DEPRECATION 1
    #include <OpenGL/gl.h>
#endif
#else
    #define FF_HAVE_NO_GL 1
#endif"""
if "TARGET_OS_IPHONE" not in text:
    if ogl_anchor not in text:
        raise SystemExit("opengl_shared.c GL include anchor missing")
    ogl_shared.write_text(text.replace(ogl_anchor, ogl_patch, 1))

ogl_apple = Path("src/detection/opengl/opengl_apple.c")
text = ogl_apple.read_text()
if "OpenGL not available on Apple mobile" not in text:
    ogl_apple_anchor = """#include "fastfetch.h"
#include "opengl.h"

#define GL_SILENCE_DEPRECATION
#include <OpenGL/gl.h>
#include <OpenGL/OpenGL.h> // This brings in CGL, not GL"""
    ogl_apple_patch = """#include "fastfetch.h"
#include "opengl.h"

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)

const char* ffDetectOpenGL(FFOpenGLOptions* options, FFOpenGLResult* result) {
    (void)options;
    (void)result;
    return "OpenGL not available on Apple mobile";
}

#else

#define GL_SILENCE_DEPRECATION
#include <OpenGL/gl.h>
#include <OpenGL/OpenGL.h> // This brings in CGL, not GL"""
    if ogl_apple_anchor not in text:
        raise SystemExit("opengl_apple.c include anchor missing")
    text = text.replace(ogl_apple_anchor, ogl_apple_patch, 1)
    if not text.rstrip().endswith("#endif"):
        text = text.rstrip() + "\n\n#endif\n"
    ogl_apple.write_text(text)

cmake = Path("CMakeLists.txt")
text = cmake.read_text()
snippet = Path(__file__).with_name("cmake-apple-mobile-sources.snippet").read_text()
src_anchor = "elseif(APPLE)\n    list(APPEND LIBFASTFETCH_SRC"
if "elseif(WAWONA_APPLE_MOBILE)" not in text:
    if src_anchor not in text:
        raise SystemExit("CMakeLists APPLE source anchor missing")
    text = text.replace(src_anchor, snippet + src_anchor, 1)

link_anchor = """elseif(APPLE)
    target_link_libraries(libfastfetch
        PRIVATE "-framework AVFoundation\""""
# NOTE: libfastfetch is built as a static archive; target_link_libraries here is
# inert (ar does not invoke the linker). The real per-platform framework set is
# emitted to $out/nix-support/fastfetch-frameworks by apple-mobile.nix and linked
# by the host app. IOKit is dropped (SMC/IORegistry stubbed); VideoToolbox/Metal
# are tiered per platform there (watchOS has neither).
link_patch = """elseif(WAWONA_APPLE_MOBILE)
    target_link_libraries(libfastfetch
        PRIVATE "-framework CoreFoundation"
        PRIVATE "-framework Foundation"
    )
""" + link_anchor
if "WAWONA_APPLE_MOBILE)\n    target_link_libraries" not in text:
    if link_anchor not in text:
        raise SystemExit("CMakeLists APPLE link anchor missing")
    text = text.replace(link_anchor, link_patch, 1)

# Make WAWONA_APPLE_MOBILE a compiler macro (for the C-side hygiene guards) and
# force-include the in-process exit() shim into every libfastfetch TU. A forced
# include is required because exit() is called from files that do not include
# fastfetch.h (e.g. commandoption.c on bad flags), so an umbrella-header edit
# alone would miss them.
defs_anchor = 'elseif(APPLE)\n    target_compile_definitions(libfastfetch PUBLIC _GNU_SOURCE _XOPEN_SOURCE __STDC_WANT_LIB_EXT1__ _FILE_OFFSET_BITS=64 _DARWIN_C_SOURCE)'
defs_patch = defs_anchor + """
    if(WAWONA_APPLE_MOBILE)
        target_compile_definitions(libfastfetch PUBLIC WAWONA_APPLE_MOBILE=1)
        target_compile_options(libfastfetch PUBLIC -include "${CMAKE_SOURCE_DIR}/src/wawona_ff_inprocess.h")
    endif()"""
if "target_compile_definitions(libfastfetch PUBLIC WAWONA_APPLE_MOBILE=1)" not in text:
    if defs_anchor not in text:
        raise SystemExit("CMakeLists APPLE compile-definitions anchor missing")
    text = text.replace(defs_anchor, defs_patch, 1)

cmake.write_text(text)

# --- Phase 1: in-process process hygiene (signals, atexit) ---------------------
# Guard process-global side effects behind WAWONA_APPLE_MOBILE. Android (real
# binary, no WAWONA_APPLE_MOBILE) and macOS keep normal behavior.

init_c = Path("src/common/impl/init.c")
text = init_c.read_text()
if "WAWONA_APPLE_MOBILE" not in text:
    handler_anchor = """#else
static void exitSignalHandler(FF_A_UNUSED int signal) {
    resetConsole();
    exit(0);
}
#endif"""
    handler_patch = """#else
#if !defined(WAWONA_APPLE_MOBILE)
static void exitSignalHandler(FF_A_UNUSED int signal) {
    resetConsole();
    exit(0);
}
#endif
#endif"""
    if handler_anchor not in text:
        raise SystemExit("init.c exitSignalHandler anchor missing")
    text = text.replace(handler_anchor, handler_patch, 1)

    signal_anchor = """    struct sigaction action;
    sigemptyset(&action.sa_mask);
    action.sa_flags = 0;
    action.sa_handler = exitSignalHandler;
    sigaction(SIGINT, &action, NULL);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGQUIT, &action, NULL);
    sigset_t newmask;
    sigemptyset(&newmask);
    sigaddset(&newmask, SIGCHLD);
    sigprocmask(SIG_BLOCK, &newmask, NULL);"""
    signal_patch = """#if !defined(WAWONA_APPLE_MOBILE)
    struct sigaction action;
    sigemptyset(&action.sa_mask);
    action.sa_flags = 0;
    action.sa_handler = exitSignalHandler;
    sigaction(SIGINT, &action, NULL);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGQUIT, &action, NULL);
    sigset_t newmask;
    sigemptyset(&newmask);
    sigaddset(&newmask, SIGCHLD);
    sigprocmask(SIG_BLOCK, &newmask, NULL);
#endif"""
    if signal_anchor not in text:
        raise SystemExit("init.c sigaction block anchor missing")
    text = text.replace(signal_anchor, signal_patch, 1)

    # In-process re-entry guard. fastfetch runs repeatedly on the zsh pthread;
    # wawona_ff_inprocess_run calls ffDestroyInstance() both before and after
    # each run to start/leave the global FFinstance clean. ffDestroyInstance
    # must therefore be a safe no-op on a pristine (zeroed BSS) or already-torn
    # singleton, and ffInitInstance must record that the instance is live.
    live_flag_anchor = "FFinstance instance; // Global singleton"
    live_flag_patch = """FFinstance instance; // Global singleton
#if defined(WAWONA_APPLE_MOBILE)
// Tracks whether `instance` currently holds initialized resources, so the
// per-run ffDestroyInstance() in wawona_ff_inprocess_run is idempotent.
static bool ffInstanceLive = false;
#endif"""
    if live_flag_anchor not in text:
        raise SystemExit("init.c instance singleton anchor missing")
    text = text.replace(live_flag_anchor, live_flag_patch, 1)

    init_set_anchor = """    defaultConfig();
    initState(&instance.state);
}"""
    init_set_patch = """    defaultConfig();
    initState(&instance.state);
#if defined(WAWONA_APPLE_MOBILE)
    ffInstanceLive = true;
#endif
}"""
    if init_set_anchor not in text:
        raise SystemExit("init.c ffInitInstance tail anchor missing")
    text = text.replace(init_set_anchor, init_set_patch, 1)

    destroy_anchor = """void ffDestroyInstance(void) {
    destroyConfig();
    destroyState();
}"""
    destroy_patch = """void ffDestroyInstance(void) {
#if defined(WAWONA_APPLE_MOBILE)
    // Idempotent on Apple mobile: never destroy a pristine (zeroed BSS) or
    // already-destroyed singleton (see wawona_ff_inprocess_run pre/post reset).
    if (!ffInstanceLive)
        return;
    ffInstanceLive = false;
#endif
    destroyConfig();
    destroyState();
}"""
    if destroy_anchor not in text:
        raise SystemExit("init.c ffDestroyInstance anchor missing")
    text = text.replace(destroy_anchor, destroy_patch, 1)

    init_c.write_text(text)

# In-process re-entry: ffPlatformInit re-runs on every fastfetch invocation on
# the zsh pthread. Upstream re-inits the FFstrbuf/FFlist members without freeing
# any prior contents, which leaks and can leave torn state across runs. Free
# first on Apple mobile; ffStrbufDestroy/ffListDestroy are no-ops on a pristine
# (zeroed BSS) struct, so this is safe on the first call too.
ffplatform = Path("src/common/impl/FFPlatform.c")
text = ffplatform.read_text()
if "WAWONA_APPLE_MOBILE" not in text:
    plat_anchor = """void ffPlatformInit(FFPlatform* platform) {
    ffStrbufInit(&platform->homeDir);"""
    plat_patch = """void ffPlatformInit(FFPlatform* platform) {
#if defined(WAWONA_APPLE_MOBILE)
    ffPlatformDestroy(platform);
#endif
    ffStrbufInit(&platform->homeDir);"""
    if plat_anchor not in text:
        raise SystemExit("FFPlatform.c ffPlatformInit anchor missing")
    text = text.replace(plat_anchor, plat_patch, 1)
    ffplatform.write_text(text)

ffmain = Path("src/fastfetch.c")
text = ffmain.read_text()
if "WAWONA_APPLE_MOBILE" not in text:
    atexit_anchor = """    ffInitInstance();
    atexit(ffDestroyInstance);"""
    atexit_patch = """    ffInitInstance();
#if !defined(WAWONA_APPLE_MOBILE)
    atexit(ffDestroyInstance);
#endif"""
    if atexit_anchor not in text:
        raise SystemExit("fastfetch.c atexit anchor missing")
    text = text.replace(atexit_anchor, atexit_patch, 1)

    # Ensure a deterministic return code for the in-process wrapper (the body,
    # compiled with -Dmain=fastfetch_main_impl, must not fall off the end).
    ret_anchor = """    yyjson_mut_doc_free(data.resultDoc);
    ffStrbufDestroy(&data.genConfigPath);
}"""
    ret_patch = """    yyjson_mut_doc_free(data.resultDoc);
    ffStrbufDestroy(&data.genConfigPath);
    return 0;
}"""
    if ret_anchor not in text:
        raise SystemExit("fastfetch.c main tail anchor missing")
    text = text.replace(ret_anchor, ret_patch, 1)

    ffmain.write_text(text)

# Safety net for the in-process path: never iterate configDirs unless .data is a
# real heap pointer. A torn singleton can leave length > 0 while .data is a stale
# tag (0x1000000005), faulting on dir->length (EXC_BAD_ACCESS at 0x1000000009).
fflist = Path("src/common/FFlist.h")
text = fflist.read_text()
if "ffListDataIsValid" not in text:
    valid_anchor = """typedef struct FFlist {
    uint8_t* data;
    uint32_t length;
    uint32_t capacity;
} FFlist;"""
    valid_patch = """typedef struct FFlist {
    uint8_t* data;
    uint32_t length;
    uint32_t capacity;
} FFlist;

#if defined(WAWONA_APPLE_MOBILE)
// iOS heap lives above the low 4GiB; torn singletons can leave a small integer
// in .data while .length stays non-zero (ffListDestroy used to no-op on that).
static inline bool ffListDataIsValid(const FFlist* list) {
    return list->data != NULL && (uintptr_t) list->data >= 0x100000000ULL;
}
#endif"""
    if valid_anchor not in text:
        raise SystemExit("FFlist.h FFlist typedef anchor missing")
    text = text.replace(valid_anchor, valid_patch, 1)

if "ffListDataIsValid(list)" not in text:
    destroy_anchor = """static inline void ffListDestroy(FFlist* list) {
    if (!list->data) {
        return;
    }

    // Avoid free-after-use. These 3 assignments are cheap so don't remove them
    list->capacity = list->length = 0;
    free(list->data);
    list->data = NULL;
}"""
    destroy_patch = """static inline void ffListDestroy(FFlist* list) {
#if defined(WAWONA_APPLE_MOBILE)
    if (!ffListDataIsValid(list)) {
        ffListInit(list);
        return;
    }
#else
    if (!list->data) {
        return;
    }
#endif

    // Avoid free-after-use. These 3 assignments are cheap so don't remove them
    list->capacity = list->length = 0;
    free(list->data);
    list->data = NULL;
}"""
    if destroy_anchor not in text:
        raise SystemExit("FFlist.h ffListDestroy anchor missing")
    text = text.replace(destroy_anchor, destroy_patch, 1)
fflist.write_text(text)

ffmain = Path("src/fastfetch.c")
text = ffmain.read_text()
cfg_guard_strong = """#if defined(WAWONA_APPLE_MOBILE)
    if (!ffListDataIsValid(&instance.state.platform.configDirs) ||
        instance.state.platform.configDirs.length == 0) {
        ffListInit(&instance.state.platform.configDirs);
        return;
    }
#endif"""
cfg_guard_weak = """#if defined(WAWONA_APPLE_MOBILE)
    if (!instance.state.platform.configDirs.data ||
        instance.state.platform.configDirs.length == 0)
        return;
#endif"""
if cfg_guard_strong not in text:
    if cfg_guard_weak in text:
        text = text.replace(cfg_guard_weak, cfg_guard_strong, 1)
    else:
        cfg_anchor = """static void parseConfigFiles(FFdata* data) {
    if (__builtin_expect(data->genConfigPath.length == 0, true)) {"""
        cfg_patch = f"""static void parseConfigFiles(FFdata* data) {{
{cfg_guard_strong}
    if (__builtin_expect(data->genConfigPath.length == 0, true)) {{"""
        if cfg_anchor not in text:
            raise SystemExit("fastfetch.c parseConfigFiles anchor missing")
        text = text.replace(cfg_anchor, cfg_patch, 1)
    ffmain.write_text(text)

ffplatform = Path("src/common/impl/FFPlatform.c")
text = ffplatform.read_text()
cfgdirs_anchor = """    FF_LIST_FOR_EACH (FFstrbuf, dir, platform->configDirs) {
        ffStrbufDestroy(dir);
    }
    ffListDestroy(&platform->configDirs);

    FF_LIST_FOR_EACH (FFstrbuf, dir, platform->dataDirs) {
        ffStrbufDestroy(dir);
    }
    ffListDestroy(&platform->dataDirs);"""
cfgdirs_patch = """#if defined(WAWONA_APPLE_MOBILE)
    if (ffListDataIsValid(&platform->configDirs)) {
#endif
    FF_LIST_FOR_EACH (FFstrbuf, dir, platform->configDirs) {
        ffStrbufDestroy(dir);
    }
#if defined(WAWONA_APPLE_MOBILE)
    }
#endif
    ffListDestroy(&platform->configDirs);

#if defined(WAWONA_APPLE_MOBILE)
    if (ffListDataIsValid(&platform->dataDirs)) {
#endif
    FF_LIST_FOR_EACH (FFstrbuf, dir, platform->dataDirs) {
        ffStrbufDestroy(dir);
    }
#if defined(WAWONA_APPLE_MOBILE)
    }
#endif
    ffListDestroy(&platform->dataDirs);"""
if "ffListDataIsValid(&platform->configDirs)" not in text:
    if cfgdirs_anchor not in text:
        raise SystemExit("FFPlatform.c configDirs destroy anchor missing")
    text = text.replace(cfgdirs_anchor, cfgdirs_patch, 1)
    ffplatform.write_text(text)

io_unix = Path("src/common/impl/io_unix.c")
text = io_unix.read_text()
if "WAWONA_APPLE_MOBILE" not in text:
    term_anchor = "        atexit(restoreTerm);"
    term_patch = """#if !defined(WAWONA_APPLE_MOBILE)
        atexit(restoreTerm);
#endif"""
    if term_anchor not in text:
        raise SystemExit("io_unix.c atexit(restoreTerm) anchor missing")
    text = text.replace(term_anchor, term_patch, 1)
    io_unix.write_text(text)

# --- Phase 3: LocalIp via upstream localip_linux.c on Apple mobile -------------
# getifaddrs works in the iOS sandbox (self IP needs no permission), but the
# BSD/Apple link-speed path pulls <net/if_media.h> and SIOCGIFMEDIA, neither of
# which exists on the iOS SDK. Drop just the media/speed detection on Apple
# mobile (not meaningful there); macOS keeps full behavior.
localip = Path("src/detection/localip/localip_linux.c")
text = localip.read_text()
if "WAWONA_APPLE_MOBILE" not in text:
    inc_anchor = """#if defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__APPLE__) || defined(__NetBSD__) || defined(__HAIKU__)
    #include <net/if_media.h>
    #include <net/if_dl.h>"""
    inc_patch = """#if defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__APPLE__) || defined(__NetBSD__) || defined(__HAIKU__)
    #if !defined(WAWONA_APPLE_MOBILE)
    #include <net/if_media.h>
    #endif
    #include <net/if_dl.h>"""
    if inc_anchor not in text:
        raise SystemExit("localip_linux.c if_media include anchor missing")
    text = text.replace(inc_anchor, inc_patch, 1)

    speed_anchor = """#elif __FreeBSD__ || __APPLE__ || __OpenBSD__ || __NetBSD__
                    struct ifmediareq ifmr = {};"""
    speed_patch = """#elif (__FreeBSD__ || __APPLE__ || __OpenBSD__ || __NetBSD__) && !defined(WAWONA_APPLE_MOBILE)
                    struct ifmediareq ifmr = {};"""
    if speed_anchor not in text:
        raise SystemExit("localip_linux.c media-speed branch anchor missing")
    text = text.replace(speed_anchor, speed_patch, 1)
    localip.write_text(text)

# --- watchOS: no IOKit framework/headers at all -------------------------------
# iOS/iPadOS/tvOS/visionOS ship IOKit headers (we just don't link/use them), but
# watchOS omits IOKit entirely. Gate IOKit behind __has_include so the shared
# CoreFoundation helper header and the SMBIOS reader compile on watchOS. Our
# CPU/host/SMC stubs already avoid IORegistry, so nothing else needs IOKit.
cf_helpers = Path("src/common/apple/cf_helpers.h")
text = cf_helpers.read_text()
if "FF_HAS_IOKIT" not in text:
    inc_anchor = """#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>"""
    inc_patch = """#include <CoreFoundation/CoreFoundation.h>
#if __has_include(<IOKit/IOKitLib.h>)
#include <IOKit/IOKitLib.h>
#define FF_HAS_IOKIT 1
#endif"""
    if inc_anchor not in text:
        raise SystemExit("cf_helpers.h IOKit include anchor missing")
    text = text.replace(inc_anchor, inc_patch, 1)

    io_anchor = """static inline void wrapIoObjectRelease(io_object_t* service) {
    assert(service);
    if (*service) {
        IOObjectRelease(*service);
    }
}
#define FF_IOOBJECT_AUTO_RELEASE FF_A_CLEANUP(wrapIoObjectRelease)"""
    io_patch = """#ifdef FF_HAS_IOKIT
static inline void wrapIoObjectRelease(io_object_t* service) {
    assert(service);
    if (*service) {
        IOObjectRelease(*service);
    }
}
#define FF_IOOBJECT_AUTO_RELEASE FF_A_CLEANUP(wrapIoObjectRelease)
#endif"""
    if io_anchor not in text:
        raise SystemExit("cf_helpers.h io_object helper anchor missing")
    text = text.replace(io_anchor, io_patch, 1)
    cf_helpers.write_text(text)

smbios = Path("src/common/impl/smbios.c")
text = smbios.read_text()
if "SMBIOS unavailable" not in text:
    smbios_anchor = """#elif defined(__APPLE__)
    #include "common/apple/cf_helpers.h\""""
    smbios_patch = """#elif defined(__APPLE__) && __has_include(<IOKit/IOKitLib.h>)
    #include "common/apple/cf_helpers.h\""""
    if smbios_anchor not in text:
        raise SystemExit("smbios.c Apple branch anchor missing")
    text = text.replace(smbios_anchor, smbios_patch, 1)

    smbios_tail = """    return &smbiosTable;
}
#endif"""
    smbios_tail_patch = """    return &smbiosTable;
}
#elif defined(__APPLE__)
const FFSmbiosHeaderTable* ffGetSmbiosHeaderTable() {
    // SMBIOS unavailable without IOKit (watchOS).
    return NULL;
}
#endif"""
    if smbios_tail not in text:
        raise SystemExit("smbios.c Apple branch tail anchor missing")
    text = text.replace(smbios_tail, smbios_tail_patch, 1)
    smbios.write_text(text)

# --- display: force TTY mode (colors + DECAWM off) on Apple mobile --------------
# In-process stdout may not pass isatty() at init; pipe mode strips ANSI escapes
# and leaves autowrap enabled, so weston-terminal wraps instead of truncating.
display_c = Path("src/options/display.c")
text = display_c.read_text()
if "WAWONA_APPLE_MOBILE" not in text:
    display_anchor = """    options->pipe = !isatty(STDOUT_FILENO) || !!getenv("NO_COLOR");

#ifdef NDEBUG
    options->disableLinewrap = !options->pipe;
#else
    options->disableLinewrap = false;
    options->debugMode = !!getenv("FF_DEBUG");
#endif"""
    display_patch = """#if defined(WAWONA_APPLE_MOBILE)
    options->pipe = false;
    options->disableLinewrap = true;
#else
    options->pipe = !isatty(STDOUT_FILENO) || !!getenv("NO_COLOR");

#ifdef NDEBUG
    options->disableLinewrap = !options->pipe;
#else
    options->disableLinewrap = false;
    options->debugMode = !!getenv("FF_DEBUG");
#endif
#endif"""
    if display_anchor not in text:
        raise SystemExit("display.c ffOptionsInitDisplay pipe anchor missing")
    display_c.write_text(text.replace(display_anchor, display_patch, 1))
