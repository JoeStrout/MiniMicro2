# Notes for Claude

## Project Context
This is MiniMicro2 — **Mini Micro 2**, a rewrite of Mini Micro (originally
Unity/C#).  The user (Joe Strout) is the original author of Mini Micro and
MiniScript.

Mini Micro 2 is written in MiniScript, running on the **raylib-miniscript**
host.  There is nothing here to compile.  An earlier C++/Raylib implementation
lived in `src/` and `include/`; it is now in `archive/` and no longer builds.
Don't reach for it except as a reference for how something used to work.

**Reference sources:**
- Unity original: `/Users/jstrout/Documents/svnrepo/stroutandsons/MiniScript/MiniMicro/`
- The C++ attempt: `archive/` in this repo
- Soda (shares our engine layer): `../soda`
- The host: `../raylib-miniscript` (see its `API_DOC.md` for intrinsics)

## Layout

```
assets/
  main.ms      entry point; the host runs this at startup
  hostopts.txt appId and default disk; read by the host before any script runs
  lib/         -> ../../soda/lib   (symlink; engine layer, SHARED WITH SODA)
  mm/          the Mini Micro shell: REPL, editor, file browser
  hw/          the /hw disk: images/ sounds/ fonts/ -- our own resources
  sys/         -> ../../minimicro-sysdisk/sys  (symlink; the /sys disk)
archive/       the old C++ implementation; dead
raylib-miniscript -> ../raylib-miniscript/build/raylib-miniscript  (symlink)
```

`lib`, `sys`, and `raylib-miniscript` are gitignored — the right target differs
per machine.

## Running it

```bash
./raylib-miniscript          # no argument: runs assets/main.ms
```

The host resolves a missing script argument as `assets/main.ms` in the working
directory first, then beside the executable (which is how a packaged app
works).  It opens a window, so run it in the background and kill it rather than
blocking a tool call; `sleep` then check the log for errors.

## Important Technical Details

### The shared engine layer
`assets/lib` is a symlink to Soda's `lib/`.  **Editing anything there changes
Soda too.**  Keep changes no-ops for Soda (sensible defaults that preserve its
current behavior), and put Mini Micro-specific code in `assets/mm/` instead
where you can.  Code that must differ at runtime switches on
`version.hostName` — `"Mini Micro"` here, `"Soda"` there.

### The version map
The host's built-in `version` map is **frozen**, so `main.ms` shadows it with a
global built by merging: `globals.version = version + {...}`.  Soda does the
same in `soda.ms`, guarded so the host application wins if it got there first.

### The file system and the sandbox
Paths are virtual and always `/`-separated.  The host mounts two disks before
running `main.ms`:

- `/hw` — the hardware disk: `assets/hw`, read-only.  Our own resources (bezel,
  sticker, screen font, boot chime) load from `/hw/...`.  It is **hidden**: it
  will not appear in a listing of `/`.  Undocumented, not secret.
- `/sys` — `assets/sys`, read-only.  Ships from the minimicro-sysdisk repo on
  its own release cycle, which is why it is not merged into `/hw`.

Each disk is its own subdirectory of `assets/`, and the host mounts only those
named subdirectories — never `assets/` itself.  That keeps `main.ms`, `mm/`,
and `lib/` off every disk, so a user program cannot read the shell's own source.
Anything put directly in `assets/` is invisible to script; anything dropped in
`assets/hw/` is readable by any program, so put resources there and nothing else.

- `/usr`, `/usr2` — the user disks, writable.  What is mounted is remembered in
  `<app data dir>/prefs.txt` and comes back at boot; `assets/hostopts.txt` names
  the app data directory (`appId`) and the folder under `~/Documents` to create
  and mount as `/usr` on first run (`defaultDisk`).  Without that file we would
  share preferences with every other raylib-miniscript build.

Mounting a user disk is always the user's choice, never a program's: script may
*request* a mount but can never name the target.  Drag and drop is the route
that works today — `_handleDrops` in `main.ms`, called from `_update` — and a
native file picker is still to come.  `file.mountAppData` mounts a subfolder of
our own app data directory, which a program may name because it cannot escape
it.  `-usr <path>` and `-usr2 <path>` on the command line are for testing and
are deliberately not remembered.

`main.ms` calls `file.enterSandbox` as its last act of setup.  That is a
**one-way latch** — there is no intrinsic to leave, and there must never be
one.  Before it, host paths work normally (boot needs that: the import path is
built from real directories).  After it, only mounted disks exist, and any
other path simply does not exist — no distinguishable "permission denied",
because that would let a program map the host file system by probing.

So anything that must touch a real host path has to happen **above** the
`file.enterSandbox` line in `main.ms`.  Rejections are logged to stderr as
`[fs] rejected ...`; check there first when a path mysteriously fails.

The `file` module is fully routed.  Two things differ from Mini Micro 1:
`f.position` is not assignable (MS2 has no assignment hooks) — use `f.seek pos`;
and a file handle buffers in memory, so **an unclosed handle loses its writes**.

The raylib bindings are routed too, and the ones that cannot be made safe —
`GetWorkingDirectory`, `GetApplicationDirectory`, `ChangeDirectory`,
`TakeScreenshot`, `OpenURL`, `LoadDroppedFiles`, the `Set*FileCallback` hooks —
refuse once sandboxed, returning empty rather than raising.  `import` switches
search paths at the latch (see below).  `http.post` accepts only http and https
URLs.

raylib's `LoadDroppedFiles` returns real host paths, so it is refused; the
sandboxed replacement is in the `file` module — `file.droppedFiles` (base names
and an `isDirectory` flag, never a path), `file.dropPosition`,
`file.mountDropped index, "usr"`, and `file.clearDroppedFiles`.  The queue
persists until the next drop or an explicit clear, so a handler must clear it or
it will act on the same drop every frame — but **only after mounting**, since
`mountDropped` names an index into that same queue and silently fails (returns
false, as if the disk were unmountable) once it has been cleared.
**Modifier keys are not readable at
drop time** (the drag comes from another application, so this window has had no
key events); position is the only context a drop carries.  A dropped file that
is not a folder cannot be mounted or read at all until the zip backend lands.

### Import path
There are two, and the latch is the switch between them.

**Before it — boot only.**  `main.ms` sets `MS_IMPORT_PATH` to
`$MS_SCRIPT_DIR : <assets>/mm : <assets>/lib`, real host directories, which is
how the engine layer and the shell get imported at all.  The last two are
absolute paths resolved once at boot, deliberately: the host repoints
`MS_SCRIPT_DIR` at every script it runs.  Watch for shadowing: `$MS_SCRIPT_DIR`
comes first, so a file named after an engine module overrides it, and the
failure surfaces somewhere unrelated.

**After it — everything a program does.**  `import` searches `env.importPaths`,
a list of *virtual* paths, default `[".", "/usr/lib", "/sys/lib"]` (`"."` is the
virtual cwd) — Mini Micro 1's convention, and the shell seeds it in
`Shell._makeEnv`.  Nothing else is searched: `<assets>/lib` is not a disk, so a
user program cannot import the engine layer's *source*, only use the modules the
shell already seeded into its globals.  The list is live rather than frozen,
because a virtual path cannot name anything outside the mounts anyway.

Since it is read from the calling VM's `env`, a child interpreter searches its
own — and a VM whose `env` is still the host intrinsic rather than a map cannot
import at all.  That is fine for `main.ms`, which does all its importing above
the latch, and would bite anything that tried to import below it.

### The screen rect and the bezel
The window is 1024x768; the Mini Micro screen is the 960x640 area inside the
bezel image, at (32, 34).  `Display.screenLeft/screenTop/screenWidth/screenHeight`
carry that; displays size and position themselves against those, never against
`GetScreenWidth`/`GetScreenHeight`.  `_update` wraps `Display.RenderAll` in a
`BeginMode2D` camera that translates by the rect's top-left, and `mouse.update`
applies the inverse.  The bezel's insets are not symmetrical (thicker at the
bottom, for the logo), so anything that centers itself must center on the rect.

