// Console: line editing on top of a TextDisplay.
//
// The display knows how to put characters on a grid; the console is what turns
// a stream of keystrokes into an edited line of text.  It owns the key buffer,
// the input line, command history, autocomplete, and mouse selection.
//
// Ported from Mini Micro 1's Console.cs.  Two things differ:
//
//   * Key repeat comes from raylib (IsKeyPressedRepeat) rather than the hand-
//     rolled timing table the Unity InputSystem forced on us.
//   * The key buffer IS key.keyQueue, so key.available/key.get see exactly the
//     keys the console has collected.  Whoever calls Console.update every frame
//     must therefore NOT also call key.update, or every key arrives twice.

import "importUtil"
ensureImport ["Display", "TextDisplay", "color", "key", "mouse"]

rl = raylib

// Character codes the console acts on.  These are the codes lib/key.ms already
// synthesizes for the non-printing keys, which is not a coincidence: both
// tables come from Mini Micro 1.
CTRL_A = 1			// also Home: start of line
CTRL_C = 3
CTRL_E = 5			// also End: end of line
BACKSPACE = 8
TAB = 9
LF = 10
CTRL_K = 11			// delete to end of line
CR = 13
LEFT = 17
RIGHT = 18
UP = 19
DOWN = 20
CTRL_U = 21			// delete to start of line
CTRL_V = 22
ESCAPE = 27
FWD_DELETE = 127

// Keys raylib does not report through GetCharPressed, and the code we want
// each to produce.  Polled with repeat, so holding one autorepeats.
_specialKeys = {}
_specialKeys[rl.KEY_BACKSPACE] = BACKSPACE
_specialKeys[rl.KEY_DELETE] = FWD_DELETE
_specialKeys[rl.KEY_LEFT] = LEFT
_specialKeys[rl.KEY_RIGHT] = RIGHT
_specialKeys[rl.KEY_UP] = UP
_specialKeys[rl.KEY_DOWN] = DOWN
_specialKeys[rl.KEY_HOME] = CTRL_A
_specialKeys[rl.KEY_END] = CTRL_E
_specialKeys[rl.KEY_TAB] = TAB
_specialKeys[rl.KEY_ESCAPE] = ESCAPE
_specialKeys[rl.KEY_ENTER] = LF
_specialKeys[rl.KEY_KP_ENTER] = LF

// Control chords: raylib key code -> the control character it produces.  We
// have to poll raylib for these because control chords never reach
// GetCharPressed, and we cannot assume KEY_A+i is the key that types the i'th
// letter -- raylib names keys by physical US-QWERTY position, so on Dvorak
// that would make control-E arrive as control-D.  The key module already knows
// where each letter really sits.
_buildCtrlChords = function
	result = {}
	for i in range(0, 25)
		keyCode = key.codeForName(char(97 + i))
		if keyCode != null then result[keyCode] = i + 1		// "a" -> 1
	end for
	return result
end function

_ctrlChords = _buildCtrlChords
_copyKey = key.codeForName("c")
_pasteKey = key.codeForName("v")

_tokenChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"

// What counts as part of a "word" for option-arrow and option-delete.
_isTokenChar = function(c)
	return _tokenChars.indexOf(c) != null
end function

Console = {}

Console.display = null			// the TextDisplay we edit in
Console.keyBuffer = null		// keys pressed but not yet consumed
Console.history = null			// past committed inputs
Console.mouseSelectionEnabled = true

// Callbacks.  Assign a function reference (with @); test with @, too, or
// reading the field would call it.
Console.onInputChanged = null		// f(inputBuf): the line was edited
Console.onInputDone = null			// f(inputBuf): the line was committed
Console.autocompleteCallback = null	// f(partial) -> completion, or null
Console.controlCHandler = null		// f() -> true if control-C was consumed

