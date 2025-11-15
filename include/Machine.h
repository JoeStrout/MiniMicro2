#ifndef MACHINE_H
#define MACHINE_H

#include <vector>
#include "Display.h"

// The Machine manages the 8 display layers and input
class Machine {
public:
    static const int kDisplayCount = 8;

    Machine();
    ~Machine();

    // Update the machine state (input, etc.)
    void Update();

    // Render all visible displays in order
    void Render();

    // Get a specific display layer (0-7)
    Display* GetDisplay(int index);

    // Set a display layer (Machine takes ownership)
    void SetDisplay(int index, Display* display);

private:
    std::vector<Display*> displays;
};

#endif // MACHINE_H
