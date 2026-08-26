# QVAC vcpkg Registry

A [vcpkg](https://vcpkg.io/) custom registry used by QVAC projects. It provides versioned ports for inference, TTS, and supporting libraries, including some packages not available (or not at the versions we need) in the official vcpkg registry.

## What’s in this registry

- **QVAC packages**: `qvac-lib-inference-addon-cpp`, `qvac-lint-cpp`
- **Inference / ML**: `llama-cpp`, `qvac-fabric`, `speech-cpp`, `stable-diffusion-cpp`, `tokenizers-cpp`, `sentencepiece`
- **ggml flavours**: `ggml`, `ggml-speech`
- **Build / runtime deps**: `vcpkg-cmake`, `vcpkg-cmake-config`, `vcpkg-cmake-get-vars`, `abseil`, `cpuinfo`, `opencl`, `opencl-headers`, `protobuf`, `re2`, and others

Exact versions and baselines are defined in `versions/baseline.json`.

The ONNX Runtime stack — `onnxruntime`, `onnx`, and the `eigen3`, `pybind11`, `xnnpack` and `pthreadpool` ports that existed only to pin its dependency versions — was removed once its sole consumer, the `@qvac/onnx` addon, was retired from tetherto/qvac. Manifests naming those ports no longer resolve, whatever baseline they pin; all four supporting ports are available from the official vcpkg registry instead.

### The speech stack: `speech-cpp`

`speech-cpp` is an umbrella port over [qvac-fabric-speech.cpp](https://github.com/tetherto/qvac-fabric-speech.cpp) (formerly `qvac-ext-lib-whisper.cpp`): one source pin for the whole speech stack, with the engines selected as features and every engine linking the single `ggml-speech` ggml.

| Feature | Engine | `find_package` | Imported target |
|---|---|---|---|
| `whisper` | whisper.cpp transcription | `whisper` | `whisper::whisper` |
| `parakeet` | Parakeet ASR + diarization | `qvac-parakeet` | `qvac::parakeet` |
| `tts` | Chatterbox, Supertonic, CosyVoice3, Parler, Audio8, LavaSR | `tts-cpp` | `tts-cpp::tts-cpp` |
| `audiogen` | ACE-Step music generation | `audiogen-cpp` | `audiogen-cpp::audiogen-cpp` |

Backend features (`metal`, `vulkan`, `opencl`) fan out to the matching `ggml-speech` features, so a manifest entry like the one below resolves one shared `ggml-speech` with unified features:

```json
{
  "name": "speech-cpp",
  "default-features": false,
  "features": ["whisper", "parakeet", "vulkan"]
}
```

`speech-cpp` replaced the per-engine `whisper-cpp`, `parakeet-cpp`, `tts-cpp` and `audiogen-cpp` ports, which pinned the same upstream repo at four different commits. Those ports were removed once every consumer had migrated, so manifests that still name them no longer resolve — depend on the matching `speech-cpp` feature instead.

## Prerequisites

- [vcpkg](https://vcpkg.io/en/docs/getting-started.html) (manifest mode or classic)
- For **manifest mode**: a `vcpkg.json` in your project
- For **classic mode**: a vcpkg installation and use of `vcpkg install` from a vcpkg root

## Setup: use this registry in your project

1. **Use the canonical registry URL**  
   `https://github.com/tetherto/qvac-registry-vcpkg.git`

2. **Configure the registry** in your project so vcpkg can find it.

   **Manifest mode**  
   Add a `vcpkg-configuration.json` next to your project’s `vcpkg.json` (or in your vcpkg root), for example:

   ```json
   {
     "registries": [
       {
         "kind": "git",
         "repository": "https://github.com/tetherto/qvac-registry-vcpkg.git",
         "baseline": "main",
         "packages": [
           "qvac-lib-inference-addon-cpp",
           "qvac-lint-cpp",
           "llama-cpp",
           "speech-cpp",
           "ggml-speech"
         ]
       }
     ]
   }
   ```

   To allow **all** packages from this registry (and still use the official registry for everything else), set:

   ```json
   "packages": ["*"]
   ```

   **Classic mode**  
   Create or edit `vcpkg-configuration.json` in your vcpkg installation root (e.g. `vcpkg_installed` or your clone of vcpkg) with the same `registries` block as above.

3. **Declare dependencies** in your project’s `vcpkg.json` (manifest mode) or install them via the CLI (classic mode), e.g.:

   ```json
   "dependencies": [
     "qvac-lib-inference-addon-cpp",
     "llama-cpp"
   ]
   ```

   Then run your usual vcpkg install/build (e.g. CMake with vcpkg toolchain, or `vcpkg install`).

## Summary

| Step | Action |
|------|--------|
| 1 | Ensure vcpkg is installed and your project uses it (manifest or classic). |
| 2 | Add this registry in `vcpkg-configuration.json` with `kind: "git"`, `repository`: `https://github.com/tetherto/qvac-registry-vcpkg.git`, and a `baseline` (e.g. `main` or a commit/tag). |
| 3 | List needed packages in `"packages"` or use `["*"]` to allow all. |
| 4 | Add the ports you need in your `vcpkg.json` or install them via the vcpkg CLI. |
