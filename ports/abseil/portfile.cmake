# Abseil for QVAC. Newer than upstream microsoft/vcpkg (20260526.0 vs 20260107.1)
# because Google FuzzTest needs absl/random/mocking_access.h, which only exists
# from 20260526.0 on. See tetherto/qvac docs/architecture/ADDON-FUZZING.md ->
# "Dependency sourcing".
#
# This replaces the previous onnxruntime-pinned Abseil (20240722.0, declared as
# version-string "onnxruntime"), which older baselines keep resolving from git
# history. The onnxruntime / sentencepiece / marian-dev ports have NOT been
# validated against this version; note that onnxruntime constrains abseil with
# `version>= "onnxruntime#1"`, a non-comparable scheme, so resolving it together
# with this dated version is an error rather than a silent upgrade.
#
# Kept close to upstream's portfile so re-syncing is a small diff. Deliberate
# differences, both about ABI compatibility with QVAC consumers:
#   * C++20 and an `asan` feature (see the comments at each below).
#   * Only the #2091 patch. Upstream's 003-force-cxx-17.patch only relaxes
#     Abseil's "compiler defaults to < C++17" FATAL_ERROR, which the explicit
#     C++20 below makes unreachable; its mingw / gcc13 patches target toolchains
#     QVAC does not build with (clang).

if(NOT VCPKG_TARGET_IS_WINDOWS)
    vcpkg_check_linkage(ONLY_STATIC_LIBRARY)
endif()

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO abseil/abseil-cpp
    REF "${VERSION}"
    SHA512 fe85ebdd451b126117df1c3a312a1d5b29fc3557d07bb248854639b2a0180e91003fd2331a0d938f4ffeae8966f1df67a488fa3bdab072e840bbfdc6e8a4f01b
    HEAD_REF master
    PATCHES
        # abseil#2091: absl_strings links to itself, fatal at generate time.
        # Fixed upstream on 2026-07-01, after the 20260526.0 tag; drop this once
        # a release carries the fix.
        fix-absl-strings-self-link.patch
)

set(ABSL_STATIC_RUNTIME_OPTION "")
if(VCPKG_TARGET_IS_WINDOWS AND VCPKG_CRT_LINKAGE STREQUAL "static")
    set(ABSL_STATIC_RUNTIME_OPTION "-DABSL_MSVC_STATIC_RUNTIME=ON")
endif()

# Abseil's swisstable ABI depends on whether it was compiled under a sanitizer:
# with ASan, raw_hash_set stores a generation counter in the backing array and
# CommonFields carries a pointer to it (ABSL_SWISSTABLE_ENABLE_GENERATIONS in
# absl/container/internal/raw_hash_set.h). The container is a template, so an
# ASan-instrumented consumer compiles the generations-enabled layout inline while
# the out-of-line resize/insert helpers in a non-instrumented libabsl allocate
# the layout without it — the header code then reads a generation that isn't
# there and dies with SIGSEGV on the first iteration. So an ASan consumer needs
# an ASan Abseil, which is what this feature is for. It is a separate feature
# rather than the default because it makes the installed libraries unlinkable
# without -fsanitize=address, and it earns its own binary-cache entry.
if("asan" IN_LIST FEATURES)
    # vcpkg_cmake_configure forwards these into CMAKE_{C,CXX}_FLAGS via the
    # toolchain, and requires the C and CXX variables to be set in lockstep.
    string(APPEND VCPKG_CXX_FLAGS " -fsanitize=address -fno-omit-frame-pointer")
    string(APPEND VCPKG_C_FLAGS " -fsanitize=address -fno-omit-frame-pointer")
endif()

# Built at C++20, not the compiler default, because Abseil's ABI depends on the
# standard: absl::SourceLocation aliases std::source_location under C++20, so a
# C++17 Abseil emits different MakeErrorImpl(...) symbols than a C++20 consumer
# references — an undefined-symbol link error. Every QVAC addon TU is C++20
# (std::span), and ABSL_PROPAGATE_CXX_STD=ON puts cxx_std_20 on the installed
# absl:: targets so dependents (re2, FuzzTest) inherit the same standard.
vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DCMAKE_CXX_STANDARD=20
        -DABSL_PROPAGATE_CXX_STD=ON
        -DABSL_BUILD_TESTING=OFF
        -DABSL_BUILD_TEST_HELPERS=OFF
        ${ABSL_STATIC_RUNTIME_OPTION}
)

vcpkg_cmake_install()
vcpkg_cmake_config_fixup(PACKAGE_NAME absl CONFIG_PATH lib/cmake/absl)

if(VCPKG_TARGET_IS_IOS OR VCPKG_TARGET_IS_OSX)
    file(APPEND "${CURRENT_PACKAGES_DIR}/lib/pkgconfig/absl_time.pc" "Libs.private: -framework CoreFoundation\n")
    if(NOT VCPKG_BUILD_TYPE)
        file(APPEND "${CURRENT_PACKAGES_DIR}/debug/lib/pkgconfig/absl_time.pc" "Libs.private: -framework CoreFoundation\n")
    endif()
endif()
vcpkg_fixup_pkgconfig()

vcpkg_copy_pdbs()
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share"
                    "${CURRENT_PACKAGES_DIR}/debug/include"
                    "${CURRENT_PACKAGES_DIR}/include/absl/copts"
                    "${CURRENT_PACKAGES_DIR}/include/absl/strings/testdata"
                    "${CURRENT_PACKAGES_DIR}/include/absl/time/internal/cctz/testdata"
)

if(VCPKG_TARGET_IS_WINDOWS AND VCPKG_LIBRARY_LINKAGE STREQUAL "dynamic")
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/include/absl/base/config.h" "defined(ABSL_CONSUME_DLL)" "1")
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/include/absl/base/internal/thread_identity.h" "defined(ABSL_CONSUME_DLL)" "1")
endif()

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
