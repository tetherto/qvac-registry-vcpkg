# audiogen-cpp: ACE-Step music generation in pure C++/ggml, from the
# engines/audiogen/ subfolder of qvac-ext-lib-whisper.cpp; consumes the
# ggml-speech port.
#
# Pinned at master 5e57a692, shared with the whisper-cpp / parakeet-cpp /
# tts-cpp ports so all four resolve one source archive against one ggml-speech.
# This pin (PRs #126 and #129) runs ACE-Step end to end on Adreno OpenCL and
# fixes the cond-encoder fp16 overflow and the VAE decode allocation cap. The
# ggml-speech floor moves to 2026-08-07 as a hard dependency: the Oobleck VAE
# needs the OpenCL snake and col2im_1d kernels from qvac-ext-ggml PR #52.

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_BUILD_TYPE release)

vcpkg_from_github(
    OUT_SOURCE_PATH WHISPER_CPP_SRC
    REPO tetherto/qvac-ext-lib-whisper.cpp
    REF 5e57a69221e58a091aac07b2d19895df985ba53c
    SHA512 2cce663c5c375e07d0bdc109fe40ce13727fa0f01969537fa1b2e07c8a20429e4854fc140e40d3b146f2debcb75207952c8a5efbf67d8c21dba4e60452cf53fd
    HEAD_REF master
)

set(SOURCE_PATH "${WHISPER_CPP_SRC}/engines/audiogen")
if (NOT EXISTS "${SOURCE_PATH}/CMakeLists.txt")
    message(FATAL_ERROR
        "audiogen-cpp: ${SOURCE_PATH}/CMakeLists.txt missing; the engines/audiogen/ "
        "subfolder layout in qvac-ext-lib-whisper.cpp may have changed.")
endif()

vcpkg_check_features(OUT_FEATURE_OPTIONS FEATURE_OPTIONS
    FEATURES
        metal   GGML_METAL
        vulkan  GGML_VULKAN
        cuda    GGML_CUDA
        opencl  GGML_OPENCL
)

set(PLATFORM_OPTIONS)

if(NOT VCPKG_TARGET_IS_OSX)
    list(APPEND PLATFORM_OPTIONS
        -DGGML_BLAS=OFF
        -DGGML_ACCELERATE=OFF
        -DCMAKE_DISABLE_FIND_PACKAGE_BLAS=ON
    )
endif()

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    DISABLE_PARALLEL_CONFIGURE
    OPTIONS
        -DAUDIOGEN_BUILD_LIBRARY=ON
        -DAUDIOGEN_BUILD_EXECUTABLES=OFF
        -DAUDIOGEN_BUILD_TESTS=OFF
        -DAUDIOGEN_INSTALL=ON
        -DAUDIOGEN_USE_SYSTEM_GGML=ON
        -DBUILD_SHARED_LIBS=OFF
        -DGGML_NATIVE=OFF
        -DGGML_OPENMP=OFF
        -DGGML_CCACHE=OFF
        -DAUDIOGEN_CCACHE=OFF
        ${FEATURE_OPTIONS}
        ${PLATFORM_OPTIONS}
)

vcpkg_cmake_install()

vcpkg_cmake_config_fixup(PACKAGE_NAME audiogen-cpp CONFIG_PATH share/audiogen-cpp)

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

if (VCPKG_LIBRARY_LINKAGE MATCHES "static")
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/bin")
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/bin")
endif()

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
