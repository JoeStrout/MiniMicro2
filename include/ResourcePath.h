#ifndef RESOURCE_PATH_H
#define RESOURCE_PATH_H

#include <string>

// Get the base path where resources are located
// This works across platforms and build configurations
std::string GetResourcePath();

// Get full path to a resource file
std::string GetResourceFile(const char* relativePath);

#endif // RESOURCE_PATH_H
