#include "ScreenFont.h"
#include "raylib.h"

ScreenFont::ScreenFont()
    : charWidth(0), charHeight(0), textureLoaded(false) {
}

ScreenFont::~ScreenFont() {
    if (textureLoaded) {
        UnloadTexture(fontTexture);
    }
}

bool ScreenFont::Load(const char* texturePath) {
    if (textureLoaded) {
        UnloadTexture(fontTexture);
    }

    fontTexture = LoadTexture(texturePath);
    if (fontTexture.id == 0) {
        textureLoaded = false;
        return false;
    }

    // Font should be a 16x16 grid
    charWidth = fontTexture.width / 16;
    charHeight = fontTexture.height / 16;
    textureLoaded = true;

    return true;
}

int ScreenFont::GetFontPosition(int unicode) const {
    int fontPos = unicode;

    if (fontPos >= 191 && fontPos <= 255) {
        // Roman accented characters - use as-is
    } else if (fontPos > 127) {
        // Only certain non-ASCII characters are mapped
        switch (unicode) {
        case 0xE200:    fontPos = 130;  break;  // button caps
        case 0xE201:    fontPos = 131;  break;
        case 0xE210:    fontPos = 140;  break;  // stick figure
        case 0xE211:    fontPos = 141;  break;
        case 0xE212:    fontPos = 142;  break;
        case 0xE213:    fontPos = 143;  break;
        case 0xE220:    fontPos = 150;  break;  // tree
        case 0x2022:    fontPos = 158;  break;  // bullet (•)
        case 0x2026:    fontPos = 135;  break;  // ellipsis (…)
        case 0x03C0:    fontPos = 159;  break;  // Pi (π)
        case 0x03C4:    fontPos = 160;  break;  // Tau (τ)
        case 0x2190:    fontPos = 17;   break;  // arrows
        case 0x2191:    fontPos = 19;   break;
        case 0x2192:    fontPos = 18;   break;
        case 0x2193:    fontPos = 20;   break;
        case 0x2610:    fontPos = 132;  break;  // empty box
        case 0x2611:    fontPos = 133;  break;  // box with checkmark
        case 0x2612:    fontPos = 134;  break;  // box with X
        case 0x2660:    fontPos = 136;  break;  // spade
        case 0x2663:    fontPos = 137;  break;  // club
        case 0x2665:    fontPos = 138;  break;  // heart
        case 0x2666:    fontPos = 139;  break;  // diamond
        case 0x2680:    fontPos = 144;  break;  // dice faces
        case 0x2681:    fontPos = 145;  break;
        case 0x2682:    fontPos = 146;  break;
        case 0x2683:    fontPos = 147;  break;
        case 0x2684:    fontPos = 148;  break;
        case 0x2685:    fontPos = 149;  break;
        case 161:       // upside-down exclamation (¡)
        case 169:       // Copyright symbol (©)
        case 172:       // CR symbol (¬)
        case 174:       // Registered symbol (®)
        case 176:       // degree symbol (°)
        case 181:       // micro (µ)
            break;      // Use as-is
        default:
            fontPos = 21;   // unknown character
            break;
        }
    }

    return fontPos;
}

void ScreenFont::DrawChar(int unicode, float x, float y, Color foreColor, Color backColor) {
    if (!textureLoaded) return;

    int fontPos = GetFontPosition(unicode);

    // Calculate position in 16x16 grid
    int charRow = fontPos / 16;
    int charCol = fontPos % 16;

    // Source rectangle in the texture (Y is flipped in OpenGL textures)
    Rectangle source = {
        (float)(charCol * charWidth),
        (float)(charRow * charHeight),
        (float)charWidth,
        (float)charHeight
    };

    // Destination rectangle on screen
    Rectangle dest = {
        x, y,
        (float)charWidth,
        (float)charHeight
    };

    // Draw background (only if not transparent)
    if (backColor.a > 0) {
        DrawRectangleRec(dest, backColor);
    }

    // Draw character from texture
    DrawTexturePro(fontTexture, source, dest, (Vector2){0, 0}, 0.0f, foreColor);
}
