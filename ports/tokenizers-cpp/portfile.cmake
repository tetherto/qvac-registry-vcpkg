vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO mlc-ai/tokenizers-cpp
    REF ae3d2062d4e08c04bdd9bdbcc59eed504463fcca
    SHA512 bfe313afefdb9fb2876febe81ef1e5c46a6f3a691c047df87567711b03502e490af8b1decd427483d4496aaf8b46472358dd85b01463a88b6565cc93afdc712e
    HEAD_REF tags/v0.1.1
    PATCHES
        0001-build-only-hf-tokenizer.patch
        0002-fix-rust-build.patch
)

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
)

vcpkg_cmake_install()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

file(INSTALL "${SOURCE_PATH}/LICENSE" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}" RENAME copyright) 