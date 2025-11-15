#include "SolidColorDisplay.h"

SolidColorDisplay::SolidColorDisplay() : color(BLACK) {
}

SolidColorDisplay::~SolidColorDisplay() {
}

void SolidColorDisplay::Render() {
    if (!visible) return;

    // Fill the entire screen with the color
    ClearBackground(color);
}

void SolidColorDisplay::Clear() {
    color = BLACK;
}