Console._inInputMode = false
Console._inputStartRow = 0		// where on the screen this input line begins
Console._inputStartCol = 0
Console._inputBuf = ""
Console._inputIndex = 0			// cursor position within _inputBuf
Console._suggestion = null		// faded text shown ahead of the cursor
Console._historyIndex = 0
Console._blinkStart = 0
Console._lineReady = false		// a committed line is waiting to be taken

Console._selecting = false		// mouse is dragging out a selection
Console._hasSelection = false
Console._selStart = null		// [column, row]
Console._selEnd = null
Console._mouseWasDown = false
Console._mouseDownX = 0
Console._mouseDownY = 0

Console._beepSound = null

// Make a console driving the given TextDisplay (the main text display by
// default).  The key buffer is shared with the key module; see the note at
// the top of this file.
Console.Make = function(display=null)
	noob = new Console
	if display == null then display = globals.text
	noob.display = display
	noob.history = []
	noob.keyBuffer = key.keyQueue
	return noob
end function

//----------------------------------------------------------------------
// Per-frame update
//----------------------------------------------------------------------

// Call once per frame, in place of key.update.
Console.update = function
	self._pollKeys
	while self._inInputMode and self.keyBuffer
		self.handleKey self.keyBuffer.pull
	end while
	if self._inInputMode then
		self._updateSelection
		self._blinkCursor
	end if
end function

Console._pollKeys = function
	ctrl = key.pressed("left ctrl") or key.pressed("right ctrl")
	cmd = key.pressed("left cmd") or key.pressed("right cmd")

	for keyCode in _specialKeys.indexes
		if rl.IsKeyPressed(keyCode) or rl.IsKeyPressedRepeat(keyCode) then
			self.keyBuffer.push char(_specialKeys[keyCode])
		end if
	end for

	if ctrl then
		for keyCode in _ctrlChords.indexes
			if not (rl.IsKeyPressed(keyCode) or rl.IsKeyPressedRepeat(keyCode)) then continue
			code = _ctrlChords[keyCode]
			if code == CTRL_C and self._handleControlC then continue
			self.keyBuffer.push char(code)
		end for
	end if

	// Command chords: only the two clipboard ones, and only on the press.
	if cmd then
		if _copyKey != null and rl.IsKeyPressed(_copyKey) then self.doCopy
		if _pasteKey != null and rl.IsKeyPressed(_pasteKey) then self.doPaste
	end if

	// Everything printable.  Skip it while a modifier is down: the chord was
	// already handled above, and some platforms deliver a character for it too.
	while true
		code = rl.GetCharPressed
		if code == 0 then break
		if ctrl or cmd then continue
		self.keyBuffer.push char(code)
	end while
end function

// Returns true if control-C was consumed here and should not reach the input
// line.  A selection makes it a copy; otherwise it is the break key, which
// throws away the line in progress before the handler runs.
Console._handleControlC = function
	if self._hasSelection then
		self.doCopy
		return true
	end if
	if @self.controlCHandler == null then return false
	self._inputBuf = ""
	self.abortInput
	return self.controlCHandler
end function

//----------------------------------------------------------------------
// Input mode
//----------------------------------------------------------------------

Console.inputInProgress = function
	return self._inInputMode
end function

Console.startInput = function
	d = self.display
	self._lineReady = false
	self._clearSelection
	self._inputStartRow = d.row
	self._inputStartCol = d.column
	self._inputBuf = ""
	self._inputIndex = 0
	self._suggestion = null
	self._inInputMode = true
	self._historyIndex = self.history.len
	self._setCursorForInput
	if @self.onInputChanged != null then self.onInputChanged self._inputBuf
end function

Console.commitInput = function
	self._clearSelection
	self._inputIndex = self._inputBuf.len
	self._setCursorForInput false
	last = null
	if self.history then last = self.history[-1]
	if self._inputBuf != "" and self._inputBuf != last then self.history.push self._inputBuf
	self.display.hideCursor
	self.display.nextLine
	self._inInputMode = false
	self._lineReady = true
	if @self.onInputDone != null then self.onInputDone self._inputBuf
