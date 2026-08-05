# audiogen-cpp: ACE-Step music generation in pure C++/ggml, from the
# engines/audiogen/ subfolder of qvac-ext-lib-whisper.cpp. Consumes ggml-speech
# for the custom snake / col2im_1d ops the Oobleck VAE needs.
#
# The REF is the shared qvac-ext-lib-whisper.cpp master pin used by every -cpp
# port in this registry. This pin (PR #122) runs the ACE-Step LM and the FSQ
# detokenizer on Metal instead of pinning them to the CPU, so on Apple the whole
# pipeline is on the GPU. It pairs with the ggml-speech 2026-08-04 floor below:
# moving the detokenizer onto Metal is what first makes ggml_cast(Q4_K -> F32)
# reachable there, and Metal had no k-quant CPY kernel until ggml PR #51, so
# this REF against an older ggml-speech aborts on the default turbo-q4 variant.

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_BUILD_TYPE release)

vcpkg_from_github(
    OUT_SOURCE_PATH WHISPER_CPP_SRC
    REPO tetherto/qvac-ext-lib-whisper.cpp
    REF b965cba039f105df055f563ee3654925bfbb428f
    SHA512 f2df5e82d02a142304db020c5581a9fd24cdffabb26688f81e852b3d2a5ca16e68814097836d5bda078851096fac52b2b98ce3654a01b90dda3c7be3ff25c90c
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
