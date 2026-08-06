# RE2 for QVAC. Same source and version as upstream microsoft/vcpkg's re2
# (2025-11-05, the tag Google FuzzTest pins in cmake/BuildDependencies.cmake),
# with two deliberate differences, both for FuzzTest's benefit. See
# tetherto/qvac docs/architecture/ADDON-FUZZING.md -> "Dependency sourcing".
#
#   * It installs the internal headers FuzzTest includes (see below). Upstream
#     installs four public headers, which is why FuzzTest needs RE2 as a source
#     tree and not as an installed package.
#   * An `asan` feature, mirroring the `abseil` port's, for ASan-instrumented
#     consumers.
#
# Otherwise kept close to upstream's portfile so re-syncing is a small diff.

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO google/re2
    REF 927f5d53caf8111721e734cf24724686bb745f55
    SHA512 35103a46a6350084f2d09ccfcf4322dac7364c61fbdad8bfcbd41b39990f83a260d2a8cd5ca019a3f24b71faf1588c7dabf07c3dddae5268bcc5b9502b87658a
    HEAD_REF master
)

# RE2 uses absl containers internally (dfa.cc, re2.cc, regexp.cc, compile.cc,
# onepass.cc, prefilter_tree.h), whose layout changes under a sanitizer — the
# same swisstable generations ABI split the `abseil` port's asan feature exists
# for. A non-instrumented RE2 on top of an ASan Abseil is the mismatched half of
# that pair, so ASan consumers take this feature and get abseil[asan] with it.
if("asan" IN_LIST FEATURES)
    # vcpkg_cmake_configure forwards these into CMAKE_{C,CXX}_FLAGS via the
    # toolchain, and requires the C and CXX variables to be set in lockstep.
    string(APPEND VCPKG_CXX_FLAGS " -fsanitize=address -fno-omit-frame-pointer")
    string(APPEND VCPKG_C_FLAGS " -fsanitize=address -fno-omit-frame-pointer")
endif()

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DRE2_TEST=OFF
        -DRE2_BENCHMARK=OFF
        -DRE2_BUILD_TESTING=OFF
)

vcpkg_cmake_install()
vcpkg_copy_pdbs()
vcpkg_cmake_config_fixup(CONFIG_PATH "lib/cmake/${PORT}")
vcpkg_fixup_pkgconfig()

# FuzzTest's regexp_dfa.cc compiles regexps down to a DFA through RE2's parser
# and program representation, which are internals: it includes "re2/prog.h" and
# "re2/regexp.h", neither of which RE2 lists in RE2_HEADERS (only filtered_re2.h,
# re2.h, set.h and stringpiece.h are installed). This is the whole include
# closure — the three below add nothing beyond each other, and utf.h adds
# nothing at all.
#
# These are private headers with no stability promise, so this port's version
# and FuzzTest's re2 pin have to move together.
foreach(header IN ITEMS prog.h regexp.h pod_array.h sparse_array.h sparse_set.h)
    file(INSTALL "${SOURCE_PATH}/re2/${header}"
         DESTINATION "${CURRENT_PACKAGES_DIR}/include/re2")
endforeach()

# regexp.h includes "util/utf.h". A quoted include is searched relative to the
# including file first, so installing it beside regexp.h resolves it without a
# generic `util/` directory in the shared include root, where it would be a
# collision risk against every other port.
file(INSTALL "${SOURCE_PATH}/util/utf.h"
     DESTINATION "${CURRENT_PACKAGES_DIR}/include/re2/util")

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