end function

Console.abortInput = function
	self._inInputMode = false
	self._lineReady = false
	self.display.hideCursor
end function

// The non-blocking counterpart of inputLine, for a shell that owns the frame
// loop: ask every frame whether a line has been committed, and take it.
Console.lineReady = function
	return self._lineReady
end function

Console.takeLine = function
	self._lineReady = false
	return self._inputBuf
end function

Console.addToHistory = function(input)
	self.history.push input
end function

// Read one line, blocking (but yielding) until it is committed.  This is the
// form the REPL and the `input` intrinsic want; everything else here is the
// machinery underneath it.
Console.inputLine = function(prompt="")
	if prompt != "" then self.display.print prompt, ""
	self.startInput
	while self._inInputMode
		yield
	end while
	self._lineReady = false
	return self._inputBuf
end function

// Feed a string in as though it had been typed.
Console.typeInput = function(s)
	for c in s
		self.handleKey c
	end for
end function

//----------------------------------------------------------------------
// The key handler proper
//----------------------------------------------------------------------

Console.handleKey = function(keyChar)
	code = keyChar.code
	if code == CTRL_C and self._handleControlC then return

	// Not taking input?  Then just buffer the key for whoever is.
	if not self._inInputMode then
		self.keyBuffer.push keyChar
		return
	end if

	d = self.display
	byWord = key.pressed("left alt") or key.pressed("right alt") or
	   key.pressed("left ctrl") or key.pressed("right ctrl")

	d.hideCursor
	if code != TAB then self._clearAutocomplete
	changed = false

	if code == CTRL_C or code == LF or code == CR then
		self.commitInput
	else if code == LEFT then
		self._inputIndex = self._prevInputStop(self._inputIndex, byWord)
	else if code == RIGHT then
		self._inputIndex = self._nextInputStop(self._inputIndex, byWord)
	else if code == CTRL_A then
		self._inputIndex = 0
	else if code == CTRL_E then
		self._inputIndex = self._inputBuf.len
	else if code == CTRL_K then
		self._replaceInput self._inputBuf[:self._inputIndex]
		changed = true
	else if code == CTRL_U then
		self._replaceInput self._inputBuf[self._inputIndex:]
		self._inputIndex = 0
		changed = true
	else if code == BACKSPACE then
		stop = self._prevInputStop(self._inputIndex, byWord)
		if stop < self._inputIndex then
			delCount = self._inputIndex - stop
			buf = self._inputBuf
			self._inputBuf = buf[:stop] + buf[self._inputIndex:]
			for i in range(1, delCount)
				d.backup
			end for
			self._write self._inputBuf[stop:] + " " * delCount
			self._inputIndex = stop
			changed = true
		end if
	else if code == FWD_DELETE then
		stop = self._nextInputStop(self._inputIndex, byWord)
		if stop > self._inputIndex then
			buf = self._inputBuf
			self._inputBuf = buf[:self._inputIndex] + buf[stop:]
			self._write self._inputBuf[self._inputIndex:] + " " * (stop - self._inputIndex)
			changed = true
		end if
	else if code == UP then
		if self._historyIndex > 0 then
			self._historyIndex -= 1
			self._replaceInput self.history[self._historyIndex]
			changed = true
		end if
	else if code == DOWN then
		if self._historyIndex < self.history.len then
			self._historyIndex += 1
			if self._historyIndex < self.history.len then
				self._replaceInput self.history[self._historyIndex]
			else
				self._replaceInput ""
			end if
			changed = true
		end if
	else if code == TAB then
		if self._suggestion then
			self._inputBuf += self._suggestion
			self._inputIndex += self._suggestion.len
			self._write self._suggestion
			changed = true
		end if
	else if code == CTRL_V then
		self.doPaste
	else if code >= 32 then
		buf = self._inputBuf
		self._inputBuf = buf[:self._inputIndex] + keyChar + buf[self._inputIndex:]
		self._write self._inputBuf[self._inputIndex:]
		self._inputIndex += 1
		changed = true
	end if
	// (Control codes we don't handle -- Escape, and the unassigned control
	// letters -- are dropped rather than inserted as garbage characters.)

	if changed and @self.onInputChanged != null then self.onInputChanged self._inputBuf
	if self._inInputMode then self._setCursorForInput
