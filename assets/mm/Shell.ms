// Shell: the Mini Micro command line.
//
// The port of Mini Micro 1's Shell.cs, and the other half of Console.ms: the
// console turns keystrokes into a line of text, and the shell decides what a
// committed line means.
//
// The piece that cannot be MiniScript is compiling and running MiniScript, and
// the host provides exactly that and nothing more -- the `Interp` class, a
// handle on a second interpreter we seed, feed lines to, and step one time
// slice per frame.  See ../../raylib-miniscript/notes/HOSTING_MS.md.
//
// Everything a user program can see lives in that child: its globals are a
// copy of ours made at boot, so the values (text, gfx, key, ...) are the same
// heap objects and shared state is genuinely shared, but a program that
// rebinds a name -- or dies with an error -- cannot disturb the shell itself.
// Mini Micro 1 has no such boundary; the shell and user code share one globals
// map and live with the consequences.

import "importUtil"
ensureImport ["Console", "key"]

_EOL = char(13)
_TAB = char(9)

// The one shell, for the callbacks the console invokes with itself as `self`.
_theShell = null

//----------------------------------------------------------------------
// Functions seeded into the child, shadowing intrinsics of the same name.
//
// These are compiled here but *run* in the child's VM, so their free variables
// -- text, _req -- resolve in the child's globals, not ours.  That is what
// makes them work at all: `text` is whatever the running program has made it.
//----------------------------------------------------------------------

// print to the text display, rather than to the host's stdout.
_childPrint = function(s="", delimiter=null)
	if s isa list then s = s.join(" ")
	text.print s, delimiter
end function

// yield hands the frame back to the shell, which is where drawing belongs --
// so unlike the shell's own `yield`, it must NOT render a frame itself.
_childYield = @intrinsics.yield

_childWait = function(duration=1)
	endTime = time + duration
	while time < endTime
		yield
	end while
end function

// input needs no host support: set a flag on the request map and yield.  The
// shell -- still running, frame after frame -- runs the line editor for as long
// as it takes and drops the answer back in the map.
_childInput = function(prompt="")
	_req.result = null
	_req.prompt = prompt
	_req.action = "input"
	while _req.action
		yield
	end while
	return _req.result
end function

// The hooks /sys/startup.ms calls: in Mini Micro 1 these were intrinsics that
// set a flag on the host, and here they are the same thing with the request
// map standing in for the host.
_childRun = function
	_req.action = "run"
	yield
end function

_childEdit = function
	_req.action = "edit"
	yield
end function

// Host intrinsics /sys/startup.ms expects, which Mini Micro 1 provides from
// Shell.cs and MiniMicroAPI.cs.  Ours are shims: the file module already does
// the real work, and the editor does not exist yet.
_childFileReadLines = @file.readLines

_childResetEditorScrollPos = function
end function

// The boot chime belongs to /sys/startup.ms (it is under env.bootOpts there),
// so main.ms loads the sound but does not play it.  Nested, because a function
// seeded into the child resolves its free variables in the *child's* globals,
// where the sound deliberately is not -- only a closure can carry it across.
_makeStartupChime = function(snd)
	return function
		if snd != null then raylib.PlaySound snd
	end function
end function

// Names the shell keeps to itself.  Seeding copies our whole globals map, which
// is the point -- the child gets the entire library layer -- but it would also
// hand a user program the shell's own console, interpreter, and boot-time
// resources.  So they are filtered out of the seed rather than seeded and then
// cleared: the Interp API has setGlobal but no removeGlobal, and setting them
// to null would leave sixteen junk names in the child's globals -- visible to
// `globals`, to pprint, and to the snapshot /sys/startup.ms takes for `wtf`.
_privateNames = ["shell", "console", "bootDir", "bootupSound", "bezelTexture",
   "bezelColor", "stickerTexture", "diskInsertedSound", "diskEjectedSound",
   "screenCamera", "updateCallbacks", "_update", "_handleDrops",
   "_consoleUpdate", "Console", "Shell"]

