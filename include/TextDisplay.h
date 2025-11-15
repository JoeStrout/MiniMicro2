#ifndef TEXT_DISPLAY_H
#define TEXT_DISPLAY_H

#include "Display.h"
#include "ScreenFont.h"
#include <vector>
#include <string>

// Text-based display with a grid of characters
class TextDisplay : public Display {
public:
    // Cell represents one character position in the grid
    struct Cell {
        char character;
        Color foreColor;
        Color backColor;
        bool inverse;  // Used for hardware cursor

        Cell() : character(' '), foreColor(WHITE), backColor(BLACK), inverse(false) {}
    };

    TextDisplay();
    virtual ~TextDisplay();

    void Render() override;
    void Clear() override;

    // Grid dimensions (default 68x26)
    int GetCols() const { return cols; }
    int GetRows() const { return rows; }
    void SetSize(int cols, int rows);

    // Cell operations
    void Set(int row, int col, char c);
    void Set(int row, int col, char c, Color textColor, Color backColor);
    Cell* Get(int row, int col);
    void Fill(char c);
    void FillRow(int row, char c);
    void ClearRow(int row);

    // Printing and cursor
    void Print(const std::string& text);
    void Put(char c);
    void SetCursor(int row, int col);
    void GetCursor(int& outRow, int& outCol) const;
    void ShowCursor();
    void HideCursor();
    void Advance();
    void Backup();
    void NextLine();
    void Scroll();

    // Colors
    Color GetTextColor() const { return textColor; }
    void SetTextColor(Color color) { textColor = color; }
    Color GetBackColor() const { return backColor; }
    void SetBackColor(Color color) { backColor = color; }

    // Inverse mode
    bool GetInverse() const { return inverse; }
    void SetInverse(bool inv) { inverse = inv; }

    // Cell spacing (in pixels)
    float GetColSpacing() const { return colSpacing; }
    float GetRowSpacing() const { return rowSpacing; }
    void SetCellSpacing(float colSpacing, float rowSpacing);

    // Font
    bool LoadFont(const char* fontTexturePath);
    ScreenFont* GetFont() { return &screenFont; }

    // Update for cursor blinking
    void Update(float deltaTime);

private:
    void UpdateCell(int row, int col);
    void HideCursorVisual();

    int cols;
    int rows;
    float colSpacing;
    float rowSpacing;

    std::vector<std::vector<Cell>> cells;  // [row][col]

    int cursorX;
    int cursorY;
    bool cursorShown;
    bool cursorBlinking;
    float cursorTime;
    float cursorOnTime;
    float cursorOffTime;

    Color textColor;
    Color backColor;
    bool inverse;

    ScreenFont screenFont;
};

#endif // TEXT_DISPLAY_H