end function

//----------------------------------------------------------------------
// Drawing the input line
//----------------------------------------------------------------------

// Print into the input area, keeping our idea of where the line starts in
// step with any scrolling the print caused.
Console._write = function(s)
	d = self.display
	mark = d.scrollCount
	d.print s, ""
	self._inputStartRow += d.scrollCount - mark
end function

// Where the cursor belongs, given the input start and the index into the
// buffer.  Long lines wrap onto following (lower-numbered) rows.
Console._cursorRowCol = function
	d = self.display
	row = self._inputStartRow
	col = self._inputStartCol + self._inputIndex
	while col >= d.columns
		row -= 1
		col -= d.columns
	end while
	return [row, col]
end function

Console._setCursorForInput = function(showSuggestion=true)
	d = self.display
	rc = self._cursorRowCol
	d.setCursor rc[0], rc[1]

	self._suggestion = null
	if showSuggestion and @self.autocompleteCallback != null and
	   self._inputIndex == self._inputBuf.len then
		self._suggestion = self.autocompleteCallback(self._inputBuf)
	end if
	if self._suggestion then
		saveColor = d.color
		d.color = color.lerp(d.color, d.backColor, 0.75)
		self._write self._suggestion
		d.color = saveColor
		rc = self._cursorRowCol		// (again: printing may have scrolled)
		d.setCursor rc[0], rc[1]
	end if

	d.showCursor
	self._blinkStart = time
end function

// Erase the faded suggestion, leaving the cursor where it was.
Console._clearAutocomplete = function
	if not self._suggestion then return
	d = self.display
	row = d.row
	col = d.column
	self._write " " * self._suggestion.len
	self._suggestion = null
	d.setCursor row, col
end function

// Wipe the current input line off the screen and draw a new one in its place.
Console._replaceInput = function(newInput)
	d = self.display
	d.setCursor self._inputStartRow, self._inputStartCol
	self._write " " * self._inputBuf.len
	self._inputBuf = newInput
	d.setCursor self._inputStartRow, self._inputStartCol
	self._write self._inputBuf
	self._inputIndex = self._inputBuf.len
end function

// The display's cursor is a solid inverted cell; blinking it is our job.
Console._blinkCursor = function
	d = self.display
	if not d.cursorShown then return
	period = d.cursorOnTime + d.cursorOffTime
	// Through the display's own show/hide rather than poking the cell: those
	// keep the cursor's color in step with text.color, so a color changed while
	// the cursor is just sitting at the prompt takes effect on the next frame
	// rather than at the next `clear`.
	if (time - self._blinkStart) % period < d.cursorOnTime then
		d._showCursorVisual
	else
		d._hideCursorVisual
	end if
end function

//----------------------------------------------------------------------
// Moving by character or by word
//----------------------------------------------------------------------

Console._prevInputStop = function(index, byWord=false)
	if index <= 0 then return index
	index -= 1
	if not byWord then return index
	// Back over any nonword characters, then over the word itself.
	while index > 0 and not _isTokenChar(self._inputBuf[index])
		index -= 1
	end while
	while index > 0 and _isTokenChar(self._inputBuf[index-1])
		index -= 1
	end while
	return index
end function

Console._nextInputStop = function(index, byWord=false)
	maxIndex = self._inputBuf.len
	if index >= maxIndex then return index
	index += 1
	if not byWord then return index
	while index < maxIndex and not _isTokenChar(self._inputBuf[index])
		index += 1
	end while
	while index < maxIndex and _isTokenChar(self._inputBuf[index-1])
		index += 1
	end while
	return index