Keep the `BeginMode2D` bracket tight around `RenderAll`: `PixelDisplay._beginDraw`
and `ttFonts` call `BeginTextureMode`, which would bake the camera matrix into a
render texture.

### Display conventions (unchanged from Mini Micro)
- **Bottom-up coordinates**: row 0 / y=0 at the bottom
- **68x26 character grid**, 14px column spacing, 24px row spacing
- **Layers 7→0 rendered**, so 0 is on top
- Cell `backColor` defaults to transparent, not black

### Property setters
Mini Micro properties that react to assignment (`.mode`, `.row`, `.column`,
`.extent`, a Sound's synthesis parameters) work by assignment, via MiniScript
2 property setters (a `"x="` member) in the Soda lib.  The old stand-in
methods -- `setMode`, `setCursor`, `setExtent` -- are gone.

## Code Style
- Tabs for indentation
- Concise; minimal comments, and comments say *why*, not *what*
- Don't add emojis unless requested

## Current Status
- ✅ Host boots `assets/main.ms`; window, bezel, screen rect, camera offset
- ✅ Displays, screen font, input via the shared engine layer
- ✅ The Mini Micro shell (`assets/mm/`): `Console.ms` (line editing) and
  `Shell.ms` (the REPL) work.  The shell runs everything in a child `Interp`
  (a host class; see `../raylib-miniscript/notes/HOSTING_MS.md`) seeded from
  our globals, stepped one 30 ms slice per frame.
- ⏳ Shell: running a program (see below), autocomplete, editor, file browser
- ✅ File system: `/hw` and `/sys` mounted read-only at boot; `file.enterSandbox`
  latched at the end of `main.ms`
- ✅ File system: `/usr` and `/usr2` mountable by drag and drop, remembered in
  prefs; ⏳ native file picker, ⏳ `.minidisk` (zip) disks
- ⏳ Packaging: per-platform app bundles

## Running a program: what boot still needs

Mini Micro's own boot is `/sys/startup.ms`, and almost everything a user thinks
of as the shell — `load`, `run`, `save`, `source`, `clear`, `reset`, `welcome` —
is defined there, not in `mm/`.  Mini Micro 1 runs it through the REPL so those
land in globals, then runs `/usr/startup.ms` as a *program* if the disk has one
(`Shell.cs`, `Start()`).  We do the same: `interp.loadKeepingGlobals` for both,
since it is global scope either way.

The shell's half of this already exists — `_childRun` sets `req.action = "run"`
and `_serveRequest` reloads the child from `_source`.  What is missing is
everything `/sys/startup.ms` reaches for that we do not yet provide:

- Host intrinsics MM1 has and we do not: `_fileReadLines`, `_startupChime`,
  `_resetEditorScrollPos` (`Shell.cs`, `MiniMicroAPI.cs`).  The first two are
  small; the third can be a stub until the editor lands.
- `env.cmdLineArgs`, `env.bootOpts`, and `version.buildDate`.
- `http.get` — the host has only `http.post`.  Needed by `loadCodeFromURL`,
  not by boot, so it can come later.
- **MS2 assignment gotchas in the sysdisk itself**: `clear` and `welcome` use
  `display(i).mode = ...` and `text.row = 25`, which silently do nothing here.
  About ten lines, all in `startup.ms`.  Fixing them means editing
  minimicro-sysdisk, which Mini Micro 1 also ships — so either the change has to
  work in both, or the two disks fork.  Unresolved; ask before touching it.

## Reference Files to Check
When implementing a Mini Micro feature, check the Unity version first:
`.../MiniMicro/Assets/Scripts/` — `Shell.cs`, `Console.cs`, `TextDisplay.cs`,
`ScreenFont.cs`.
