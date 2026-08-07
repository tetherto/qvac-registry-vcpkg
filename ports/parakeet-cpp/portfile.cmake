# parakeet-cpp: NVIDIA Parakeet ASR + Sortformer diarization in pure C++/ggml,
# from the engines/parakeet/ subfolder of tetherto/qvac-ext-lib-whisper.cpp;
# consumes the ggml-speech port.
#
# The installable artifacts live under the `qvac-parakeet` name so this port is
# co-installable with whisper-cpp, whose upstream v1.9.1+ installs its own
# parakeet library and CMake package. Consumers use
# find_package(qvac-parakeet CONFIG) + qvac::parakeet; the C++ `parakeet::`
# namespace and the include/parakeet/ directory are unchanged.
#
# Pinned at master 5e57a692, shared with the whisper-cpp / tts-cpp /
# audiogen-cpp ports so all four resolve one source archive against one
# ggml-speech. engines/parakeet is unchanged from the previous pin; the
# ggml-speech floor moves to 2026-08-07 for the Vulkan matmul src0 binding fix
# and the OpenCL im2col rewrite (qvac-ext-ggml PRs #52, #53).

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_BUILD_TYPE release)

vcpkg_from_github(
    OUT_SOURCE_PATH WHISPER_CPP_SRC
    REPO tetherto/qvac-ext-lib-whisper.cpp
    REF 5e57a69221e58a091aac07b2d19895df985ba53c
    SHA512 2cce663c5c375e07d0bdc109fe40ce13727fa0f01969537fa1b2e07c8a20429e4854fc140e40d3b146f2debcb75207952c8a5efbf67d8c21dba4e60452cf53fd
    HEAD_REF master
)

set(SOURCE_PATH "${WHISPER_CPP_SRC}/engines/parakeet")
if (NOT EXISTS "${SOURCE_PATH}/CMakeLists.txt")
    message(FATAL_ERROR
        "parakeet-cpp: ${SOURCE_PATH}/CMakeLists.txt missing; the engines/parakeet/ "
        "subfolder layout in qvac-ext-lib-whisper.cpp may have changed.")
endif()

set(GGML_METAL  OFF)
set(GGML_VULKAN OFF)
set(GGML_CUDA   OFF)
set(GGML_OPENCL OFF)
if("metal" IN_LIST FEATURES)
    set(GGML_METAL ON)
endif()
if("vulkan" IN_LIST FEATURES)
    set(GGML_VULKAN ON)
endif()
if("cuda" IN_LIST FEATURES)
    set(GGML_CUDA ON)
endif()
if("opencl" IN_LIST FEATURES)
    set(GGML_OPENCL ON)
endif()

set(PARAKEET_COREML OFF)
if("coreml" IN_LIST FEATURES)
    set(PARAKEET_COREML ON)
endif()

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    DISABLE_PARALLEL_CONFIGURE
    OPTIONS
        -DPARAKEET_BUILD_LIBRARY=ON
        -DPARAKEET_BUILD_EXECUTABLES=OFF
        -DPARAKEET_BUILD_TESTS=OFF
        -DPARAKEET_BUILD_EXAMPLES=OFF
        -DPARAKEET_INSTALL=ON
        -DPARAKEET_USE_SYSTEM_GGML=ON
        -DBUILD_SHARED_LIBS=OFF
        -DGGML_NATIVE=OFF
        -DGGML_OPENMP=OFF
        -DPARAKEET_OPENMP=OFF
        -DGGML_CCACHE=OFF
        -DPARAKEET_CCACHE=OFF
        -DGGML_METAL=${GGML_METAL}
        -DGGML_VULKAN=${GGML_VULKAN}
        -DGGML_CUDA=${GGML_CUDA}
        -DGGML_OPENCL=${GGML_OPENCL}
        -DPARAKEET_COREML=${PARAKEET_COREML}
)

vcpkg_cmake_install()

# The engine installs its package config to lib/cmake/qvac-parakeet (was
# share/parakeet-cpp) under the new namespace; the imported target is
# qvac::parakeet.
vcpkg_cmake_config_fixup(PACKAGE_NAME qvac-parakeet CONFIG_PATH lib/cmake/qvac-parakeet)