end function

//----------------------------------------------------------------------
// Mouse selection and the clipboard
//----------------------------------------------------------------------

Console.enableMouseSelection = function(enableIt=true)
	self.mouseSelectionEnabled = enableIt
	if not enableIt then self._clearSelection
end function

Console.doCopy = function
	if not self._hasSelection then return
	rl.SetClipboardText self._textInRange(self._selStart, self._selEnd)
end function

Console.doPaste = function
	clip = rl.GetClipboardText
	if clip == null then return
	for c in clip
		self.handleKey c
	end for
end function

// Screen pixel position (mouse coordinates: bottom-up, origin at the bottom
// left of the screen rect) to [column, row].  Not clamped: callers use the
// out-of-range result to tell that a click missed the grid.
Console._rowColForXY = function(x, y)
	d = self.display
	col = floor((x - d.offsetX) / d.colSpacing)
	// offsetY measures down from the top of the screen, so flip y first.
	row = d.rows - 1 - floor((Display.screenHeight - y - d.offsetY) / d.rowSpacing)
	return [col, row]
end function

Console._clampRowCol = function(colRow)
	d = self.display
	col = colRow[0]
	row = colRow[1]
	if col < 0 then col = 0
	if col > d.columns then col = d.columns
	if row < 0 then row = 0
	if row > d.rows - 1 then row = d.rows - 1
	return [col, row]
end function

Console._updateSelection = function
	if not self.mouseSelectionEnabled then return
	if not mouse.button then
		self._mouseWasDown = false
		self._selecting = false
		return
	end if

	if not self._mouseWasDown then
		self._mouseWasDown = true
		self._clearSelection
		d = self.display
		p = self._rowColForXY(mouse.x, mouse.y)
		self._selStart = p
		self._selEnd = p
		self._mouseDownX = mouse.x
		self._mouseDownY = mouse.y
		self._selecting = p[0] >= 0 and p[0] < d.columns and p[1] >= 0 and p[1] < d.rows
		return
	end if

	if not self._selecting then return
	// Ignore the jitter of an ordinary click; a real drag has to travel.
	dx = mouse.x - self._mouseDownX
	dy = mouse.y - self._mouseDownY
	if dx*dx + dy*dy < 100 then
		self._clearSelectionVisual
		self._selEnd = self._selStart
		return
	end if
	newEnd = self._clampRowCol(self._rowColForXY(mouse.x, mouse.y))
	if newEnd[0] != self._selEnd[0] or newEnd[1] != self._selEnd[1] then
		self._setSelection self._selStart, newEnd
	end if
end function

Console._setSelection = function(startPos, endPos)
	if self._hasSelection then self._invertRange self._selStart, self._selEnd
	self._selStart = startPos
	self._selEnd = endPos
	self._invertRange startPos, endPos
	self._hasSelection = true
end function

Console._clearSelectionVisual = function
	if not self._hasSelection then return
	self._invertRange self._selStart, self._selEnd
	self._hasSelection = false
end function

Console._clearSelection = function
	self._clearSelectionVisual
	self._selecting = false
end function

// Put the two ends in reading order: earlier means a higher row (row 0 is the
// bottom), or the same row and a lower column.
Console._orderRange = function(startPos, endPos)
	if startPos[1] < endPos[1] or (startPos[1] == endPos[1] and startPos[0] > endPos[0]) then
		return [endPos, startPos]
	end if
	return [startPos, endPos]
end function

Console._invertRange = function(startPos, endPos)
	d = self.display
	ends = self._orderRange(startPos, endPos)
	col = ends[0][0]
	row = ends[0][1]
	while row >= 0 and (col != ends[1][0] or row != ends[1][1])
		c = d._cellAt(row, col)
		if c != null then c.inverse = not c.inverse
		col += 1
		if col >= d.columns then
			col = 0
			row -= 1
		end if
	end while
