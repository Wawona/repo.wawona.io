#!/usr/bin/env python3
"""App Store–safe Neovim on Apple mobile: PUC Lua, no providers, spawn stubs."""
from pathlib import Path

CMAKE_ANCHOR = 'option(ENABLE_LIBINTL "enable libintl" ON)'
CMAKE_SNIPPET = Path(__file__).with_name("cmake-apple-mobile-flags.snippet").read_text()
DEPS_CMAKE_ANCHOR = 'option(USE_BUNDLED_LUAJIT "Use the bundled version of luajit." ${USE_BUNDLED})'
DEPS_CMAKE_SNIPPET = Path(__file__).with_name("cmake-deps-apple-mobile.snippet").read_text()

cmake = Path("CMakeLists.txt")
text = cmake.read_text()
if "WAWONA_APPLE_MOBILE" not in text:
    if CMAKE_ANCHOR not in text:
        raise SystemExit("CMakeLists BUILD_LIBNVIM anchor missing")
    cmake.write_text(text.replace(CMAKE_ANCHOR, CMAKE_SNIPPET + "\n" + CMAKE_ANCHOR, 1))

deps_cmake = Path("cmake.deps/CMakeLists.txt")
deps_text = deps_cmake.read_text()
if "WAWONA_APPLE_MOBILE" not in deps_text:
    if DEPS_CMAKE_ANCHOR not in deps_text:
        raise SystemExit("cmake.deps USE_BUNDLED_LUAJIT anchor missing")
    deps_cmake.write_text(deps_text.replace(DEPS_CMAKE_ANCHOR, DEPS_CMAKE_SNIPPET + "\n" + DEPS_CMAKE_ANCHOR, 1))

build_lua = Path("cmake.deps/cmake/BuildLua.cmake")
lua_text = build_lua.read_text()
lua_anchor = "elseif(APPLE)\n  set(LUA_TARGET macosx)"
lua_patch = "elseif(WAWONA_APPLE_MOBILE)\n  set(LUA_TARGET posix)\nelseif(APPLE)\n  set(LUA_TARGET macosx)"
if lua_anchor in lua_text and "WAWONA_APPLE_MOBILE" not in lua_text:
    build_lua.write_text(lua_text.replace(lua_anchor, lua_patch, 1))
    lua_text = build_lua.read_text()
lua_cflags_anchor = 'set(LUA_CFLAGS "-O2 -g3 -fPIC")\nset(LUA_LDFLAGS "")'
lua_cflags_patch = """set(LUA_CFLAGS "-O2 -g3 -fPIC")
if(WAWONA_APPLE_MOBILE)
  if(CMAKE_C_COMPILER_TARGET)
    string(APPEND LUA_CFLAGS " -target ${CMAKE_C_COMPILER_TARGET}")
  endif()
  if(CMAKE_OSX_SYSROOT)
    string(APPEND LUA_CFLAGS " -isysroot ${CMAKE_OSX_SYSROOT}")
  endif()
  if(CMAKE_OSX_ARCHITECTURES)
    string(APPEND LUA_CFLAGS " -arch ${CMAKE_OSX_ARCHITECTURES}")
  endif()
  if(CMAKE_OSX_DEPLOYMENT_TARGET AND CMAKE_SYSTEM_NAME STREQUAL "iOS")
    if(CMAKE_C_COMPILER_TARGET MATCHES "simulator")
      string(APPEND LUA_CFLAGS " -mios-simulator-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET}")
    else()
      string(APPEND LUA_CFLAGS " -miphoneos-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET}")
    endif()
  endif()
  string(APPEND LUA_CFLAGS " ${CMAKE_C_FLAGS}")
endif()
set(LUA_LDFLAGS "")"""
if lua_cflags_anchor in lua_text and "WAWONA_APPLE_MOBILE_LUA_CFLAGS" not in lua_text:
    build_lua.write_text(lua_text.replace(lua_cflags_anchor, lua_cflags_patch, 1))
    lua_text = build_lua.read_text()

