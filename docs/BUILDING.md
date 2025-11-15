## Building Mini Micro 2

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
