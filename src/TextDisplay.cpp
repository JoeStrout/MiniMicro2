#include "TextDisplay.h"
#include <algorithm>

TextDisplay::TextDisplay()
    : cols(68), rows(26),
      colSpacing(14.0f), rowSpacing(24.0f),
      cursorX(0), cursorY(0),
      cursorShown(false), cursorBlinking(false),
      cursorTime(0.0f), cursorOnTime(0.7f), cursorOffTime(0.3f),
      textColor(GREEN), backColor(BLANK), inverse(false) {

    SetSize(cols, rows);
}

TextDisplay::~TextDisplay() {
}

void TextDisplay::SetSize(int newCols, int newRows) {
    cols = newCols;
    rows = newRows;

    // Resize the cells grid
    cells.resize(rows);
    for (int row = 0; row < rows; row++) {
        cells[row].resize(cols);
        for (int col = 0; col < cols; col++) {
            cells[row][col].foreColor = textColor;
            cells[row][col].backColor = backColor;
        }
    }

    // Reset cursor to home
    cursorX = 0;
    cursorY = 0;
}

void TextDisplay::Render() {
    if (!visible) return;

    // Display offset from window edge
    const float offsetX = 32.0f;
    const float offsetY = 34.0f;

    // Draw each cell (bottom-up: row 0 at bottom, row 25 at top)
    for (int row = 0; row < rows; row++) {
        for (int col = 0; col < cols; col++) {
            const Cell& cell = cells[row][col];

            float x = offsetX + col * colSpacing;
            float y = offsetY + (rows - 1 - row) * rowSpacing;

            // Determine display colors (respecting inverse)
            Color fore = cell.inverse ? cell.backColor : cell.foreColor;
            Color back = cell.inverse ? cell.foreColor : cell.backColor;

            // Draw character using ScreenFont
            if (screenFont.IsLoaded()) {
                screenFont.DrawChar(cell.character, x, y, fore, back);
            } else {
                // Fallback: draw background and text
                DrawRectangle((int)x, (int)y, (int)colSpacing, (int)rowSpacing, back);
                if (cell.character != ' ') {
                    char str[2] = { cell.character, '\0' };
                    DrawText(str, (int)x, (int)y, 16, fore);
                }
            }
        }
    }
}

void TextDisplay::Clear() {
    Fill(' ');
    cursorShown = false;
}

void TextDisplay::Fill(char c) {
    for (int row = 0; row < rows; row++) {
        for (int col = 0; col < cols; col++) {
            cells[row][col].character = c;
            cells[row][col].foreColor = textColor;
            cells[row][col].backColor = backColor;
            cells[row][col].inverse = inverse;
        }
    }
}

void TextDisplay::FillRow(int row, char c) {
    if (row < 0 || row >= rows) return;

    for (int col = 0; col < cols; col++) {
        cells[row][col].character = c;
        cells[row][col].foreColor = textColor;
        cells[row][col].backColor = backColor;
        cells[row][col].inverse = inverse;
    }
}

void TextDisplay::ClearRow(int row) {
    FillRow(row, ' ');
}

void TextDisplay::Set(int row, int col, char c) {
    Set(row, col, c, textColor, backColor);
}

void TextDisplay::Set(int row, int col, char c, Color foreColor, Color backColor) {
    if (row < 0 || row >= rows || col < 0 || col >= cols) return;

    Cell& cell = cells[row][col];
    cell.character = c;

    if (inverse) {
        cell.foreColor = backColor;
        cell.backColor = foreColor;
    } else {
        cell.foreColor = foreColor;
        cell.backColor = backColor;
    }

    UpdateCell(row, col);
}

TextDisplay::Cell* TextDisplay::Get(int row, int col) {
    if (row < 0 || row >= rows || col < 0 || col >= cols) return nullptr;
    return &cells[row][col];
}

void TextDisplay::Print(const std::string& text) {
    HideCursorVisual();
    for (char c : text) {
        Put(c);
    }
}

void TextDisplay::Put(char c) {
    if (c == '\n' || c == '\r') {
        NextLine();
    } else if (c == '\t') {
        do {
            Set(cursorY, cursorX, ' ');
            Advance();
        } while (cursorX % 4 != 0);
    } else if (c == 7) {
        // Beep - could trigger a sound here
        // For now, do nothing
    } else if (c == 8) {
        // Backspace
        Backup();
    } else if (c == (char)134) {
        // Inverse on
        inverse = true;
    } else if (c == (char)135) {
        // Inverse off
        inverse = false;
    } else {
        Set(cursorY, cursorX, c);
        Advance();
    }
}

void TextDisplay::Advance() {
    cursorX++;
    if (cursorX >= cols) {
        NextLine();
    }
}

void TextDisplay::Backup() {
    HideCursorVisual();
    cursorX--;
    if (cursorX < 0) {
        if (cursorY >= rows - 1) {
            cursorX = 0;
            return;
        }
        cursorY++;
        cursorX = cols - 1;
    }
}

void TextDisplay::NextLine() {
    cursorY--;
    while (cursorY < 0) {
        Scroll();
    }
    cursorX = 0;
}

void TextDisplay::Scroll() {
    // Copy each row from the one above it
    for (int row = rows - 1; row > 0; row--) {
        for (int col = 0; col < cols; col++) {
            cells[row][col] = cells[row - 1][col];
        }
    }

    // Adjust cursor position
    if (cursorY < rows - 1) {
        cursorY++;
    }

    // Clear the top row
    ClearRow(0);
}

void TextDisplay::SetCursor(int row, int col) {
    bool wasShown = cursorShown;
    if (cursorShown) HideCursor();

    cursorX = col;
    if (cursorX < 0) cursorX = 0;
    else if (cursorX >= cols) cursorX = cols - 1;

    cursorY = row;
    if (cursorY < 0) cursorY = 0;
    if (cursorY >= rows) cursorY = rows - 1;

    if (wasShown) ShowCursor();
}

void TextDisplay::GetCursor(int& outRow, int& outCol) const {
    outRow = cursorY;
    outCol = cursorX;
}

void TextDisplay::HideCursorVisual() {
    if (!cursorShown) return;
    cells[cursorY][cursorX].inverse = false;
    UpdateCell(cursorY, cursorX);
}

void TextDisplay::HideCursor() {
    HideCursorVisual();
    cursorTime = 0;
    cursorShown = false;
}

void TextDisplay::ShowCursor() {
    cells[cursorY][cursorX].inverse = true;
    UpdateCell(cursorY, cursorX);
    cursorTime = 0;
    cursorShown = true;
}

void TextDisplay::UpdateCell(int row, int col) {
    // Nothing special needed in Raylib - cells are just data
    // The Render() method draws everything
}

void TextDisplay::Update(float deltaTime) {
    if (cursorShown) {
        // Make the cursor blink
        cursorTime += deltaTime;
        if (!cursorBlinking && cursorTime > cursorOnTime) {
            HideCursor();
            cursorShown = true;
            cursorBlinking = true;
        } else if (cursorBlinking && cursorTime > cursorOffTime) {
            ShowCursor();
            cursorBlinking = false;
        }
    }
}

void TextDisplay::SetCellSpacing(float colSp, float rowSp) {
    colSpacing = colSp;
    rowSpacing = rowSp;
}

bool TextDisplay::LoadFont(const char* fontTexturePath) {
    return screenFont.Load(fontTexturePath);
}
