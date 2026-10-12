#!/usr/bin/env python3
"""Allow Neovim Android cross-builds to reuse a host-built libnlua0.so for codegen."""
from pathlib import Path

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

gen_cc_setup_anchor = "if(MSVC)\n  list(APPEND gen_cflags -wd4003)\nendif()"
gen_cc_setup_patch = """if(DEFINED ENV{WAWONA_GEN_CC})
  set(WAWONA_GEN_CC $ENV{WAWONA_GEN_CC})
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
    nc_text = nvim_cmake.read_text()

nlua0_anchor = "add_library(nlua0 MODULE)\nif(WIN32)\n  target_compile_definitions(nlua0 PUBLIC LUA_BUILD_AS_DLL LUA_LIB)\n  set_target_properties(nlua0 PROPERTIES ENABLE_EXPORTS TRUE)\nelseif(APPLE)\n  target_link_options(nlua0 PRIVATE -undefined dynamic_lookup)\nendif()"
nlua0_patch = """if(DEFINED ENV{WAWONA_HOST_NLUA0})
  add_library(nlua0 SHARED IMPORTED GLOBAL)
  set_target_properties(nlua0 PROPERTIES IMPORTED_LOCATION "$ENV{WAWONA_HOST_NLUA0}")
else()
  add_library(nlua0 MODULE)
  if(WIN32)
    target_compile_definitions(nlua0 PUBLIC LUA_BUILD_AS_DLL LUA_LIB)
    set_target_properties(nlua0 PROPERTIES ENABLE_EXPORTS TRUE)
  elseif(APPLE)
    target_link_options(nlua0 PRIVATE -undefined dynamic_lookup)
  endif()
endif()"""
if nlua0_anchor in nc_text and "IMPORTED_LOCATION" not in nc_text:
    nvim_cmake.write_text(nc_text.replace(nlua0_anchor, nlua0_patch, 1))
    nc_text = nvim_cmake.read_text()

for anchor, patch in [
    (
        "target_link_libraries(nlua0 PUBLIC lpeg)",
        "if(NOT DEFINED ENV{WAWONA_HOST_NLUA0})\n  target_link_libraries(nlua0 PUBLIC lpeg)\nendif()",
    ),
    (
        "  target_include_directories(nlua0 SYSTEM BEFORE PUBLIC ${LUA_INCLUDE_DIR})",
        "  if(NOT DEFINED ENV{WAWONA_HOST_NLUA0})\n    target_include_directories(nlua0 SYSTEM BEFORE PUBLIC ${LUA_INCLUDE_DIR})\n  endif()",
    ),
    (
        "  target_include_directories(nlua0 SYSTEM BEFORE PUBLIC ${LUAJIT_INCLUDE_DIR})",
        "  if(NOT DEFINED ENV{WAWONA_HOST_NLUA0})\n    target_include_directories(nlua0 SYSTEM BEFORE PUBLIC ${LUAJIT_INCLUDE_DIR})\n  endif()",
    ),
    (
        "    target_link_libraries(nlua0 PUBLIC ${LUAJIT_LIBRARY})",
        "    if(NOT DEFINED ENV{WAWONA_HOST_NLUA0})\n      target_link_libraries(nlua0 PUBLIC ${LUAJIT_LIBRARY})\n    endif()",
    ),
    (
        "target_include_directories(nlua0 PUBLIC\n  \"${PROJECT_SOURCE_DIR}/src\"\n  \"${PROJECT_BINARY_DIR}/cmake.config\"\n  ${GENERATED_INCLUDES_DIR})",
        "if(NOT DEFINED ENV{WAWONA_HOST_NLUA0})\n  target_include_directories(nlua0 PUBLIC\n    \"${PROJECT_SOURCE_DIR}/src\"\n    \"${PROJECT_BINARY_DIR}/cmake.config\"\n    ${GENERATED_INCLUDES_DIR})\nendif()",
    ),
    (
        "target_sources(nlua0 PUBLIC ${NLUA0_SOURCES})",
        "if(NOT DEFINED ENV{WAWONA_HOST_NLUA0})\n  target_sources(nlua0 PUBLIC ${NLUA0_SOURCES})\nendif()",
    ),
]:
    if anchor in nc_text:
        nvim_cmake.write_text(nc_text.replace(anchor, patch, 1))
        nc_text = nvim_cmake.read_text()
