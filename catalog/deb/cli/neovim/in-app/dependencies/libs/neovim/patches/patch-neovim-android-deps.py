#!/usr/bin/env python3
"""Forward Android cross settings from cmake.deps into bundled dependency builds."""
from pathlib import Path

cmake_deps = Path("cmake.deps/CMakeLists.txt")
text = cmake_deps.read_text()
anchor = "  list(APPEND DEPS_CMAKE_ARGS -D CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE})"
patch = """  list(APPEND DEPS_CMAKE_ARGS -D CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE})
if(CMAKE_SYSTEM_NAME STREQUAL "Android")
  list(APPEND DEPS_CMAKE_ARGS
    -D CMAKE_PREFIX_PATH=${DEPS_INSTALL_DIR}
    -D CMAKE_FIND_ROOT_PATH=${DEPS_INSTALL_DIR}
    -D CMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH
    -D CMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH
    -D CMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH)
  foreach(_wawona_android_flag
      CMAKE_SYSTEM_NAME
      CMAKE_SYSTEM_VERSION
      CMAKE_ANDROID_NDK
      CMAKE_ANDROID_ARCH_ABI
      CMAKE_ANDROID_STL_TYPE
      CMAKE_C_COMPILER
      CMAKE_CXX_COMPILER
      CMAKE_TRY_COMPILE_TARGET_TYPE
      CMAKE_C_COMPILER_WORKS
      CMAKE_CXX_COMPILER_WORKS
      CMAKE_OSX_ARCHITECTURES
      CMAKE_OSX_SYSROOT
      CMAKE_OSX_DEPLOYMENT_TARGET)
    if(DEFINED ${_wawona_android_flag})
      list(APPEND DEPS_CMAKE_ARGS -D ${_wawona_android_flag}=${${_wawona_android_flag}})
    endif()
  endforeach()
endif()"""
if anchor in text and "WAWONA_ANDROID_DEPS" not in text and "CMAKE_SYSTEM_NAME STREQUAL \"Android\"" not in text:
    cmake_deps.write_text(text.replace(anchor, patch, 1))

find_libuv = Path("cmake/FindLibuv.cmake")
fl_text = find_libuv.read_text()
fl_anchor = "set(LIBUV_LIBRARIES ${LIBUV_LIBRARY})\n\ncheck_library_exists(dl dlopen"
fl_patch = """set(LIBUV_LIBRARIES ${LIBUV_LIBRARY})

if(CMAKE_SYSTEM_NAME STREQUAL "Android")
  find_package_handle_standard_args(Libuv DEFAULT_MSG
                                    LIBUV_LIBRARY LIBUV_INCLUDE_DIR)
  mark_as_advanced(LIBUV_INCLUDE_DIR LIBUV_LIBRARY)
  add_library(libuv INTERFACE)
  target_include_directories(libuv SYSTEM BEFORE INTERFACE ${LIBUV_INCLUDE_DIR})
  target_link_libraries(libuv INTERFACE ${LIBUV_LIBRARIES})
  return()
endif()

check_library_exists(dl dlopen"""
if fl_anchor in fl_text and 'CMAKE_SYSTEM_NAME STREQUAL "Android"' not in fl_text:
    find_libuv.write_text(fl_text.replace(fl_anchor, fl_patch, 1))

nvim_cmake = Path("src/nvim/CMakeLists.txt")
nc_text = nvim_cmake.read_text()
util_anchor = """  if (NOT CMAKE_SYSTEM_NAME STREQUAL "SunOS")
    target_link_libraries(main_lib INTERFACE util)"""
util_patch = """  if (NOT CMAKE_SYSTEM_NAME STREQUAL "SunOS" AND NOT CMAKE_SYSTEM_NAME STREQUAL "Android")
    target_link_libraries(main_lib INTERFACE util)"""
if util_anchor in nc_text and 'STREQUAL "Android"' not in nc_text.split("util")[0][-200:]:
    nvim_cmake.write_text(nc_text.replace(util_anchor, util_patch, 1))