lua_cross_build = """if(WAWONA_APPLE_MOBILE AND CMAKE_C_COMPILER_TARGET)
  set(WAWONA_LUA_BUILD_COMMAND ${CMAKE_COMMAND} -E env CC=${CMAKE_C_COMPILER} AR=${CMAKE_AR} RANLIB=${CMAKE_RANLIB} bash ${CMAKE_CURRENT_LIST_DIR}/../../patch-and-build-lua-apple-mobile.sh ${DEPS_BUILD_DIR}/src/lua/src ${DEPS_INSTALL_DIR} ${MAKE_PRG} "${LUA_CFLAGS}")
  set(WAWONA_LUA_INSTALL_COMMAND ${CMAKE_COMMAND} -E make_directory ${DEPS_LIB_DIR} ${DEPS_INSTALL_DIR}/include && ${CMAKE_COMMAND} -E copy ${DEPS_BUILD_DIR}/src/lua/src/liblua.a ${DEPS_LIB_DIR}/liblua.a && ${CMAKE_COMMAND} -DFROM_GLOB=${DEPS_BUILD_DIR}/src/lua/src/*.h -DTO=${DEPS_INSTALL_DIR}/include -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/CopyFilesGlob.cmake)
else()
  set(WAWONA_LUA_BUILD_COMMAND ${MAKE_PRG} ${LUA_INSTALL_TOP_ARG} ${LUA_TARGET})
  set(WAWONA_LUA_INSTALL_COMMAND ${MAKE_PRG} ${LUA_INSTALL_TOP_ARG} install)
endif()
"""
if "WAWONA_LUA_BUILD_COMMAND" in lua_text and 'patch-and-build-lua-apple-mobile.sh ${DEPS_BUILD_DIR}/src/lua/src ${DEPS_INSTALL_DIR} ${MAKE_PRG} "${LUA_CFLAGS}"' not in lua_text:
    build_lua.write_text(lua_text.replace(
        "bash ${CMAKE_CURRENT_LIST_DIR}/../../patch-and-build-lua-apple-mobile.sh ${DEPS_BUILD_DIR}/src/lua/src ${DEPS_INSTALL_DIR} ${MAKE_PRG})",
        "bash ${CMAKE_CURRENT_LIST_DIR}/../../patch-and-build-lua-apple-mobile.sh ${DEPS_BUILD_DIR}/src/lua/src ${DEPS_INSTALL_DIR} ${MAKE_PRG} \"${LUA_CFLAGS}\")",
        1,
    ).replace(
        "MYCFLAGS=\"${LUA_CFLAGS}\" bash",
        "bash",
        1,
    ))
    lua_text = build_lua.read_text()

lua_ep_anchor = "get_externalproject_options(lua ${DEPS_IGNORE_SHA})"
if "WAWONA_LUA_BUILD_COMMAND" not in lua_text and lua_ep_anchor in lua_text:
    build_lua.write_text(lua_text.replace(lua_ep_anchor, lua_cross_build + lua_ep_anchor, 1))
    lua_text = build_lua.read_text()

for old_build in (
    "  BUILD_COMMAND ${CMAKE_COMMAND} -E env CC=${CMAKE_C_COMPILER} AR=${CMAKE_AR} RANLIB=${CMAKE_RANLIB} MYCFLAGS=\"${LUA_CFLAGS}\" bash ${CMAKE_CURRENT_LIST_DIR}/../../patch-and-build-lua-apple-mobile.sh ${DEPS_BUILD_DIR}/src/lua/src ${DEPS_INSTALL_DIR} ${MAKE_PRG}\n",
    "  BUILD_COMMAND ${MAKE_PRG} ${LUA_INSTALL_TOP_ARG} -C src liblua.a\n",
    "  BUILD_COMMAND ${MAKE_PRG} ${LUA_INSTALL_TOP_ARG} ${LUA_TARGET}\n",
):
    if old_build in lua_text:
        build_lua.write_text(lua_text.replace(old_build, "  BUILD_COMMAND ${WAWONA_LUA_BUILD_COMMAND}\n", 1))
        lua_text = build_lua.read_text()
        break

for old_install in (
    "  INSTALL_COMMAND ${CMAKE_COMMAND} -E make_directory ${DEPS_LIB_DIR} ${DEPS_INSTALL_DIR}/include && "
    "${CMAKE_COMMAND} -E copy ${DEPS_BUILD_DIR}/src/lua/src/liblua.a ${DEPS_LIB_DIR}/liblua.a && "
    "${CMAKE_COMMAND} -DFROM_GLOB=${DEPS_BUILD_DIR}/src/lua/src/*.h -DTO=${DEPS_INSTALL_DIR}/include "
    "-P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/CopyFilesGlob.cmake # WAWONA_APPLE_MOBILE_LUA\n",
    "  INSTALL_COMMAND ${MAKE_PRG} ${LUA_INSTALL_TOP_ARG} install\n",
):
    if old_install in lua_text:
        build_lua.write_text(lua_text.replace(old_install, "  INSTALL_COMMAND ${WAWONA_LUA_INSTALL_COMMAND}\n", 1))
        lua_text = build_lua.read_text()
        break