//----------------------------------------------------------------------

Shell = {}

Shell.console = null
Shell.interp = null			// the child Interp we run everything in
Shell.env = null			// the `env` map, shared with the child
Shell.req = null			// the request map, ditto
Shell.bootChime = null		// sound for _startupChime; loaded by main.ms

Shell._errShown = false		// interp.error survives until the next line; print it once
Shell._exiting = false
Shell._bootStage = 0		// 0: /sys/startup.ms, 1: /usr/startup.ms, 2: at the prompt

Shell.Make = function(console, bootChime=null)
	noob = new Shell
	noob.console = console
	noob.bootChime = bootChime
	noob.env = Shell._makeEnv
	noob.req = {"action": null, "prompt": "", "result": null}
	console.controlCHandler = @_controlCHandler
	outer._theShell = noob
	noob.reset
	return noob
end function

Shell._makeEnv = function
	usrMounted = file.exists("/usr")
	env = {}
	if usrMounted then env.curdir = "/usr" else env.curdir = "/sys/demo"
	env.home = "/usr"
	env.prompt = "]"
	env.morePrompt = "...]"
	env.shell = ""
	env.importPaths = [".", "/usr/lib", "/sys/lib"]
	// Read by /sys/startup.ms's _startup.  cmdLineArgs is empty because the host
	// does not hand argv to script at all yet; bootOpts is the hook for turning
	// the chime and the welcome banner off.
	env.cmdLineArgs = []
	env.bootOpts = {}
	return env
end function

// Build (or rebuild) the child interpreter and seed it with our globals.
Shell.reset = function
	if self.interp != null then
		self.interp.stop
		self.interp.dispose
	end if
	self.interp = Interp.create
	seed = {}
	for kv in globals
		if _privateNames.indexOf(kv.key) == null then seed[kv.key] = @kv.value
	end for
	self.interp.setGlobals seed
	self.interp.setGlobal "env", self.env
	self.interp.setGlobal "_req", self.req
	self.interp.setGlobal "print", @_childPrint
	self.interp.setGlobal "input", @_childInput
	self.interp.setGlobal "yield", @_childYield
	self.interp.setGlobal "wait", @_childWait
	self.interp.setGlobal "_run", @_childRun
	self.interp.setGlobal "_edit", @_childEdit
	self.interp.setGlobal "_fileReadLines", @_childFileReadLines
	self.interp.setGlobal "_resetEditorScrollPos", @_childResetEditorScrollPos
	self.interp.setGlobal "_startupChime", _makeStartupChime(self.bootChime)
	self._errShown = false
end function

Shell.display = function
	return self.console.display
end function

Shell.printLine = function(s="")
	self.console.display.print s
end function

//----------------------------------------------------------------------
// The frame loop
//----------------------------------------------------------------------

Shell.run = function
	while not self._exiting
		self.update
		yield
	end while
end function

// One frame of shell.  Mirrors Shell.cs's Update: whatever state we are in,
// this returns promptly, and the caller draws the frame.
Shell.update = function
	con = self.console

	// A committed line goes to whoever was waiting for one.
	if con.lineReady then
		self._handleLine con.takeLine
		return
	end if

	if self.req.action then
		self._serveRequest
	else if not self.interp.done then
		self.interp.runUntilDone 0.03
		self._afterSlice
	else if self._bootStage < 2 then
		self._nextBootStage
	else if not con.inputInProgress then
		self._startPrompt
	end if
end function

//----------------------------------------------------------------------
// Boot
//----------------------------------------------------------------------

