# MiniMicro2

A complete rewrite of [Mini Micro](https://miniscript.org/MiniMicro/), using C++ and Raylib rather than Unity.  This will be **Mini Micro 2**.

## Dependencies

- [Raylib](https://github.com/raysan5/raylib) - A simple and easy-to-use library for graphics
- [MiniScript](https://github.com/JoeStrout/miniscript) - A lightweight scripting language

Dependencies are managed as git submodules.

See [BUILDING.md](docs/BUILDING.md) for notes on building this project.

## Development Plan

I intend to keep this project mostly on the back burner, just occasionally pushing it forward, until MiniScript 2.0 is complete.  Then we will move this project up to the front and complete it.

## Platform Support

One reason for moving from Unity to Raylib is to make it possible to run on more platforms -- including Raspberry Pi.  Also with 2.0, mobile platforms (Android and iOS) are going to be a high priority, particularly for tablets (I'm not sure how practical it is to really use Mini Micro on a phone, though we'll support if if we can).  Target platforms:

- macOS
- Linux
- Windows
- Raspberry Pi
- Mobile (iOS/Android)

## License

TBD