for broken in (
    """if(WAWONA_APPLE_MOBILE AND CMAKE_C_COMPILER_TARGET)
  string(APPEND LUA_CONFIGURE_COMMAND " && python3 ${CMAKE_CURRENT_LIST_DIR}/../../patch-lua-loslib-apple-mobile.py ${DEPS_BUILD_DIR}/src/lua/src/loslib.c")
endif()
""",
    """set(LUA_APPLE_MOBILE_LOSLIB_PATCH "")
if(WAWONA_APPLE_MOBILE AND CMAKE_C_COMPILER_TARGET)
  set(LUA_APPLE_MOBILE_LOSLIB_PATCH "&& python3 ${CMAKE_CURRENT_LIST_DIR}/../../patch-lua-loslib-apple-mobile.py ${DEPS_BUILD_DIR}/src/lua/src/loslib.c")
endif()
""",
):
    if broken in lua_text:
        build_lua.write_text(lua_text.replace(broken, "", 1))
        lua_text = build_lua.read_text()
if "${LUA_APPLE_MOBILE_LOSLIB_PATCH}" in lua_text:
    build_lua.write_text(lua_text.replace(" ${LUA_APPLE_MOBILE_LOSLIB_PATCH}", "", 1))

install_helpers = Path("cmake/InstallHelpers.cmake")
ih_text = install_helpers.read_text()
ih_old = "      RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})"
ih_new = "      RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}\n      BUNDLE DESTINATION ${CMAKE_INSTALL_BINDIR})"
if ih_old in ih_text and "BUNDLE DESTINATION" not in ih_text:
    install_helpers.write_text(ih_text.replace(ih_old, ih_new, 1))

nvim_cmake = Path("src/nvim/CMakeLists.txt")
nc_text = nvim_cmake.read_text()
lua_gen_anchor = (
    "set(LUA_GEN ${LUA_GEN_PRG} ${GENERATOR_PRELOAD} ${PROJECT_SOURCE_DIR} "
    "$<TARGET_FILE:nlua0> ${PROJECT_BINARY_DIR})\n"
    "set(LUA_GEN_DEPS ${GENERATOR_PRELOAD} $<TARGET_FILE:nlua0>)"
)
lua_gen_patch = """if(DEFINED ENV{WAWONA_HOST_NLUA0})
  set(WAWONA_NLUA0_FOR_GEN $ENV{WAWONA_HOST_NLUA0})
else()
  set(WAWONA_NLUA0_FOR_GEN $<TARGET_FILE:nlua0>)
endif()
set(LUA_GEN ${LUA_GEN_PRG} ${GENERATOR_PRELOAD} ${PROJECT_SOURCE_DIR} ${WAWONA_NLUA0_FOR_GEN} ${PROJECT_BINARY_DIR})
set(LUA_GEN_DEPS ${GENERATOR_PRELOAD} ${WAWONA_NLUA0_FOR_GEN})"""
if lua_gen_anchor in nc_text and "WAWONA_HOST_NLUA0" not in nc_text:
    nvim_cmake.write_text(nc_text.replace(lua_gen_anchor, lua_gen_patch, 1))
    nc_text = nvim_cmake.read_text()

gen_sysroot_anchor = """if(APPLE AND CMAKE_OSX_SYSROOT)
  list(APPEND gen_cflags "-isysroot" "${CMAKE_OSX_SYSROOT}")
endif()"""
gen_sysroot_patch = """if(APPLE AND CMAKE_OSX_SYSROOT)
  if(DEFINED ENV{WAWONA_HOST_NLUA0})
    execute_process(COMMAND xcrun --sdk macosx --show-sdk-path
                    OUTPUT_VARIABLE WAWONA_MACOS_SDK OUTPUT_STRIP_TRAILING_WHITESPACE)
    list(APPEND gen_cflags "-isysroot" "${WAWONA_MACOS_SDK}")
  else()
    list(APPEND gen_cflags "-isysroot" "${CMAKE_OSX_SYSROOT}")
  endif()
endif()"""
if gen_sysroot_anchor in nc_text and "WAWONA_MACOS_SDK" not in nc_text:
    nvim_cmake.write_text(nc_text.replace(gen_sysroot_anchor, gen_sysroot_patch, 1))
    nc_text = nvim_cmake.read_text()

