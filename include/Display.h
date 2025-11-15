#ifndef DISPLAY_H
#define DISPLAY_H

#include "raylib.h"

// Base class for all display layers
class Display {
public:
    Display();
    virtual ~Display();

    // Render this display layer
    virtual void Render() = 0;

    // Clear/reset the display to its default state
    virtual void Clear() = 0;

    // Get/set visibility
    bool IsVisible() const { return visible; }
    void SetVisible(bool visible) { this->visible = visible; }

protected:
    bool visible;
};

#endif // DISPLAY_H
