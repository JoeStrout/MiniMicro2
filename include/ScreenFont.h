#ifndef SCREEN_FONT_H
#define SCREEN_FONT_H

#include "raylib.h"

// Handles the Mini Micro screen font - a 16x16 grid texture
// with special Unicode character mappings
class ScreenFont {
public:
    ScreenFont();
    ~ScreenFont();

    // Load a font texture (should be 16x16 character grid)
    bool Load(const char* texturePath);

    // Get the position in the font grid for a Unicode character
    int GetFontPosition(int unicode) const;

    // Draw a character at the specified position
    void DrawChar(int unicode, float x, float y, Color foreColor, Color backColor);

    // Get character dimensions
    int GetCharWidth() const { return charWidth; }
    int GetCharHeight() const { return charHeight; }

    bool IsLoaded() const { return textureLoaded; }

private:
    Texture2D fontTexture;
    int charWidth;
    int charHeight;
    bool textureLoaded;
};

#endif // SCREEN_FONT_H