gen_cc_setup_anchor = "if(MSVC)\n  list(APPEND gen_cflags -wd4003)\nendif()"
gen_cc_setup_patch = """if(DEFINED ENV{WAWONA_HOST_NLUA0})
  execute_process(COMMAND xcrun --sdk macosx --find clang
                  OUTPUT_VARIABLE WAWONA_GEN_CC OUTPUT_STRIP_TRAILING_WHITESPACE)
else()
  set(WAWONA_GEN_CC ${CMAKE_C_COMPILER})
endif()
if(MSVC)
  list(APPEND gen_cflags -wd4003)
endif()"""
if gen_cc_setup_anchor in nc_text and "WAWONA_GEN_CC" not in nc_text:
    nvim_cmake.write_text(nc_text.replace(gen_cc_setup_anchor, gen_cc_setup_patch, 1))
    nc_text = nvim_cmake.read_text()

gen_cc_anchor = "    COMMAND ${CMAKE_C_COMPILER} ${sfile} ${PREPROC_OUTPUT} ${gen_cflags}"
gen_cc_patch = "    COMMAND ${WAWONA_GEN_CC} ${sfile} ${PREPROC_OUTPUT} ${gen_cflags}"
if gen_cc_anchor in nc_text:
    nvim_cmake.write_text(nc_text.replace(gen_cc_anchor, gen_cc_patch, 1))

# iOS SDK exposes be64toh in cmake checks but not htobe64 at compile time; use fallbacks.
config_cmake = Path("cmake.config/CMakeLists.txt")
cc_text = config_cmake.read_text()
be64_anchor = """if("${HAVE_BE64TOH_MACROS}" OR "${HAVE_BE64TOH_FUNC}")
  set(HAVE_BE64TOH 1)
endif()

test_big_endian(ORDER_BIG_ENDIAN)"""
be64_patch = """if("${HAVE_BE64TOH_MACROS}" OR "${HAVE_BE64TOH_FUNC}")
  set(HAVE_BE64TOH 1)
endif()
if(WAWONA_APPLE_MOBILE)
  unset(HAVE_BE64TOH)
endif()

test_big_endian(ORDER_BIG_ENDIAN)"""
if be64_anchor in cc_text and "unset(HAVE_BE64TOH)" not in cc_text:
    config_cmake.write_text(cc_text.replace(be64_anchor, be64_patch, 1))

lang_c = Path("src/nvim/os/lang.c")
lang_text = lang_c.read_text()
lang_changed = False
cs_include_anchor = """#ifdef __APPLE__
# define Boolean CFBoolean  // Avoid conflict with API's Boolean
# define FileInfo CSFileInfo  // Avoid conflict with API's Fileinfo
# include <CoreServices/CoreServices.h>

# undef Boolean
# undef FileInfo
#endif"""
cs_include_patch = """#if defined(__APPLE__) && !defined(WAWONA_APPLE_MOBILE)
# define Boolean CFBoolean  // Avoid conflict with API's Boolean
# define FileInfo CSFileInfo  // Avoid conflict with API's Fileinfo
# include <CoreServices/CoreServices.h>

# undef Boolean
# undef FileInfo
#elif defined(WAWONA_APPLE_MOBILE)
# define Boolean CFBoolean  // Avoid conflict with MacTypes.h Boolean
# include <CoreFoundation/CoreFoundation.h>
# undef Boolean
#endif"""
if cs_include_anchor in lang_text:
    lang_text = lang_text.replace(cs_include_anchor, cs_include_patch, 1)
    lang_changed = True

