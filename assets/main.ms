// Mini Micro 2 -- main entry point.
//
// The host (raylib-miniscript) runs this file at startup: with no script
// argument it looks for assets/main.ms beside the executable, which is exactly
// where this file sits in a packaged app.
//
// Everything below this file is MiniScript.  lib/ is the engine layer, shared
// with Soda; mm/ is the Mini Micro shell (REPL, editor, file browser); sys/ is
// the /sys disk the user sees from the command line.

rl = raylib

// Import search path.  The first entry is the running script's own directory,
// so a user program can import modules sitting next to it.  The other two must
// NOT be written in terms of $MS_SCRIPT_DIR: the host repoints that variable at
// every script it runs, and running user programs is Mini Micro's whole job.
// So pin them to where this file lives, resolved once, right now.
bootDir = env.MS_SCRIPT_DIR
if bootDir[0] != "/" and bootDir[1] != ":" then  // (":" catches "C:\..." on Windows)
	bootDir = file.curdir + "/" + bootDir  // (relative; make it absolute)
end if
env.MS_IMPORT_PATH = "$MS_SCRIPT_DIR" + ":" + bootDir + "/mm" + ":" + bootDir + "/lib"

// The built-in `version` map is frozen, so shadow it with a global of our own,
// carrying the same keys plus our overrides.  Code shared with Soda can switch
// on version.hostName to tell the two environments apart.
globals.version = version + {
	"host": "2.0",
	"hostName": "Mini Micro",
	"hostInfo": "http://miniscript.org/MiniMicro"}

rl.SetTraceLogLevel rl.LOG_WARNING
rl.InitWindow 1024, 768
rl.SetWindowTitle "Mini Micro 2"
rl.SetTargetFPS 60

// Our own resources live on /hw, the hardware disk: the host mounts this
// file's directory there at boot.  These used to be written relative to the
// working directory, which broke for a packaged app launched from the Finder.
// The chime is played by /sys/startup.ms, through the _startupChime the shell
// seeds for it -- that is where env.bootOpts can turn it off.  Loaded here
// because /hw is ours, not the shell's.
bootupSound = rl.LoadSound("/hw/sounds/startup-chime.wav")

bezelTexture = rl.LoadTexture("/hw/images/3DBezel.png")
bezelColor = [218, 208, 185, 255]
stickerTexture = rl.LoadTexture("/hw/images/MiniMicroSticker.png")
print "sticker: " + stickerTexture

diskInsertedSound = rl.LoadSound("/hw/sounds/disk-inserted.wav")
diskEjectedSound = rl.LoadSound("/hw/sounds/disk-ejected.wav")	// (for the shell's eject)

import "importUtil"

ensureImport ["color", "Image", "Sound", "Display", "SolidColorDisplay", "PixelDisplay",
  "SpriteDisplay", "TileDisplay", "TextDisplay", "mouse", "key", "Console", "Shell"]

// Our screen is the 960x640 area framed by the bezel, not the whole window.
// Tell the display layer where that is; everything sizes and centers itself
// against these, and _update below translates rendering to match.  (The bezel
// image is 1024x768, with a thicker band at the bottom for the logo -- so the
// insets are NOT symmetrical, and a plain "center it" would land 64px high.)
Display.screenLeft = 32
Display.screenTop = 34
Display.screenWidth = 960
Display.screenHeight = 640

Display.Initialize

// window: query and control the application window.
// Mini Micro exposes window.width/height/fullScreen as assignable properties,
// but MiniScript 2 has no assignment hook, so the setters are methods here.
globals.window = {}
window.title = "Mini Micro 2"

window.width = function
	return rl.GetScreenWidth
end function

window.height = function
	return rl.GetScreenHeight
end function

window.fullScreen = function
	return rl.IsWindowFullscreen
end function

window.setSize = function(w=960, h=640)
	rl.SetWindowSize w, h
end function

window.setTitle = function(title="")
	rl.SetWindowTitle title
	self.title = title
end function

// Raylib only offers a toggle, so compare with the current state first.
window.setFullScreen = function(full=true)
	if (full != 0) == (rl.IsWindowFullscreen != 0) then return
	rl.ToggleFullscreen
end function

