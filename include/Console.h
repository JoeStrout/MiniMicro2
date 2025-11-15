#ifndef CONSOLE_H
#define CONSOLE_H

#include "TextDisplay.h"
#include <string>
#include <vector>
#include <queue>
#include <map>
#include <functional>

// Console manages text input/output and command history
class Console {
public:
    // Special key codes (matching the C# version)
    static const int kBackspace = 8;
    static const int kFwdDelete = 127;
    static const int kLeftArrow = 17;
    static const int kRightArrow = 18;
    static const int kUpArrow = 19;
    static const int kDownArrow = 20;
    static const int kTab = 9;
    static const int kControlA = 1;
    static const int kControlC = 3;
    static const int kControlE = 5;
    static const int kControlK = 11;
    static const int kControlU = 21;

    // Callback types
    typedef std::function<void(const std::string&)> InputCallback;
    typedef std::function<std::string(const std::string&)> AutocompleteCallback;
    typedef std::function<bool()> ControlCCallback;

    Console(TextDisplay* display);
    ~Console();

    // Initialize keyboard mapping (call once at startup)
    void InitKeyboardMapping();

    // Update - call every frame
    void Update(float deltaTime);

    // Input mode control
    void StartInput();
    void CommitInput();
    void AbortInput();
    bool InputInProgress() const { return inInputMode; }

    // Handle a key press
    void HandleKey(char keyChar);

    // Get buffered keys (for when not in input mode)
    bool HasBufferedKey() const { return !keyBuffer.empty(); }
    char GetBufferedKey();

    // History management
    void AddToHistory(const std::string& input);

    // Callbacks
    void SetOnInputDone(InputCallback callback) { onInputDone = callback; }
    void SetOnInputChanged(InputCallback callback) { onInputChanged = callback; }
    void SetAutocompleteCallback(AutocompleteCallback callback) { autocompleteCallback = callback; }
    void SetControlCHandler(ControlCCallback callback) { controlCHandler = callback; }

    // Notify console that display scrolled
    void NoteScrolled();

    // Access to the text display
    TextDisplay* GetDisplay() { return display; }

    // Type input programmatically
    void TypeInput(const std::string& text);

private:
    struct RowCol {
        int row;
        int col;
        RowCol() : row(0), col(0) {}
        RowCol(int r, int c) : row(r), col(c) {}
    };

    void ReplaceInput(const std::string& newInput);
    void SetCursorForInput(bool showSuggestion = true);
    void ClearAutocomplete();
    int PrevInputStop(int index, bool byWord);
    int NextInputStop(int index, bool byWord);
    bool IsTokenChar(char c) const;

    TextDisplay* display;

    // Keyboard mapping (virtual char -> physical KeyboardKey)
    std::map<char, int> charToKeyCode;

    // Input state
    bool inInputMode;
    RowCol inputStartPos;
    std::string inputBuf;
    int inputIndex;
    std::string curSuggestion;

    // History
    std::vector<std::string> history;
    int historyIndex;

    // Key buffer
    std::queue<char> keyBuffer;

    // Callbacks
    InputCallback onInputDone;
    InputCallback onInputChanged;
    AutocompleteCallback autocompleteCallback;
    ControlCCallback controlCHandler;
};

#endif // CONSOLE_H
