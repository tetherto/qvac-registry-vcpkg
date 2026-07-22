# audiogen-cpp: ACE-Step music generation in pure C++/ggml.
# Sourced from the engines/audiogen/ subfolder of qvac-ext-lib-whisper.cpp;
# consumes the ggml-speech port for the custom snake / col2im_1d ops the
# ACE-Step Oobleck VAE needs.
#
# [AudioGen GGML] native ACE-Step music generation
# (qvac-ext-lib-whisper.cpp PR #98 merged, QVAC-21921): the ACE-Step
# text-to-music pipeline (Qwen3-Embedding text encoder -> ace-lm language model
# -> DiT diffusion transformer -> Oobleck VAE) behind the shared Engine API,
# alongside engines/tts and engines/parakeet. Runs on CPU and, when built with
# the matching ggml-speech GPU feature (Metal on Apple, etc.), on the GPU
# backend; the VAE decode/encode rely on the GGML_OP_SNAKE and GGML_OP_COL2IM_1D
# custom ops published by ggml-speech >= 2026-07-22.
#
# Pinned at tetherto/qvac-ext-lib-whisper.cpp@master HEAD 0f832db3 (PR #98
# merged: native ACE-Step music generation on CPU, plus the engines/ folder
# refactor that groups tts / parakeet / audiogen under engines/).

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_BUILD_TYPE release)

vcpkg_from_github(
    OUT_SOURCE_PATH WHISPER_CPP_SRC
    REPO tetherto/qvac-ext-lib-whisper.cpp
    REF 0f832db3444cbda456e7b149dbb21ef4f46fc66a
    SHA512 599106f65909356f7b067c24b12822fe7a57be046e27ef2a6861f75e117528cdf8c14ea6e836b8ba6931c97dbe8e4598351b40cda3f29c27a7a9eedbcf413c1b
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
