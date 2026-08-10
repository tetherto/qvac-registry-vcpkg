# audiogen-cpp: ACE-Step music generation in pure C++/ggml, from the
# engines/audiogen/ subfolder of qvac-ext-lib-whisper.cpp; consumes the
# ggml-speech port.
#
# Pinned at merged commit 80d5c3a2 (qvac-ext-lib-whisper.cpp PR #132). This
# aligns generation with official ACE-Step, including the Haar wavelet DCW
# correction that removes robotic artifacts and the stabilized quantized
# batched LM head. The ggml-speech floor remains 2026-08-07 because it already
# provides the required GPU kernels for the supported backends.

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_BUILD_TYPE release)

vcpkg_from_github(
    OUT_SOURCE_PATH WHISPER_CPP_SRC
    REPO tetherto/qvac-ext-lib-whisper.cpp
    REF 80d5c3a267753422d57c533441b3fb640bb7d56a
    SHA512 3e9b5f168e3b18acd7cbb17c291381e7fa16fee2bcbfce621749d121609a39d34305d563d2cdb522d0f9b07f8e08f4f77822e77bf6c60fcc0ff01bc7caaf71d3
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