// Mounting a disk is the user's act, not a program's: a drop is the user
// naming a target, exactly as a file picker would be.  The host reports base
// names only and we mount by index, so no host path is named here or handed
// back to script.  Clear the queue when done -- but only when done, since
// mountDropped names an index into it, and it survives until the next drop, so
// an unmountable file would otherwise retry every frame.
//
// Slot by index (first dropped item to /usr, second to /usr2) is what Mini
// Micro 1 does.  file.dropPosition is the better answer once the bezel has real
// disk slots to drop onto; it is in window coordinates, top-down, so it needs
// the same transform mouse.update applies before comparing with anything drawn.
_handleDrops = function
	dropped = file.droppedFiles
	if not dropped then return
	print "Detected file drop: " + dropped
	slots = ["usr", "usr2"]
	for i in range(0, 1)
		if i >= dropped.len then break
		if file.mountDropped(i, slots[i]) then
			rl.PlaySound diskInsertedSound
			print "Mounted " + dropped[i].name + " as " + slots[i]
		else
			print dropped[i].name + " is not a mountable disk"
		end if
	end for
	file.clearDroppedFiles
end function

// The console owns key input: its update collects keys (with repeat, and with
// the control chords raylib does not report as characters) into key.keyQueue,
// which is why key.update is NOT in the list below -- running both would
// deliver every special key twice.  Mouse update comes first, since the
// console's selection dragging reads mouse.x/y.
globals.console = Console.Make(text)

_consoleUpdate = function
	console.update
end function

// updateCallbacks: a list of methods to call on every frame.  This includes standard
// Soda update methods, but you may add your own methods to ensure they are invoked
// at update time as well.
updateCallbacks = [
	@mouse.update,
	@_consoleUpdate,
	@Sound.UpdateAll,
]

// Slide all display rendering into the bezel's opening.  The displays draw
// themselves at 0,0..960,640; this camera is a pure translation by the screen
// rect's top-left corner.  Keep the bracket tight around RenderAll: anything
// that calls BeginTextureMode inside it (PixelDisplay._beginDraw, ttFonts)
// would bake the camera matrix into the render texture.
screenCamera = {"offsetX": Display.screenLeft, "offsetY": Display.screenTop,
   "targetX": 0, "targetY": 0, "rotation": 0, "zoom": 1}

_update = function(beginEndRaylibDrawing = true)
	// A program can be time-sliced mid-draw, including when we have set all
	// drawing to go to a render texture.  If we attempted to render the
	// displays in the middle of that, it would make a mess.  So, skip
	// the frame; the program closes its bracket within a slice or two and the
	// next frame draws normally.
	if beginEndRaylibDrawing and rl.rlGetActiveFramebuffer != 0 then return

	// Not in updateCallbacks: that is a hook a user program may replace, and
	// disks have to keep mounting whatever is running.
	_handleDrops
	
	// Render all displays.
	if beginEndRaylibDrawing then rl.BeginDrawing
	rl.BeginMode2D screenCamera
	Display.RenderAll
	rl.EndMode2D
	rl.DrawTexture bezelTexture, 0, 0, bezelColor
	for f in updateCallbacks; f; end for
	rl.DrawTextureEx stickerTexture, 
	  [window.width - 56 - 32, window.height - 42 - 24],
	  0, 64 / stickerTexture.width, rl.WHITE
	if beginEndRaylibDrawing then rl.EndDrawing
end function

// Override (actually, shadow) the `yield` intrinsic to do our standard
// update, so that a tight yield loop does not lock up the app.
globals.yield = function
	outer._update
	intrinsics.yield
end function

// And similar for `wait`.
globals.wait = function(duration=1)
	endTime = time + duration
	while time < endTime
		intrinsics.yield
		outer._update
	end while
end function

// Lock the file system down.  From here on only mounted disks exist: /sys and
// the hidden /hw, plus whatever the user chooses to mount as /usr or /usr2.
// No path a program can name reaches anything else.
//
// This is deliberately the last thing boot does, and it is one-way -- there is
// no intrinsic to leave.  Everything above needed the unrestricted host: the
// import path is built from real directories, and the resources above load
// through /hw only because the host mounted it before running this file.
file.enterSandbox

file.setdir "/usr"

// The shell owns everything from here.  It seeds a child interpreter from
// `globals` as it stands right now, so anything a user program should be able
// to see has to exist by this line.
globals.shell = Shell.Make(console, bootupSound)
shell.run
