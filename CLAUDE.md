# Notes for Claude

## Project Context
This is MiniMicro2 - a C++/Raylib port of Mini Micro (originally Unity/C#). The user (Joe Strout) is the original author of Mini Micro and MiniScript. He's porting it to be more cross-platform and performant.

**Original source for reference:** `/Users/jstrout/Documents/svnrepo/stroutandsons/MiniScript/MiniMicro/`

## Important Technical Details

### Build System
- **CMake generates Xcode projects** - always regenerate after code changes: `cmake -G Xcode ..`
- Working directory: `/Users/jstrout/Documents/svnrepo/MiniMicro2/build`
- User works in Xcode, not command line builds
- Bundle identifier: `org.miniscript.minimicro2`

### Platform Constraints
- **macOS 10.13 minimum** - NO std::filesystem (requires 10.15)
- Use POSIX APIs instead (stat, getcwd, etc.)
- All file paths must be absolute in tools

### Display System Specifics
- **Bottom-up coordinates** for text (row 0 at bottom) - Mini Micro convention
- **68x26 character grid** for TextDisplay
- **Character spacing**: 14px horizontal, 24px vertical (characters overlap slightly)
- **Display offset**: 32px X, 34px Y from window edge
- **Layer ordering**: 7→0 rendered (0 is on top)
- **ScreenFont uses custom shader** - foreground/background separation based on texture alpha

### Input Handling
- **Keyboard layout aware** - use `charToKeyCode` mapping (via `GetKeyName`)
- User uses Dvorak layout - physical key codes don't work for Ctrl+key
- Must call `console.InitKeyboardMapping()` after creation
- `GetCharPressed()` returns 0 when modifiers held - handle Ctrl+key separately

### Resources
- **Font atlas**: `resources/images/ScreenFont.png` (16x16 grid)
- **Shaders**: `resources/shaders/screenfont.vs/fs` (must load at startup)
- **ResourcePath system** handles dev vs. bundle paths automatically
- Fonts/images/sounds all use `GetResourceFile()` helper

### STL Usage Policy
See `docs/CPP_STL.md` for details. Quick reference:
- ✅ Use: std::string, std::vector, std::unordered_map, std::function
- ❌ Avoid: std::regex, iostreams, complex smart pointers
- 🔀 Boundary: Use MiniScript types (SimpleString, etc.) at MiniScript interface

### Code Style Observations
- User prefers concise code
- Tabs for indentation (auto-formatted)
- K&R-ish brace style
- Minimal comments - code should be clear
- Don't add emojis unless requested

## Key Gotchas

1. **Shader loading** - Must load ScreenFont shader before creating TextDisplay
2. **Cell background transparency** - Default backColor is BLANK (transparent), not BLACK
3. **Row coordinate math** - `y = offsetY + (rows - 1 - row) * rowSpacing` for bottom-up
4. **Resource bundling** - Files copied to `Contents/Resources/resources` in bundle
5. **Working directory** - Xcode scheme set to project root via `CMAKE_SOURCE_DIR`

## Architecture Overview
See `docs/ARCHITECTURE.md` for full details.

**Quick hierarchy:**
```
main.cpp
  └─ Machine (owns 8 Display layers)
       └─ Display (base class)
            ├─ SolidColorDisplay
            └─ TextDisplay (uses ScreenFont)
  └─ Console (manages TextDisplay input)
```

## Current Status
- ✅ Basic display system working
- ✅ TextDisplay with custom font rendering
- ✅ Console with full line editing
- ✅ Keyboard layout support
- ⏳ MiniScript integration (not started)
- ⏳ Other display types (Pixel, Sprite, Tile)

## Next Steps (Likely)
- Integrate MiniScript interpreter
- Add remaining display types
- Handle file I/O for MiniScript
- Implement sprite/tile graphics
- Add sound/music APIs

## Useful Commands
```bash
# Regenerate Xcode project (from build dir)
cmake -G Xcode ..

# Find resource files
ls ../resources/

# Check font texture dimensions
file ../resources/images/ScreenFont.png
```

## Reference Files to Check
- Original Console.cs: `/Users/jstrout/Documents/svnrepo/stroutandsons/MiniScript/MiniMicro/Assets/Scripts/Console.cs`
- Original TextDisplay.cs: Same directory
- Original ScreenFont.cs: Same directory
- When implementing new features, check Unity version first for guidance