build_lua = Path("cmake.deps/cmake/BuildLua.cmake")
bl_text = build_lua.read_text()
bl_anchor = """if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  set(LUA_TARGET linux)
elseif(APPLE)"""
bl_patch = """if(CMAKE_SYSTEM_NAME STREQUAL "Android")
  set(LUA_TARGET linux)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  set(LUA_TARGET linux)
elseif(APPLE)"""
if bl_anchor in bl_text and 'STREQUAL "Android"' not in bl_text:
    bl_text = bl_text.replace(bl_anchor, bl_patch, 1)

lua_cflags_anchor = "set(LUA_CFLAGS \"-O2 -g3 -fPIC\")\nset(LUA_LDFLAGS \"\")"
lua_cflags_patch = """set(LUA_CFLAGS "-O2 -g3 -fPIC")
if(CMAKE_SYSTEM_NAME STREQUAL "Android")
  if(CMAKE_C_COMPILER_TARGET)
    string(APPEND LUA_CFLAGS " --target=${CMAKE_C_COMPILER_TARGET}")
  endif()
  if(CMAKE_SYSROOT)
    string(APPEND LUA_CFLAGS " --sysroot=${CMAKE_SYSROOT}")
  endif()
  string(APPEND LUA_CFLAGS " ${CMAKE_C_FLAGS}")
endif()
set(LUA_LDFLAGS "")"""
if lua_cflags_anchor in bl_text and "CMAKE_C_COMPILER_TARGET" not in bl_text:
    bl_text = bl_text.replace(lua_cflags_anchor, lua_cflags_patch, 1)

lua_only_anchor = """  BUILD_COMMAND ${MAKE_PRG} ${LUA_INSTALL_TOP_ARG} ${LUA_TARGET}
  INSTALL_COMMAND ${MAKE_PRG} ${LUA_INSTALL_TOP_ARG} install"""
lua_only_patch = (
    "  BUILD_COMMAND ${MAKE_PRG} ${LUA_INSTALL_TOP_ARG} -C src liblua.a\n"
    "  INSTALL_COMMAND ${CMAKE_COMMAND} -E make_directory ${DEPS_LIB_DIR} ${DEPS_INSTALL_DIR}/include && "
    "${CMAKE_COMMAND} -E copy ${DEPS_BUILD_DIR}/src/lua/src/liblua.a ${DEPS_LIB_DIR}/liblua.a && "
    "${CMAKE_COMMAND} -DFROM_GLOB=${DEPS_BUILD_DIR}/src/lua/src/*.h -DTO=${DEPS_INSTALL_DIR}/include "
    "-P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/CopyFilesGlob.cmake # WAWONA_ANDROID_LUA"
)
if lua_only_anchor in bl_text and "WAWONA_ANDROID_LUA" not in bl_text:
    bl_text = bl_text.replace(lua_only_anchor, lua_only_patch, 1)
elif "WAWONA_ANDROID_LUA" not in bl_text:
    bl_text = bl_text.replace(
        "BUILD_COMMAND ${MAKE_PRG} CC=${DEPS_C_COMPILER} ${LUA_INSTALL_TOP_ARG} ${LUA_TARGET}",
        "BUILD_COMMAND ${MAKE_PRG} ${LUA_INSTALL_TOP_ARG} -C src liblua.a",
        1,
    )
    bl_text = bl_text.replace(
        "INSTALL_COMMAND ${MAKE_PRG} CC=${DEPS_C_COMPILER} ${LUA_INSTALL_TOP_ARG} install",
        "INSTALL_COMMAND ${CMAKE_COMMAND} -E make_directory ${DEPS_LIB_DIR} ${DEPS_INSTALL_DIR}/include && "
        "${CMAKE_COMMAND} -E copy ${DEPS_BUILD_DIR}/src/lua/src/liblua.a ${DEPS_LIB_DIR}/liblua.a && "
        "${CMAKE_COMMAND} -DFROM_GLOB=${DEPS_BUILD_DIR}/src/lua/src/*.h -DTO=${DEPS_INSTALL_DIR}/include "
        "-P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/CopyFilesGlob.cmake # WAWONA_ANDROID_LUA",
        1,
    )

original_bl_text = build_lua.read_text()
if bl_text != original_bl_text:
    build_lua.write_text(bl_text)
