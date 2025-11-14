# MiniMicro2

A cross-platform application built with Raylib and MiniScript.

## Dependencies

- [Raylib](https://github.com/raysan5/raylib) - A simple and easy-to-use library for graphics
- [MiniScript](https://github.com/JoeStrout/miniscript) - A lightweight scripting language

Dependencies are managed as git submodules.

## Building

### Prerequisites

- CMake 3.15 or higher
- A C++17 compatible compiler
- Git

### Clone the Repository

```bash
git clone --recursive <your-repo-url>
cd MiniMicro2
```

If you already cloned without `--recursive`, initialize the submodules:

```bash
git submodule update --init --recursive
```

### Build Instructions

#### macOS (Xcode)

```bash
mkdir build
cd build
cmake -G Xcode ..
open MiniMicro2.xcodeproj
```

Or build from command line:

```bash
mkdir build
cd build
cmake ..
cmake --build .
```

#### Linux / Raspberry Pi

```bash
mkdir build
cd build
cmake ..
make
```

#### Windows (Visual Studio)

```bash
mkdir build
cd build
cmake ..
cmake --build . --config Release
```

### Other Build Systems

CMake can generate project files for various IDEs and build systems:

- Visual Studio: `cmake -G "Visual Studio 17 2022" ..`
- Ninja: `cmake -G Ninja ..`
- Unix Makefiles: `cmake -G "Unix Makefiles" ..`

## Project Structure

```
MiniMicro2/
├── CMakeLists.txt        # Main build configuration
├── src/                  # Source files (.cpp, .c)
├── include/              # Header files (.h, .hpp)
└── external/             # External dependencies (submodules)
    ├── raylib/
    └── miniscript/
```

## Platform Support

- macOS
- Linux
- Windows
- Raspberry Pi
- Mobile (iOS/Android) - planned

## License

TBD
