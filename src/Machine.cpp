#include "Machine.h"
#include "SolidColorDisplay.h"

Machine::Machine() {
    // Initialize all 8 display layers with SolidColorDisplay by default
    displays.resize(kDisplayCount, nullptr);
    for (int i = 0; i < kDisplayCount; i++) {
        displays[i] = new SolidColorDisplay();
    }
}

Machine::~Machine() {
    // Clean up all displays
    for (Display* display : displays) {
        delete display;
    }
    displays.clear();
}

void Machine::Update() {
    // Update all displays (for cursor blinking, animations, etc.)
    float deltaTime = GetFrameTime();
    for (int i = 0; i < kDisplayCount; i++) {
        if (displays[i]) {
            displays[i]->Update(deltaTime);
        }
    }
    // TODO: Handle input
}

void Machine::Render() {
    // Render each display in reverse order (7 down to 0)
    // so that display 0 is on top
    for (int i = kDisplayCount - 1; i >= 0; i--) {
        if (displays[i]) displays[i]->Render();
    }
}

Display* Machine::GetDisplay(int index) {
    if (index < 0 || index >= kDisplayCount) return nullptr;
    return displays[index];
}

void Machine::SetDisplay(int index, Display* display) {
    if (index < 0 || index >= kDisplayCount) return;

    // Delete old display if it exists
    if (displays[index]) {
        delete displays[index];
    }

    displays[index] = display;
}