lang_init_anchor = """void lang_init(void)
{
#ifdef __APPLE__
  if (os_getenv("LANG") == NULL) {
    char buf[50] = { 0 };

    // $LANG is not set, either because it was unset or Nvim was started
    // from the Dock. Query the system locale.
    if (LocaleRefGetPartString(NULL,
                               kLocaleLanguageMask | kLocaleLanguageVariantMask |
                               kLocaleRegionMask | kLocaleRegionVariantMask,
                               sizeof(buf) - 10, buf) == noErr && *buf) {
      if (strcasestr(buf, "utf-8") == NULL) {
        xstrlcat(buf, ".UTF-8", sizeof(buf));
      }
      os_setenv("LANG", buf, true);
      setlocale(LC_ALL, "");
      // Make sure strtod() uses a decimal point, not a comma.
      setlocale(LC_NUMERIC, "C");
    } else {
      ELOG("$LANG is empty and the macOS primary language cannot be inferred.");
    }
  }
#endif
}"""
lang_init_patch = """void lang_init(void)
{
#if defined(WAWONA_APPLE_MOBILE)
  if (os_getenv("LANG") == NULL) {
    char buf[50] = { 0 };
    CFLocaleRef locale = CFLocaleCopyCurrent();
    CFStringRef lang = CFLocaleGetValue(locale, kCFLocaleLanguageCode);
    CFStringRef region = CFLocaleGetValue(locale, kCFLocaleCountryCode);
    if (lang && CFStringGetCString(lang, buf, sizeof(buf), kCFStringEncodingUTF8)) {
      if (region && CFStringGetLength(region) > 0) {
        char region_buf[16] = { 0 };
        CFStringGetCString(region, region_buf, sizeof(region_buf), kCFStringEncodingUTF8);
        xstrlcat(buf, "_", sizeof(buf));
        xstrlcat(buf, region_buf, sizeof(buf));
      }
      if (strcasestr(buf, "utf-8") == NULL) {
        xstrlcat(buf, ".UTF-8", sizeof(buf));
      }
      os_setenv("LANG", buf, true);
      setlocale(LC_ALL, "");
      setlocale(LC_NUMERIC, "C");
    } else {
      os_setenv("LANG", "en_US.UTF-8", true);
      setlocale(LC_ALL, "");
      setlocale(LC_NUMERIC, "C");
    }
    CFRelease(locale);
  }
#elif defined(__APPLE__)
  if (os_getenv("LANG") == NULL) {
    char buf[50] = { 0 };

    // $LANG is not set, either because it was unset or Nvim was started
    // from the Dock. Query the system locale.
    if (LocaleRefGetPartString(NULL,
                               kLocaleLanguageMask | kLocaleLanguageVariantMask |
                               kLocaleRegionMask | kLocaleRegionVariantMask,
                               sizeof(buf) - 10, buf) == noErr && *buf) {
      if (strcasestr(buf, "utf-8") == NULL) {
        xstrlcat(buf, ".UTF-8", sizeof(buf));
      }
      os_setenv("LANG", buf, true);
      setlocale(LC_ALL, "");
      // Make sure strtod() uses a decimal point, not a comma.
      setlocale(LC_NUMERIC, "C");
    } else {
      ELOG("$LANG is empty and the macOS primary language cannot be inferred.");
    }
  }
#endif
}"""
if lang_init_anchor in lang_text:
    lang_text = lang_text.replace(lang_init_anchor, lang_init_patch, 1)
    lang_changed = True
if lang_changed:
    lang_c.write_text(lang_text)

# os_system / :! / :grep external paths
shell = Path("src/nvim/os/shell.c")
text = shell.read_text()
if "WAWONA_APPLE_MOBILE_SYSTEM" not in text:
    anchor = "static int do_os_system(char **argv, const char *input, size_t len, char **output, size_t *nread,\n                        bool silent, bool forward_output)\n{"
    patch = anchor + """
#if defined(WAWONA_APPLE_MOBILE)
  if (!silent) {
    msg_puts(_("\\nwawona: external shell commands unavailable on Apple mobile (App Store compliance)\\n"));
  }
  return -1;
#endif
"""
    if anchor not in text:
        raise SystemExit("shell.c do_os_system anchor missing")
    shell.write_text(text.replace(anchor, patch, 1))

# Dynamic module load (providers)
provider = Path("src/nvim/ex_cmds2.c")
if provider.exists():
    text = provider.read_text()
    anchor = "bool provider_exists(const char *name)"
    if anchor in text and "WAWONA_APPLE_MOBILE_PROVIDER" not in text:
        patch = """#if defined(WAWONA_APPLE_MOBILE)
bool provider_exists(const char *name)
{
  (void)name;
  return false;
}
#else
""" + anchor
        # Only patch if we can find end of function - skip complex patch, cmake disables providers

import subprocess
subprocess.check_call(["python3", str(Path(__file__).with_name("patch-libuv-spawn.py"))])

print("neovim apple-mobile patches applied")