end function

Console._textInRange = function(startPos, endPos)
	d = self.display
	ends = self._orderRange(startPos, endPos)
	col = ends[0][0]
	row = ends[0][1]
	result = []
	pending = 0		// spaces seen but not yet committed
	while row >= 0 and (col != ends[1][0] or row != ends[1][1])
		c = d._cellAt(row, col)
		if c == null or c.character == " " then
			// Hold trailing spaces back; they get dropped at a line end.
			pending += 1
		else
			if pending then result.push " " * pending
			result.push c.character
			pending = 0
		end if
		col += 1
		if col >= d.columns then
			col = 0
			row -= 1
			result.push char(10)
			pending = 0
		end if
	end while
	return result.join("")
end function

//----------------------------------------------------------------------

Console.beep = function
	if self._beepSound == null then self._beepSound = rl.LoadSound("/hw/sounds/beep-single.wav")
	rl.PlaySound self._beepSound
end function

if locals == globals then
	ensureImport "qa"

	c = Console.Make(TextDisplay.Make)

	print "the control chords cover all 26 letters, whatever the layout"
	found = {}
	for kv in _ctrlChords
		qa.assert not found.hasIndex(kv.value), "two keys claim control-" + char(64 + kv.value)
		found[kv.value] = kv.key
	end for
	for i in range(1, 26)
		qa.assert found.hasIndex(i), "no key produces control-" + char(64 + i)
	end for
	qa.assertEqual _copyKey, found[CTRL_C], "the copy key is the one that types c"
	qa.assertEqual _pasteKey, found[CTRL_V], "the paste key is the one that types v"

	print "word motion skips nonword characters, then the word"
	c._inputBuf = "print foo.bar"
	qa.assertEqual c._prevInputStop(13, true), 10, "back by word from the end"
	qa.assertEqual c._prevInputStop(10, true), 6, "back by word over the dot"
	qa.assertEqual c._prevInputStop(6, true), 0, "back by word to the start"
	qa.assertEqual c._prevInputStop(0, true), 0, "back by word at the start stays put"
	qa.assertEqual c._prevInputStop(13, false), 12, "back by character"
	qa.assertEqual c._nextInputStop(0, true), 6, "forward by word"
	qa.assertEqual c._nextInputStop(13, true), 13, "forward by word at the end stays put"
	qa.assertEqual c._nextInputStop(0, false), 1, "forward by character"

	print "editing keeps the buffer and the screen in step"
	c.startInput
	c.typeInput "hello world"
	qa.assertEqual c._inputBuf, "hello world", "typed text lands in the buffer"
	qa.assertEqual c._inputIndex, 11, "cursor sits past the text"
	c.handleKey char(1)			// control-A: start of line
	qa.assertEqual c._inputIndex, 0, "control-A homes the cursor"
	c.typeInput "say "
	qa.assertEqual c._inputBuf, "say hello world", "insertion happens at the cursor"
	c.handleKey char(11)		// control-K: delete to end of line
	qa.assertEqual c._inputBuf, "say ", "control-K cuts to the end of the line"
	c.handleKey char(8)			// backspace
	qa.assertEqual c._inputBuf, "say", "backspace removes one character"
	row = c.display.row
	col = c.display.column
	qa.assertEqual col, 3, "the display cursor tracks the input index"

	print "committing files the line away in history"
	c.handleKey char(13)
	qa.assert not c.inputInProgress, "return should end input mode"
	qa.assertEqual c.history, ["say"], "the committed line should be in history"

	print "history recall replaces the input line"
	c.startInput
	c.typeInput "x"
	c.handleKey char(19)		// up arrow
	qa.assertEqual c._inputBuf, "say", "up arrow recalls the previous entry"
	c.handleKey char(20)		// down arrow
	qa.assertEqual c._inputBuf, "", "down arrow past the end clears the line"
	c.abortInput

	print "All Console tests passed!"
	exit
else
	return Console
end if
