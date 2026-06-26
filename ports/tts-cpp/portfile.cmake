# tts-cpp: Resemble Chatterbox + Supertonic TTS in pure C++/ggml.
# Sourced from the tts-cpp/ subfolder of qvac-ext-lib-whisper.cpp;
# consumes the ggml-speech port.
#
# QVAC-19557 [TTS GGML] S3TokenizerV2 host-mirror elimination
# (qvac-ext-lib-whisper.cpp PR #65): the voice-conditioning bake loaded the
# S3TokenizerV2 encoder weights (~458 MB F32) into a host std::vector mirror AND
# the backend (Metal) weight buffer at once (~900 MB dual-resident), the
# dominant contributor to the chatterbox first-synth peak that jetsam-killed the
# iOS SDK e2e.  build_encoder_ctx now streams each encoder tensor straight from
# the GGUF into its backend tensor (8 MiB chunks, no host mirror); weights are
# bit-identical.  On-device the chatterbox first-test peak drops 3184 -> 2772 MB
# (under the ~3 GB budget); warm tests unchanged.
#
# Pinned at tetherto/qvac-ext-lib-whisper.cpp@master HEAD 586268bf (PR #67
# merged: QVAC-20557 run Chatterbox correctly on ARM Mali Vulkan via an
# is_arm_mali-gated unfused CFM attention -- zero change off ARM Mali, CPU
# output byte-identical).  Layered on the 46921668 pin (PR #65 merged,
# QVAC-19557 S3TokenizerV2 host-mirror elimination, described above), the
# 1cc2d383 pin (QVAC-21118 PR #62: chunk-
# streaming CFM-step floor for the Multilingual standard 10-step CFM) and the
# a679c7e7 pin (PR #43 merged):
# QVAC-19557 chatterbox iOS-memory work — streamed GGUF tensor loads (no
# full-file host staging), selectable chatterbox KV-cache dtype
# (EngineOptions::kv_cache_type = f32|f16|q8_0) on a token-major slab with a
# load-time capability probe + F32 fallback and a Vulkan q8_0->f32 guard.
#
# Layered on the previous b95ad447 pin (QVAC-19305 Supertonic v3 PR #42 base),
# which brought the two TTS-relevant master merges:
#   - QVAC-20616 [TTS GGML] end-of-speech robustness (PR #53): alignment-based
#     EOS stop (ports the AlignmentStreamAnalyzer cross-attention signal via an
#     in-graph attention probe) plus a heuristic stop controller (EOS
#     confidence, n-gram repetition, text-length budget) and per-language
#     calibration, so the Chatterbox multilingual model stops at end-of-
#     utterance instead of rambling for ~20s of random tokens past the text.
#   - QVAC-20557 Supertonic Android GPU (PR #54): Adreno OpenCL + Xclipse/Mali
#     Vulkan. This also reroutes Supertonic's direct CPU-backend calls that are
#     unlinkable under GGML_BACKEND_DL=ON --
#     ggml_get_type_traits_cpu()->from_float -> ggml_quantize_chunk()
#     (ggml-base, always linked) and ggml_backend_is_cpu() ->
#     tts_cpp::detail::backend_is_cpu() (registry shim) -- so the tts-ggml
#     addon dlopen's cleanly on Android. It is the upstream successor to the
#     f7d4d6c fix that the tts-ggml package-local overlay was carrying; with
#     this pin published, that overlay can be dropped.

set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_BUILD_TYPE release)

vcpkg_from_github(
    OUT_SOURCE_PATH WHISPER_CPP_SRC
    REPO tetherto/qvac-ext-lib-whisper.cpp
    REF 586268bfd8863b1b27e2e21305238d397921b747
    SHA512 3922e709d034544e8e4c334c121a64f46ff4ee039997f6bb4cc9be4069cb4811e6eafe9b3ee991b1ba94b8b0d376c1d2990d48c7ab7ef7085650b64445f9e732
    HEAD_REF master
)

set(SOURCE_PATH "${WHISPER_CPP_SRC}/tts-cpp")
if (NOT EXISTS "${SOURCE_PATH}/CMakeLists.txt")
    message(FATAL_ERROR
        "tts-cpp: ${SOURCE_PATH}/CMakeLists.txt missing; the tts-cpp/ "
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
        -DTTS_CPP_BUILD_LIBRARY=ON
        -DTTS_CPP_BUILD_SHARED=OFF
        -DTTS_CPP_BUILD_EXECUTABLES=OFF
        -DTTS_CPP_BUILD_TESTS=OFF
        -DTTS_CPP_INSTALL=ON
        -DTTS_CPP_USE_SYSTEM_GGML=ON
        -DBUILD_SHARED_LIBS=OFF
        -DGGML_NATIVE=OFF
        -DGGML_OPENMP=OFF
        -DTTS_CPP_OPENMP=OFF
        -DGGML_CCACHE=OFF
        -DTTS_CPP_CCACHE=OFF
        ${FEATURE_OPTIONS}
        ${PLATFORM_OPTIONS}
)

vcpkg_cmake_install()

vcpkg_cmake_config_fixup(PACKAGE_NAME tts-cpp CONFIG_PATH share/tts-cpp)

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

if (VCPKG_LIBRARY_LINKAGE MATCHES "static")
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/bin")
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/bin")
endif()

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
