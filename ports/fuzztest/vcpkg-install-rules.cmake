# Install rules for a project that has none.
#
# FuzzTest ships no install() call anywhere (upstream vcpkg request #36901 was
# closed as not-planned for exactly that reason), so the port supplies them. The
# portfile appends an include() of this file to the end of CMakeLists.txt rather
# than patching it, so there is no patch context to rot across FuzzTest bumps.
#
# It works generically — walk every target the project defined and export it —
# rather than naming ~30 libraries, so a bump that adds or renames a library
# needs no edit here.

include(GNUInstallDirs)

# FuzzTest's includes are rooted at its source dir: "fuzztest/fuzztest.h" and
# also "common/logging.h" (internal headers such as internal/any.h and
# domains/lazy.h reach into common/). Installing a top-level common/ into the
# shared include root would collide with any other port, so both trees go under
# one private root that the exported targets carry as their include directory.
set(_fuzztest_includedir "${CMAKE_INSTALL_INCLUDEDIR}/fuzztest-root")

function(_fuzztest_collect_targets dir out_var)
  get_property(_targets DIRECTORY "${dir}" PROPERTY BUILDSYSTEM_TARGETS)
  get_property(_subdirs DIRECTORY "${dir}" PROPERTY SUBDIRECTORIES)
  foreach(_subdir IN LISTS _subdirs)
    _fuzztest_collect_targets("${_subdir}" _sub)
    list(APPEND _targets ${_sub})
  endforeach()
  set(${out_var} "${_targets}" PARENT_SCOPE)
endfunction()

_fuzztest_collect_targets("${CMAKE_CURRENT_SOURCE_DIR}" _fuzztest_all_targets)

set(_fuzztest_export_targets "")
foreach(_target IN LISTS _fuzztest_all_targets)
  get_target_property(_type ${_target} TYPE)
  if(_type STREQUAL "UTILITY" OR _type STREQUAL "EXECUTABLE")
    continue()
  endif()

  # Targets are named fuzztest_<x> and aliased fuzztest::<x>. Exporting under
  # the raw name would hand consumers fuzztest::fuzztest_<x>, so strip the
  # prefix to keep the documented spelling (fuzztest::fuzztest_gtest_main).
  # Exactly one prefix: string(REGEX REPLACE) is global, and would turn
  # fuzztest_fuzztest_gtest_main into gtest_main rather than the
  # fuzztest::fuzztest_gtest_main that link_fuzztest() asks for.
  set(_export_name "${_target}")
  if(_export_name MATCHES "^fuzztest_(.+)$")
    set(_export_name "${CMAKE_MATCH_1}")
  endif()
  set_target_properties(${_target} PROPERTIES EXPORT_NAME "${_export_name}")

  # FuzzTest hard-sets CMAKE_CXX_STANDARD 17 in its own CMakeLists, which beats
  # anything passed on the configure line. QVAC addon TUs are C++20 and
  # instantiate FuzzTest templates over their own types, and the vcpkg Abseil is
  # C++20 for its own ABI reasons, so lift the subtree the same way the addon
  # template does for the FetchContent build.
  if(NOT _type STREQUAL "INTERFACE_LIBRARY")
    set_target_properties(${_target} PROPERTIES
      CXX_STANDARD 20 CXX_STANDARD_REQUIRED ON)
  endif()

  # Most targets already wrap their include dirs in $<BUILD_INTERFACE:>, which
  # is what makes exporting this project viable at all — but json_grammar and
  # generated_antlr_parser use bare paths, and install(EXPORT) refuses a target
  # whose interface leaks a build- or source-tree path. Wrap whatever is bare.
  get_target_property(_includes ${_target} INTERFACE_INCLUDE_DIRECTORIES)
  if(_includes)
    set(_wrapped "")
    foreach(_dir IN LISTS _includes)
      if(_dir MATCHES "^\\$<")
        list(APPEND _wrapped "${_dir}")
      else()
        list(APPEND _wrapped "$<BUILD_INTERFACE:${_dir}>")
      endif()
    endforeach()
    set_target_properties(${_target} PROPERTIES
      INTERFACE_INCLUDE_DIRECTORIES "${_wrapped}")
  endif()

  target_include_directories(${_target}
    INTERFACE "$<INSTALL_INTERFACE:${_fuzztest_includedir}>")

  list(APPEND _fuzztest_export_targets ${_target})
endforeach()

install(TARGETS ${_fuzztest_export_targets}
        EXPORT fuzztestTargets
        ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}"
        LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}"
        INCLUDES DESTINATION "${_fuzztest_includedir}")

install(EXPORT fuzztestTargets
        NAMESPACE fuzztest::
        DESTINATION "${CMAKE_INSTALL_DATAROOTDIR}/fuzztest")

foreach(_tree fuzztest common)
  install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/${_tree}"
          DESTINATION "${_fuzztest_includedir}"
          FILES_MATCHING PATTERN "*.h")
endforeach()

# link_fuzztest() / link_fuzztest_core(), which consumers call.
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/cmake/AddFuzzTest.cmake"
        DESTINATION "${CMAKE_INSTALL_DATAROOTDIR}/fuzztest")
