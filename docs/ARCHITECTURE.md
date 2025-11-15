# MiniMicro2 Architecture

## Overview
MiniMicro2 is a C++/Raylib port of Mini Micro, a retro-style virtual computer. The architecture is designed to be simple, modular, and cross-platform.

## Core Components

### Machine (`Machine.h/cpp`)
- Central controller managing 8 display layers (0-7)
- Calls `Update()` and `Render()` on each display
- Layer 0 is on top (rendered last), layer 7 on bottom (rendered first)
- Owns all display instances

### Display System (`Display.h`)
Base class for all display layers:
- `Display` - Abstract base class
- `SolidColorDisplay` - Fills screen with solid color
- `TextDisplay` - Character grid with cursor and text rendering
- Future: `PixelDisplay`, `SpriteDisplay`, `TileDisplay`

### TextDisplay (`TextDisplay.h/cpp`)
- 68x26 character grid (default)
- Bottom-up coordinate system (row 0 at bottom)
- Character spacing: 14px horizontal, 24px vertical
- Display offset: 32px X, 34px Y from window edge
- Supports cursor, colors, inverse mode, scrolling
- Uses `ScreenFont` for rendering

### ScreenFont (`ScreenFont.h/cpp`)
- Renders characters from 16x16 font atlas
- Custom shader separates foreground/background colors
- Maps special Unicode characters (arrows, symbols, etc.)
- Texture brightness determines character vs. background

### Console (`Console.h/cpp`)
- Manages text input with full editing capabilities
- Command history (up/down arrows)
- Line editing (backspace, delete, cursor movement)
- Control key support (Ctrl+A/E/K/U/C)
- Keyboard layout aware (uses `GetKeyName` mapping)
- Autocomplete support with visual suggestions
- Callbacks for input completion and changes

### Resource Management (`ResourcePath.h/cpp`)
- Cross-platform resource loading
- Automatically finds resources in:
  - Current working directory (development)
  - macOS bundle (distribution)
  - Fallback paths
- Uses POSIX APIs (compatible with macOS 10.13+)

## Main Loop
```cpp
while (!WindowShouldClose()) {
    machine.Update();      // Update all displays
    console.Update();      // Handle input

    BeginDrawing();
    machine.Render();      // Render all displays
    drawBezel();           // Draw UI chrome
    EndDrawing();
}
```

## Design Decisions

### STL Usage
See [CPP_STL.md](CPP_STL.md) for detailed policy. Summary:
- Use STL in MiniMicro-specific code (std::string, std::vector, etc.)
- Use MiniScript types at MiniScript boundary (SimpleString, etc.)
- Avoid heavyweight STL features (regex, iostreams, complex smart pointers)

### Coordinate Systems
- **Text displays**: Bottom-up (row 0 at bottom, Mini Micro convention)
- **Screen space**: Top-down (standard Raylib, pixel coordinates)

### Platform Support
- macOS 10.13+ (uses POSIX, no std::filesystem)
- Cross-platform code preferred
- Platform-specific code in `#ifdef` blocks when needed

## External Dependencies
- **Raylib** - Graphics, input, audio
- **MiniScript** - Scripting engine (not yet integrated)
- Custom shaders (GLSL 330) for text rendering
