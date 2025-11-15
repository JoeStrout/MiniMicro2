#include "Console.h"
#include "raylib.h"
#include <algorithm>
#include <cctype>
#include <cstring>

Console::Console(TextDisplay* display)
    : display(display),
      inInputMode(false),
      inputIndex(0),
      historyIndex(0) {
}

Console::~Console() {
}

void Console::InitKeyboardMapping() {
    // Build a map from virtual characters to physical key codes
    // by checking what character each physical key produces
    charToKeyCode.clear();

    // Check all letter keys
    for (int keyCode = 39; keyCode <= 96; keyCode++) {
        const char* keyName = GetKeyName(keyCode);
        if (keyName && strlen(keyName) == 1) {
            char ch = tolower(keyName[0]);
            charToKeyCode[ch] = keyCode;
        }
    }
}

void Console::Update(float deltaTime) {
    if (!inInputMode) return;

    // Check for Ctrl key state first
    bool ctrl = IsKeyDown(KEY_LEFT_CONTROL) || IsKeyDown(KEY_RIGHT_CONTROL);

    // Handle Ctrl+key combinations before regular character input
    // Use our keyboard mapping to find the right physical key for each virtual key
    if (ctrl) {
        auto checkCtrlKey = [&](char ch, int ctrlCode) {
            auto it = charToKeyCode.find(ch);
            if (it != charToKeyCode.end() && IsKeyPressed((KeyboardKey)it->second)) {
                HandleKey((char)ctrlCode);
                return true;
            }
            return false;
        };

        if (checkCtrlKey('a', kControlA)) return;
        if (checkCtrlKey('c', kControlC)) return;
        if (checkCtrlKey('e', kControlE)) return;
        if (checkCtrlKey('k', kControlK)) return;
        if (checkCtrlKey('u', kControlU)) return;
    }

    // Handle keyboard input from Raylib (only printable characters)
    int key = GetCharPressed();
    while (key > 0) {
        if (key >= 32) {
            HandleKey((char)key);
        }
        key = GetCharPressed();
    }

    // Handle special keys that don't come through GetCharPressed
    if (IsKeyPressed(KEY_BACKSPACE)) HandleKey((char)kBackspace);
    if (IsKeyPressed(KEY_DELETE)) HandleKey((char)kFwdDelete);
    if (IsKeyPressed(KEY_ENTER)) HandleKey('\n');
    if (IsKeyPressed(KEY_TAB)) HandleKey((char)kTab);
    if (IsKeyPressed(KEY_ESCAPE)) HandleKey((char)27);

    if (IsKeyPressed(KEY_LEFT)) {
        if (ctrl) HandleKey((char)kControlA);
        else HandleKey((char)kLeftArrow);
    }
    if (IsKeyPressed(KEY_RIGHT)) {
        if (ctrl) HandleKey((char)kControlE);
        else HandleKey((char)kRightArrow);
    }
    if (IsKeyPressed(KEY_UP)) HandleKey((char)kUpArrow);
    if (IsKeyPressed(KEY_DOWN)) HandleKey((char)kDownArrow);
    if (IsKeyPressed(KEY_HOME)) HandleKey((char)kControlA);
    if (IsKeyPressed(KEY_END)) HandleKey((char)kControlE);
}

void Console::StartInput() {
    display->GetCursor(inputStartPos.row, inputStartPos.col);
    display->ShowCursor();
    inputBuf = "";
    inputIndex = 0;
    inInputMode = true;
    historyIndex = (int)history.size();
    if (onInputChanged) onInputChanged(inputBuf);
}

void Console::CommitInput() {
    inputIndex = (int)inputBuf.length();
    SetCursorForInput(false);

    // Add to history if not empty and different from last
    std::string lastCommand = history.empty() ? "" : history.back();
    if (!inputBuf.empty() && inputBuf != lastCommand) {
        history.push_back(inputBuf);
    }

    display->HideCursor();
    display->NextLine();
    inInputMode = false;

    if (onInputDone) onInputDone(inputBuf);
}

void Console::AbortInput() {
    inInputMode = false;
    display->HideCursor();
}

