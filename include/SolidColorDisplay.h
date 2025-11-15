#ifndef SOLID_COLOR_DISPLAY_H
#define SOLID_COLOR_DISPLAY_H

#include "Display.h"

// Display that shows a solid color across the entire screen
class SolidColorDisplay : public Display {
public:
    SolidColorDisplay();
    virtual ~SolidColorDisplay();

    void Render() override;
    void Clear() override;

    // Get/set the background color
    Color GetColor() const { return color; }
    void SetColor(Color color) { this->color = color; }

private:
    Color color;
};

#endif // SOLID_COLOR_DISPLAY_H
