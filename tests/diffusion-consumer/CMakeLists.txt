cmake_minimum_required(VERSION 3.25)
project(diffusion_registry_consumer LANGUAGES CXX)

find_package(stable-diffusion-cpp CONFIG REQUIRED)
add_executable(diffusion-registry-consumer main.cpp)
target_compile_features(diffusion-registry-consumer PRIVATE cxx_std_17)
target_link_libraries(diffusion-registry-consumer PRIVATE stable-diffusion::stable-diffusion)
enable_testing()
add_test(NAME diffusion-registry-consumer COMMAND diffusion-registry-consumer)
