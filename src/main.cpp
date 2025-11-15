#include "raylib.h"
#include "ResourcePath.h"

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
	//Sound beepSound = LoadSound("resources/sounds/beep-single.wav");
	
	PlaySound(bootupSound);

    // Main game loop
    while (!WindowShouldClose()) {
        // Update
        // (Nothing to update yet)

        // Draw
        BeginDrawing();
        ClearBackground(BLACK);
		drawBezel();
        EndDrawing();
    }

    // Cleanup
	UnloadSound(bootupSound);
	CloseWindow();

    return 0;
}