void Console::HandleKey(char keyChar) {
    int keyInt = (int)keyChar;

    // Control-C handling
    if (keyInt == kControlC) {
        if (controlCHandler && controlCHandler()) return;
    }

    if (!inInputMode) {
        // Buffer keys when not in input mode
        keyBuffer.push(keyChar);
        return;
    }

    bool byWord = IsKeyDown(KEY_LEFT_ALT) || IsKeyDown(KEY_RIGHT_ALT);

    if (keyInt != kTab) ClearAutocomplete();

    if (keyInt == 3 || keyInt == 10 || keyInt == 13) {
        // Enter/Return
        CommitInput();
    } else if (keyInt == kLeftArrow) {
        inputIndex = PrevInputStop(inputIndex, byWord);
    } else if (keyInt == kRightArrow) {
        inputIndex = NextInputStop(inputIndex, byWord);
    } else if (keyInt == kControlA) {
        inputIndex = 0;
    } else if (keyInt == kControlE) {
        inputIndex = (int)inputBuf.length();
    } else if (keyInt == kControlK) {
        // Delete to end of line
        ReplaceInput(inputBuf.substr(0, inputIndex));
    } else if (keyInt == kControlU) {
        // Delete to start of line
        ReplaceInput(inputBuf.substr(inputIndex));
        inputIndex = 0;
    } else if (keyInt == kBackspace) {
        int stop = PrevInputStop(inputIndex, byWord);
        if (stop < inputIndex) {
            inputBuf = inputBuf.substr(0, stop) + inputBuf.substr(inputIndex);
            int delCount = inputIndex - stop;
            for (int i = 0; i < delCount; i++) display->Backup();
            display->Print(inputBuf.substr(stop));
            for (int i = 0; i < delCount; i++) display->Put(' ');
            inputIndex = stop;
            if (onInputChanged) onInputChanged(inputBuf);
        }
    } else if (keyInt == kFwdDelete) {
        int stop = NextInputStop(inputIndex, byWord);
        if (stop > inputIndex) {
            inputBuf = inputBuf.substr(0, inputIndex) + inputBuf.substr(stop);
            display->Print(inputBuf.substr(inputIndex));
            for (int i = 0; i < stop - inputIndex; i++) display->Put(' ');
            if (onInputChanged) onInputChanged(inputBuf);
        }
    } else if (keyInt == kUpArrow) {
        if (historyIndex > 0) {
            historyIndex--;
            ReplaceInput(history[historyIndex]);
        }
    } else if (keyInt == kDownArrow) {
        if (historyIndex < (int)history.size()) {
            historyIndex++;
            ReplaceInput(historyIndex < (int)history.size() ? history[historyIndex] : "");
        }
    } else if (keyInt == kTab) {
        if (!curSuggestion.empty()) {
            inputBuf += curSuggestion;
            inputIndex += curSuggestion.length();
            display->Print(curSuggestion);
        }
    } else if (keyInt >= 32) {
        // Regular printable character
        inputBuf = inputBuf.substr(0, inputIndex) + keyChar + inputBuf.substr(inputIndex);
        display->Print(inputBuf.substr(inputIndex));
        inputIndex++;
        if (onInputChanged) onInputChanged(inputBuf);
    }

    if (inInputMode) SetCursorForInput();
}

char Console::GetBufferedKey() {
    if (keyBuffer.empty()) return 0;
    char key = keyBuffer.front();
    keyBuffer.pop();
    return key;
}

void Console::AddToHistory(const std::string& input) {
    history.push_back(input);
}

void Console::NoteScrolled() {
    inputStartPos.row++;
}

void Console::TypeInput(const std::string& text) {
    for (char c : text) {
        HandleKey(c);
    }
}

void Console::ReplaceInput(const std::string& newInput) {
    display->SetCursor(inputStartPos.row, inputStartPos.col);
    for (size_t i = 0; i < inputBuf.length(); i++) {
        display->Put(' ');
    }
    inputBuf = newInput;
    display->SetCursor(inputStartPos.row, inputStartPos.col);
    display->Print(inputBuf);
    inputIndex = (int)inputBuf.length();
    SetCursorForInput();
}

void Console::SetCursorForInput(bool showSuggestion) {
    int curRow = inputStartPos.row;
    int curCol = inputStartPos.col + inputIndex;

    while (curCol >= display->GetCols()) {
        curRow--;
        curCol -= display->GetCols();
    }

    display->SetCursor(curRow, curCol);

    if (!showSuggestion) return;

    curSuggestion = "";
    if (autocompleteCallback && inputIndex == (int)inputBuf.length()) {
        curSuggestion = autocompleteCallback(inputBuf);
    }

    if (!curSuggestion.empty()) {
        Color c = display->GetTextColor();
        Color back = display->GetBackColor();

        // Blend text color with background for suggestion
        Color blendedColor = {
            (unsigned char)(c.r * 0.25f + back.r * 0.75f),
            (unsigned char)(c.g * 0.25f + back.g * 0.75f),
            (unsigned char)(c.b * 0.25f + back.b * 0.75f),
            (unsigned char)255
        };

        display->SetTextColor(blendedColor);
        display->Print(curSuggestion);
        display->SetTextColor(c);

        for (size_t i = 0; i < curSuggestion.length(); i++) {
            display->Backup();
        }
        display->SetCursor(curRow, curCol);
    }
}

void Console::ClearAutocomplete() {
    if (curSuggestion.empty()) return;

    int row, col;
    display->GetCursor(row, col);

    for (size_t i = 0; i < curSuggestion.length(); i++) {
        display->Put(' ');
    }

    curSuggestion = "";
    display->SetCursor(row, col);
}

int Console::PrevInputStop(int index, bool byWord) {
    if (index <= 0) return index;
    index--;

    if (byWord) {
        // Skip any non-word characters, then continue till we get to non-word chars again
        while (index > 0 && !IsTokenChar(inputBuf[index])) {
            index--;
        }
        while (index > 0 && IsTokenChar(inputBuf[index - 1])) {
            index--;
        }
    }

    return index;
}

int Console::NextInputStop(int index, bool byWord) {
    int maxi = (int)inputBuf.length();
    if (index >= maxi) return index;
    index++;

    if (byWord) {
        // Skip any non-word characters, then continue till we get to non-word chars again
        while (index < maxi && !IsTokenChar(inputBuf[index])) {
            index++;
        }
        while (index < maxi && IsTokenChar(inputBuf[index - 1])) {
            index++;
        }
    }

    return index;
}

bool Console::IsTokenChar(char c) const {
    return std::isalnum(c) || c == '_' || c == '.';
}