# The engine installs lib/pkgconfig/qvac-parakeet.pc carrying absolute -L/-I
# into this machine's install prefix, which would break every consumer that
# restores the package from the binary cache. vcpkg_fixup_pkgconfig() rewrites
# them by exact string match only, and the two sides can disagree on spelling
# (macOS /tmp vs /private/tmp), so normalise by meaning instead: rewrite any
# absolute -L/-I whose realpath lands inside the prefix to ${prefix}-relative.
# The shipped .pc is complete for CMake consumers and for pkg-config against a
# shared ggml; a static-ggml pkg-config link still misses the backend
# registration symbols, tracked as an engine follow-up.
get_filename_component(PARAKEET_INSTALLED_REALPATH "${CURRENT_INSTALLED_DIR}" REALPATH)

function(parakeet_relativize_pc pc_file)
    if (NOT EXISTS "${pc_file}")
        return()
    endif()
    file(READ "${pc_file}" contents)
    string(REGEX MATCHALL "-[LI][^ \t\r\n\"]+" tokens "${contents}")
    foreach (token IN LISTS tokens)
        string(SUBSTRING "${token}" 0 2 flag)
        string(SUBSTRING "${token}" 2 -1 dir)
        if (NOT IS_ABSOLUTE "${dir}")
            continue()
        endif()
        get_filename_component(dir_real "${dir}" REALPATH)
        # Only touch paths inside our own prefix; a genuinely external dep
        # (e.g. a system OpenMP runtime) must keep its absolute path.
        string(FIND "${dir_real}" "${PARAKEET_INSTALLED_REALPATH}/" hit)
        if (NOT hit EQUAL 0)
            continue()
        endif()
        string(LENGTH "${PARAKEET_INSTALLED_REALPATH}/" prefix_len)
        string(SUBSTRING "${dir_real}" ${prefix_len} -1 rel)
        string(REPLACE "${token}" "${flag}\${prefix}/${rel}" contents "${contents}")
    endforeach()
    file(WRITE "${pc_file}" "${contents}")
endfunction()

file(GLOB PARAKEET_PC_FILES
    "${CURRENT_PACKAGES_DIR}/lib/pkgconfig/*.pc"
    "${CURRENT_PACKAGES_DIR}/debug/lib/pkgconfig/*.pc")
foreach (PARAKEET_PC_FILE IN LISTS PARAKEET_PC_FILES)
    parakeet_relativize_pc("${PARAKEET_PC_FILE}")
endforeach()

vcpkg_fixup_pkgconfig()

# Guard the outcome by meaning, not by spelling: after the rewrites no -L/-I in
# the shipped .pc may still resolve into this machine's install/package/build
# trees. Cheap, and it turns a silently non-relocatable package into a build
# failure here.
file(GLOB PARAKEET_PC_FILES "${CURRENT_PACKAGES_DIR}/lib/pkgconfig/*.pc")
foreach (PARAKEET_PC_FILE IN LISTS PARAKEET_PC_FILES)
    file(READ "${PARAKEET_PC_FILE}" PARAKEET_PC_CONTENTS)
    string(REGEX MATCHALL "-[LI][^ \t\r\n\"]+" PARAKEET_PC_TOKENS "${PARAKEET_PC_CONTENTS}")
    foreach (PARAKEET_PC_TOKEN IN LISTS PARAKEET_PC_TOKENS)
        string(SUBSTRING "${PARAKEET_PC_TOKEN}" 2 -1 PARAKEET_PC_DIR)
        if (NOT IS_ABSOLUTE "${PARAKEET_PC_DIR}")
            continue()
        endif()
        get_filename_component(PARAKEET_PC_DIR_REAL "${PARAKEET_PC_DIR}" REALPATH)
        foreach (PARAKEET_TREE
                 "${PARAKEET_INSTALLED_REALPATH}" "${CURRENT_PACKAGES_DIR}" "${CURRENT_BUILDTREES_DIR}")
            get_filename_component(PARAKEET_TREE_REAL "${PARAKEET_TREE}" REALPATH)
            string(FIND "${PARAKEET_PC_DIR_REAL}" "${PARAKEET_TREE_REAL}" PARAKEET_TREE_HIT)
            if (PARAKEET_TREE_HIT EQUAL 0)
                message(FATAL_ERROR
                    "parakeet-cpp: ${PARAKEET_PC_FILE} still contains '${PARAKEET_PC_TOKEN}', which "
                    "resolves inside ${PARAKEET_TREE_REAL}. The packaged .pc would not be "
                    "relocatable and would break consumers restoring this package from the "
                    "binary cache.")
            endif()
        endforeach()
    endforeach()
endforeach()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

if (VCPKG_LIBRARY_LINKAGE MATCHES "static")
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/bin")
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/bin")
endif()

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
