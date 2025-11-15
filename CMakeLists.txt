cmake_minimum_required(VERSION 3.15)

# Platform-specific settings (must be before project())
if(APPLE)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "10.13" CACHE STRING "Minimum OS X deployment version")
    # Disable code signing for local development
    set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "")
    set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO")
    set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO")
endif()

project(MiniMicro2 VERSION 0.1.0 LANGUAGES CXX C)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Export compile commands for IDEs
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Options
option(BUILD_SHARED_LIBS "Build shared libraries" OFF)

# Add subdirectories for dependencies
add_subdirectory(external/raylib)
add_subdirectory(external/miniscript)

# Include directories
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/external/raylib/src
    ${CMAKE_CURRENT_SOURCE_DIR}/external/miniscript/MiniScript-cpp/src
)

# Collect source files
file(GLOB_RECURSE SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/*.c
)

file(GLOB_RECURSE HEADERS
    ${CMAKE_CURRENT_SOURCE_DIR}/include/*.h
    ${CMAKE_CURRENT_SOURCE_DIR}/include/*.hpp
)

# Collect documentation and resource files for IDE visibility
file(GLOB_RECURSE DOC_FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/docs/*.md
)

file(GLOB_RECURSE RESOURCE_FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/resources/*
)

# Create executable
add_executable(${PROJECT_NAME} ${SOURCES} ${HEADERS} ${DOC_FILES} ${RESOURCE_FILES})

# Organize files in Xcode groups
source_group("Documentation" FILES ${DOC_FILES})
source_group("Resources" FILES ${RESOURCE_FILES})

# Disable app sandboxing for macOS development
if(APPLE)
    set_target_properties(${PROJECT_NAME} PROPERTIES
        XCODE_ATTRIBUTE_ENABLE_HARDENED_RUNTIME NO
        XCODE_ATTRIBUTE_ENABLE_APP_SANDBOX NO
        MACOSX_BUNDLE_BUNDLE_NAME "MiniMicro2"
        MACOSX_BUNDLE_GUI_IDENTIFIER "org.miniscript.minimicro2"
        MACOSX_BUNDLE TRUE
        XCODE_SCHEME_WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    )
endif()

# Link libraries
target_link_libraries(${PROJECT_NAME}
    raylib
    miniscript-cpp
)

# Platform-specific linking
if(WIN32)
    target_link_libraries(${PROJECT_NAME} winmm)
elseif(UNIX AND NOT APPLE)
    target_link_libraries(${PROJECT_NAME} m pthread dl)
    find_package(OpenGL REQUIRED)
    target_link_libraries(${PROJECT_NAME} ${OPENGL_LIBRARIES})
endif()

# Copy resources to build directory
if(APPLE)
    # For macOS bundles, copy to Contents/Resources
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            ${CMAKE_CURRENT_SOURCE_DIR}/resources
            $<TARGET_FILE_DIR:${PROJECT_NAME}>/../Resources/resources
        COMMENT "Copying resources to bundle"
    )
else()
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            ${CMAKE_CURRENT_SOURCE_DIR}/resources
            $<TARGET_FILE_DIR:${PROJECT_NAME}>/resources
        COMMENT "Copying resources to build directory"
    )
endif()

# Install targets
install(TARGETS ${PROJECT_NAME} DESTINATION bin)
install(DIRECTORY resources DESTINATION bin)
