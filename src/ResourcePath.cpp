#include "ResourcePath.h"
#include <cstdlib>
#include <cstring>
#include <string>
#include <sys/stat.h>
#include <unistd.h>

#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif

#ifdef _WIN32
#include <windows.h>
#endif

// Check if a file or directory exists
static bool PathExists(const char* path) {
    struct stat info;
    return stat(path, &info) == 0;
}

// Simple path joining - appends paths with a separator
static std::string JoinPath(const std::string& base, const char* relative) {
    std::string result = base;
    if (!result.empty() && result[result.length() - 1] != '/') {
        result += '/';
    }
    result += relative;
    return result;
}

// Get directory portion of a path
static std::string GetDirectory(const char* path) {
    std::string p(path);
    size_t pos = p.find_last_of("/\\");
    if (pos != std::string::npos) {
        return p.substr(0, pos);
    }
    return "";
}

std::string GetResourcePath() {
    // Try several locations in order of likelihood:

    // 1. Current working directory + resources (for IDE development)
    char cwd[1024];
    if (getcwd(cwd, sizeof(cwd))) {
        std::string cwdResources = JoinPath(cwd, "resources");
        if (PathExists(cwdResources.c_str())) {
            return cwdResources;
        }
    }

#ifdef __APPLE__
    // 2. macOS bundle resources (for distribution)
    char execPath[1024];
    uint32_t size = sizeof(execPath);
    if (_NSGetExecutablePath(execPath, &size) == 0) {
        // execPath is something like: /path/to/App.app/Contents/MacOS/executable
        // We want: /path/to/App.app/Contents/Resources/resources
        std::string exeDir = GetDirectory(execPath);           // Contents/MacOS
        std::string contentsDir = GetDirectory(exeDir.c_str()); // Contents
        std::string bundleResources = JoinPath(contentsDir, "Resources");
        bundleResources = JoinPath(bundleResources, "resources");
        if (PathExists(bundleResources.c_str())) {
            return bundleResources;
        }
    }
#endif

    // 3. Fallback: assume resources is in current directory
    return "resources";
}

std::string GetResourceFile(const char* relativePath) {
    static std::string resourceBasePath = GetResourcePath();
    return JoinPath(resourceBasePath, relativePath);
}
