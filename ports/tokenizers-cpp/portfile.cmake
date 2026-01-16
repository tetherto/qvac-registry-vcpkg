vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO mlc-ai/tokenizers-cpp
    REF ae3d2062d4e08c04bdd9bdbcc59eed504463fcca
    SHA512 6f693f760c48575a68c6508ecade13a005f76575695ae348e8490b9e232c54e3240449d610ac60a8f9e90ed694bbc072c1abbcd671470a1d6701bb3c6b6798ab
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