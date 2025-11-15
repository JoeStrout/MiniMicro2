# C++ STL Usage Policy

## Guiding Principles

1. **Keep code simple and clean**
2. **Minimize build size and maintain performance** (including on lighter platforms like Raspberry Pi)

## Approach: Boundary-Based Separation

### At MiniScript Interface Boundaries
Use MiniScript's types when communicating with the MiniScript VM:
- `SimpleString`
- `SimpleVector`
- `SimpleDictionary`

This avoids conversion overhead at the critical MiniScript boundary.

### In MiniMicro-Specific C++ Code
Use selective STL types:
- `std::string` - for internal string manipulation
- `std::vector<T>` - for dynamic arrays
- `std::unordered_map<K,V>` - for hash tables
- `std::array<T,N>` - for fixed-size arrays

### Avoid Heavy STL Components
- `std::regex` (large compile-time cost)
- Most of `<algorithm>` (unless genuinely needed)
- iostreams (prefer printf-style or raylib's TraceLog)
- Smart pointers (unless ownership is genuinely complex)

## Example

```cpp
// Internal game code - use STL
std::vector<Sprite> sprites;
std::string username = "player1";

// When calling into MiniScript VM
SimpleString scriptUsername = username.c_str();
vm->SetGlobal("username", scriptUsername);
```

Keep conversion code in well-defined places (e.g., a `ScriptBridge` class or module).
