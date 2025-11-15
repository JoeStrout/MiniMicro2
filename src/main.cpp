#include "raylib.h"
#include "ResourcePath.h"
#include "Machine.h"
#include "SolidColorDisplay.h"
#include "TextDisplay.h"
#include "ScreenFont.h"
#include "Console.h"

// Window configuration and other constants
const int windowWidth = 1024;
const int windowHeight = 768;
const Color bezelColor = { 218, 209, 185, 255 };

Texture2D LoadTextureOrFail(const char* path) {
	Texture2D tex = LoadTexture(path);
	if (tex.id == 0) {
		TraceLog(LOG_ERROR, "Failed to load %s", path);
	}
	return tex;
}

void drawBezel() {
	static bool initialized = false;
	static Texture2D bezelTexture, stickerTexture;
	if (!initialized) {
		bezelTexture = LoadTextureOrFail(GetResourceFile("images/3DBezel.png").c_str());
		stickerTexture = LoadTextureOrFail(GetResourceFile("images/MiniMicroSticker.png").c_str());
		initialized = true;
	}
	DrawTexture(bezelTexture, 0, 0, bezelColor);
	DrawTextureEx(stickerTexture,
				  (Vector2){windowWidth - 56 - 32, windowHeight - 42 - 24},
				  0,
				  64.0f / stickerTexture.width,
				  WHITE);
}

int main() {
    // Initialize window and other Raylib systems
    InitWindow(windowWidth, windowHeight, "Mini Micro 2");
    SetTargetFPS(60);
	InitAudioDevice();

	Sound bootupSound = LoadSound(GetResourceFile("sounds/startup-chime.wav").c_str());
	PlaySound(bootupSound);

	// Load the screen font shader
	ScreenFont::LoadShader(
		GetResourceFile("shaders/screenfont.vs").c_str(),
		GetResourceFile("shaders/screenfont.fs").c_str()
	);

	// Create the machine
	Machine machine;

	// Set display 1 to a nice blue color for testing
	SolidColorDisplay* display1 = new SolidColorDisplay();
	display1->SetColor((Color){33, 33, 99, 255});
	machine.SetDisplay(1, display1);
	
	// Create a TextDisplay for layer 0
	TextDisplay* textDisplay = new TextDisplay();
	textDisplay->LoadFont(GetResourceFile("images/ScreenFont.png").c_str());
	textDisplay->SetTextColor(GREEN);
	machine.SetDisplay(0, textDisplay);

	// Create console
	Console console(textDisplay);
	console.InitKeyboardMapping();  // Initialize keyboard layout mapping
	console.SetOnInputDone([&](const std::string& input) {
		textDisplay->Print("You said: ");
		textDisplay->Print(input);
		textDisplay->Print("\n]");
		console.StartInput();
	});

	// Print welcome message
	textDisplay->Print("Mini Micro 2 Console Test\n");
	textDisplay->Print("Type something and press Enter!\n");
	textDisplay->Print("]");
	console.StartInput();

    // Main game loop
    while (!WindowShouldClose()) {
        // Update
		float deltaTime = GetFrameTime();
        machine.Update();
		console.Update(deltaTime);

        // Draw
        BeginDrawing();
		machine.Render();
		drawBezel();
        EndDrawing();
    }

    // Cleanup
	UnloadSound(bootupSound);
	ScreenFont::UnloadShader();
	CloseWindow();

    return 0;
}
