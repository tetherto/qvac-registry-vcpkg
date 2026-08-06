# Google FuzzTest for QVAC.
#
# FuzzTest ships no install() rules — upstream vcpkg request microsoft/vcpkg#36901
# was closed as not-planned on exactly those grounds — so this port supplies
# them. Everything it adds is injected without a patch, so a FuzzTest bump has
# no patch context to reconcile:
#
#   * vcpkg-install-rules.cmake is copied into the source tree and included from
#     the end of CMakeLists.txt by a file(APPEND). It exports whatever targets
#     the project defined rather than naming them, so added or renamed libraries
#     need no edit here.
#   * vcpkg-deps.cmake goes in through CMAKE_PROJECT_INCLUDE, which CMake runs at
#     the end of project() — before FuzzTest's cmake/BuildDependencies.cmake — so
#     Abseil, RE2, GoogleTest and ANTLR4 resolve to the vcpkg packages instead of
#     being cloned and rebuilt inside the port.
#
# See tetherto/qvac docs/architecture/ADDON-FUZZING.md -> "Dependency sourcing".

vcpkg_check_linkage(ONLY_STATIC_LIBRARY)

# Fuzzing is a release-shaped activity and no consumer links a debug FuzzTest,
# so building both halves would double the build for nothing.
set(VCPKG_BUILD_TYPE release)

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO google/fuzztest
    # Release 2026-06-29. Must move in step with the `re2` port: FuzzTest's
    # regexp domains include RE2's private headers, which carry no stability
    # promise, and that port is pinned to the RE2 tag this release expects.
    REF 704efb341c23011cab2a750efcdd16ad04882c80
    SHA512 642258748bf6a3e290e97f3da19ecff4053737208d657487fe9b41d73aa2865ae107673ec3c83ae322cf367b225e0be7b6a25729f800f77d39a9c5f967d243f0
    HEAD_REF main
)

file(COPY "${CMAKE_CURRENT_LIST_DIR}/vcpkg-install-rules.cmake"
     DESTINATION "${SOURCE_PATH}")
file(APPEND "${SOURCE_PATH}/CMakeLists.txt"
     "\ninclude(\"\${CMAKE_CURRENT_SOURCE_DIR}/vcpkg-install-rules.cmake\")\n")

if("asan" IN_LIST FEATURES)
    # vcpkg_cmake_configure forwards these into CMAKE_{C,CXX}_FLAGS through the
    # toolchain, and wants the C and CXX variables set in lockstep.
    string(APPEND VCPKG_CXX_FLAGS " -fsanitize=address -fno-omit-frame-pointer")
    string(APPEND VCPKG_C_FLAGS " -fsanitize=address -fno-omit-frame-pointer")
endif()

# Deliberately NOT built with FUZZTEST_FUZZING_MODE=ON, even though consumers
# run `--fuzz=`. That option calls fuzztest_setup_fuzzing_flags(), which puts
# ASan *and* -fsanitize-coverage on FuzzTest's whole scope. Coverage-guided
# fuzzing only needs the code under test instrumented — the consumer's own fuzz
# target — and instrumenting FuzzTest's libraries as well just feeds the fuzzer
# edges from its own machinery. Validated against tetherto/qvac's
# classification-ggml preprocess-fuzz target: identical total-edge count to the
# FetchContent build, no runtime complaint about fuzzing mode. The visible
# difference is that FuzzTest's internal assertions stay compiled out (this
# build keeps NDEBUG), which is the same posture its unit-test mode uses.
vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        "-DCMAKE_PROJECT_INCLUDE=${CMAKE_CURRENT_LIST_DIR}/vcpkg-deps.cmake"
        -DFUZZTEST_BUILD_TESTING=OFF
        -DFUZZTEST_BUILD_FLATBUFFERS=OFF
        -DFUZZTEST_FUZZING_MODE=OFF
)

# FuzzTest builds a codegen tool (grammar_domain_code_generator) and RUNS it
# during the build to generate its grammar domains. Under the asan feature that
# tool is instrumented while the vcpkg ANTLR4 it links is not, and ASan's
# container-overflow check fires on std::vector state crossing that boundary —
# a false positive, but a fatal one, because it happens at build time. It is the
# same instrumented/uninstrumented mixing the fuzz binaries already tolerate at
# runtime, so the one check is disabled rather than ASan as a whole.
if("asan" IN_LIST FEATURES)
    set(ENV{ASAN_OPTIONS} "detect_container_overflow=0")
endif()

vcpkg_cmake_install()

configure_file("${CMAKE_CURRENT_LIST_DIR}/fuzztest-config.cmake.in"
               "${CURRENT_PACKAGES_DIR}/share/fuzztest/fuzztest-config.cmake"
               COPYONLY)

# fuzztest/grammars holds .g4 sources only, so the header install leaves an
# empty directory behind and vcpkg's post-build check rejects those.
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/include/fuzztest-root/fuzztest/grammars")

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