// Two startup scripts, in Mini Micro 1's order (Shell.cs, Start()):
//
//   /sys/startup.ms   the rest of the shell, really -- load, run, save, source,
//                     clear, reset and welcome are all defined there, not here.
//   /usr/startup.ms   the user's, run as a program if their disk has one.
//
// Both are global-scope code in the child, so both go through the same call;
// neither can be run inline, since either may yield, wait, or ask for input,
// and the frame loop is what keeps the screen alive while it does.
Shell._nextBootStage = function
	stage = self._bootStage
	self._bootStage = stage + 1
	if stage == 0 then
		self._loadFile "/sys/startup.ms"
	else if stage == 1 then
		self._loadFile "/usr/startup.ms"
	end if
end function

// Hand the child a whole file to run, keeping its globals -- which is the point
// for /sys/startup.ms, whose whole job is to define them.  Missing is not an
// error: /usr may be unmounted, or simply have no startup script.
Shell._loadFile = function(path)
	if not file.exists(path) then return
	lines = file.readLines(path)
	if lines == null then
		self.printLine "Unable to read " + path
		return
	end if
	self._errShown = false
	self.interp.loadKeepingGlobals lines.join(char(10))
	self._afterSlice
end function

Shell._handleLine = function(line)
	if self.req.action == "input" then
		self.req.result = line
		self.req.action = null
		return
	end if
	self._errShown = false
	self.interp.replLine line, 0.05
	self._afterSlice
end function

// Drain whatever the child produced, and report an error if it hit one.  Called
// after every slice; both are cheap when there is nothing to say.
Shell._afterSlice = function
	out = self.interp.takeOutput
	if out != null then
		// The capture buffer marks line ends with \n; the display wants its own
		// delimiter, and a trailing one would double up with the print below.
		if out[-1] == char(10) then out = out[:-1]
		for line in out.split(char(10))
			self.printLine line
		end for
	end if

	err = self.interp.error
	if err == null then
		self._errShown = false
	else if not self._errShown then
		self._errShown = true
		self.printLine err
		trace = self.interp.stackTrace
		if trace then
			for line in trace
				self.printLine _TAB + line
			end for
		end if
	end if
end function

Shell._startPrompt = function
	d = self.console.display
	if d.column != 0 then d.nextLine
	if self.interp.needMoreInput then
		d.print self.env.morePrompt, ""
	else
		d.print self.env.prompt, ""
	end if
	self.console.startInput
end function

// Act on whatever the child asked for by setting req.action and yielding.
Shell._serveRequest = function
	action = self.req.action

	if action == "input" then
		// Stay in this state until the line is committed; _handleLine above is
		// what ends it.
		if not self.console.inputInProgress then
			if self.req.prompt != "" then self.console.display.print self.req.prompt, ""
			self.console.startInput
		end if
		return
	end if

	self.req.action = null

	if action == "run" then
		src = self.interp.getGlobal("_source")
		if src isa list then src = src.join(_EOL)
		if src == null then src = ""
		self._errShown = false
		// Keep the globals: a program's variables are still there at the prompt
		// when it ends, which is how Mini Micro has always worked.
		self.interp.loadKeepingGlobals src
		self._afterSlice
	else if action == "edit" then
		self.printLine "The editor is not implemented yet."
	end if
end function

//----------------------------------------------------------------------
// Break
//----------------------------------------------------------------------

// Control-C.  The console calls this with itself as self, so it can only be a
// plain function; the shell it belongs to is the module-level one.
_controlCHandler = function
	return _theShell.doBreak
end function

// (Shell.cs calls this Break; `break` is a keyword here, so it cannot be a
// member name.)
Shell.doBreak = function(silent=false)
	wasRunning = not self.interp.done or self.req.action != null
	self.interp.stop
	self.console.abortInput
	key.clear
	self.req.action = null
	self._errShown = true		// a stopped program is not an error to report
	if wasRunning and not silent then
		d = self.console.display
		if d.column != 0 then d.nextLine
		self.printLine "BREAK"
	end if
	return true
end function

//----------------------------------------------------------------------

if locals == globals then
	print "Shell.ms is not a standalone program; import it from main.ms."
	exit
else
	return Shell
end if
