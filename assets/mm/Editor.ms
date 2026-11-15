// Editor: the code editor's core -- the buffer, cursor and selection, undo,
// keyboard and mouse handling, and drawing.  A port of Mini Micro 1's
// CodeEditor.cs, drawing straight to raylib rather than through a display.
//
// What kind of file this is lives entirely in the mode (see TextMode.ms).  The
// editor caches each line's tokens and the state it ends in; an edit clears
// the cache for that line and the next, and re-styling carries on down only
// while a line's end state keeps changing.
//
// Positions are [line, index]: index counts characters, not screen columns,
// since a tab spans several columns.

import "importUtil"
ensureImport ["Display", "key"]
import "TextMode"
import "MiniScriptMode"
import "EditorUI"

rl = raylib

// The mode for each file extension.  Kept here rather than in TextMode,
// because import runs a module afresh each time: every mode gets its own
// copy of TextMode, so a registry there would be split among them.
_modeByExt = {"ms": MiniScriptMode}

modeForPath = function(path)
	parts = path.split("/")[-1].split(".")
	if parts.len > 1 and _modeByExt.hasIndex(parts[-1].lower) then
		return _modeByExt[parts[-1].lower]
	end if
	return TextMode
end function

TAB = char(9)
LF = char(10)

// MiniMicro-Regular scales by ascent-descent (942 font units), so size 22
// gives 13-pixel cells, the same pitch Mini Micro 1's editor had.
_codeSize = 22
_numSize = 17
_smallSize = 15
_codeFont = null
_numFont = null
_smallFont = null

// The glyphs MiniMicro-Regular has (from its cmap); raylib loads only ASCII
// unless told otherwise.
_codepoints = function
	result = range(32, 126) + range(161, 184) + range(191, 383)
	for r in [[710,711], [728,733], [956,964], [8211,8230], [8482,8482],
	  [8592,8595], [8722,8722], [9744,9746], [9824,9830], [9856,9861]]
		result += range(r[0], r[1])
	end for
	return result
end function

_loadFonts = function(path)
	if _codeFont != null or not rl.IsWindowReady then return
	cps = _codepoints
	outer._codeFont = rl.LoadFontEx(path, _codeSize, cps, cps.len)
	outer._numFont = rl.LoadFontEx(path, _numSize, cps, cps.len)
	outer._smallFont = rl.LoadFontEx(path, _smallSize, cps, cps.len)
	for f in [_codeFont, _numFont, _smallFont]
		rl.SetTextureFilter f.texture, rl.TEXTURE_FILTER_BILINEAR
	end for
end function

// Colors from Mini Micro 1 (CodeStyling.cs and the editor prefab).
theme = {}
theme.background = [226, 226, 226, 255]
theme.toolbar = [196, 197, 196, 255]
theme.text = [45, 45, 45, 255]
theme.lineNumber = [170, 170, 170, 255]
theme.selection = [168, 200, 255, 255]
theme.caret = [0, 0, 0, 255]
theme.scrollTrack = [243, 244, 243, 255]
theme.scrollThumb = [190, 190, 190, 255]
theme.unmatched = [255, 0, 0, 255]
theme.style = {}
theme.style.keyword = [170, 68, 170, 255]
theme.style.number = [68, 170, 68, 255]
theme.style.string = [170, 68, 68, 255]
theme.style.openString = [204, 0, 0, 255]
theme.style.comment = [102, 102, 102, 255]
// Styles drawn slanted.  The font has no italic face, so we shear the
// upright one, as TextMeshPro did for Mini Micro 1.
theme.italic = {"comment": true}
theme.slant = 0.2		// horizontal shift per pixel above the baseline
theme.style.operator = [68, 68, 170, 255]
theme.style.colon = [255, 0, 255, 255]
theme.style.separator = [68, 68, 170, 255]
theme.style.identifier = theme.text
// Brackets rotate through these by nesting depth.
theme.paren = [[0, 0, 204, 255]]
theme.square = [[26, 26, 128, 255]]
theme.brace = [[68, 68, 170, 255]]

_min = function(a, b)
	if a < b then return a else return b
end function

_max = function(a, b)
	if a > b then return a else return b
end function

_clamp = function(x, lo, hi)
	if x < lo then return lo
	if x > hi then return hi
	return x
end function

_blank = function(s)
	for c in s
		if c != " " and c != TAB then return false
	end for
	return true
end function

_lstrip = function(s)
	i = 0
	while i < s.len and (s[i] == " " or s[i] == TAB)
		i += 1
	end while
	return s[i:]
end function

_tabCount = function(s)
	i = 0
	while i < s.len and s[i] == TAB
		i += 1
	end while
	return i
end function

_before = function(a, b)
	return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])
end function

// MM1's IsTokenChar: what option-arrow skips over.  The dot counts only
// within a number.
_isTokenChar = function(c, state)
	if c == "." then return state.numeric
	if "0" <= c <= "9" then
		state.numeric = true
		return true
	end if
	if c <= "/" or ":" <= c <= "@" or "{" <= c <= "~" then return false
	return true
end function

_keyHit = function(k)
	return rl.IsKeyPressed(k) or rl.IsKeyPressedRepeat(k)
end function

//----------------------------------------------------------------------

Editor = {}
Editor.fontPath = "/hw/fonts/MiniMicro-Regular.ttf"
Editor.tabWidth = 4
Editor.undoLimit = 20
Editor.toolbarHeight = 36
Editor.scrollbarSize = 17
Editor.gutterWidth = 57
Editor.lineHeight = 26
Editor.charWidth = 13
Editor.iconDir = "/hw/images/editor/"
Editor.snippetPaths = ["/sys/data/codeSnippets.txt", "/usr/data/codeSnippets.txt"]
// Shared by every editor, so the checkbox stays as it was last left.
// (Mini Micro 1 kept this in its preferences; we do not have those yet.)
Editor.autoSave = true

// lines: the text; path: where it came from, if anywhere; saved: whether the
// text matches what is on disk there.
Editor.Make = function(lines, path=null, saved=true)
	_loadFonts Editor.fontPath
	EditorUI.loadIcons Editor.iconDir
	ui = EditorUI.UI
	if _numFont then
		ui.font = _numFont
		ui.size = _numSize
		ui.charW = rl.MeasureTextEx(_numFont, "M", _numSize, 0).x
		ui.small = _smallFont
		ui.smallSize = _smallSize
		ui.smallW = rl.MeasureTextEx(_smallFont, "M", _smallSize, 0).x
	end if
	noob = new Editor
	if not lines then lines = [""]
	noob.path = path
	if path then noob.mode = modeForPath(path) else noob.mode = MiniScriptMode
	if _codeFont then noob.charWidth = rl.MeasureTextEx(_codeFont, "M", _codeSize, 0).x
	noob.anc = [0, 0]
	noob.pos = [0, 0]
	noob._prefCol = 0
	noob.scrollX = 0
	noob.scrollY = 0
	noob.modified = false		// since the editor opened
	noob.dirty = not saved		// differs from the file on disk
	noob.done = false
	noob.result = null			// "close" or "run", once done
	noob.toolbar = EditorUI.Toolbar.Make
	noob.findPanel = null
	noob.dialog = null
	noob.menu = null
	noob.focus = null			// null for the code, "find" for the find panel
	noob._status = null
	noob._scrollDrag = null
	noob._revertTo = [lines[:], noob.dirty]
	noob._undo = []
	noob._undoPos = -1
	noob._lastEditTime = -99
	noob._caretTime = time
	noob._clickCount = 0
	noob._lastClickTime = -99
	noob._dragging = false
	noob._load lines
	return noob
end function

Editor._load = function(lines)
	self.lines = lines[:]
	self._toks = [null] * lines.len
	self._states = [null] * lines.len
	self._firstDirty = 0
	last = lines.len - 1
	for p in [self.anc, self.pos]
		if p[0] > last then p[0] = last
		if p[1] > lines[p[0]].len then p[1] = lines[p[0]].len
	end for
end function

//----------------------------------------------------------------------
// Line store and style cache
//----------------------------------------------------------------------

Editor._dirty = function(i)
	if i < self.lines.len then self._toks[i] = null
	if i < self._firstDirty then self._firstDirty = i
end function

Editor._setLine = function(i, s)
	self.lines[i] = s
	self._dirty i
end function

// Inserting or removing a line changes the state the line below starts in,
// so that one is re-styled too.
Editor._insertLine = function(i, s)
	self.lines.insert i, s
	self._toks.insert i, null
	self._states.insert i, null
	self._dirty i + 1
	self._dirty i
end function

Editor._removeLine = function(i)
	self.lines.remove i
	self._toks.remove i
	self._states.remove i
	self._dirty i
end function

// Make sure lines 0 through upTo have current tokens.
Editor._ensureStyled = function(upTo)
	if upTo >= self.lines.len then upTo = self.lines.len - 1
	k = self._firstDirty
	if k > upTo then return
	if k == 0 then stateIn = null else stateIn = self._states[k-1]
	carry = false
	toks = self._toks
	states = self._states
	while k <= upTo
		if carry or toks[k] == null then
			r = self.mode.styleLine(self.lines[k], stateIn)
			toks[k] = r[0]
			carry = (r[1] != states[k])
			states[k] = r[1]
		end if
		stateIn = states[k]
		k += 1
	end while
	if carry and k < toks.len then toks[k] = null
	self._firstDirty = k
end function

Editor.tokensAt = function(i)
	self._ensureStyled i
	return self._toks[i]
end function

//----------------------------------------------------------------------
// Selection
//----------------------------------------------------------------------

Editor.hasSelection = function
	return self.anc != self.pos
end function

Editor.selFirst = function
	if _before(self.pos, self.anc) then return self.pos[:]
	return self.anc[:]
end function

Editor.selLast = function
	if _before(self.pos, self.anc) then return self.anc[:]
	return self.pos[:]
end function

Editor.selectedText = function
	a = self.selFirst
	b = self.selLast
	if a[0] == b[0] then return self.lines[a[0]][a[1]:b[1]]
	result = [self.lines[a[0]][a[1]:]]
	for i in range(a[0]+1, b[0]-1, 1)
		result.push self.lines[i]
	end for
	result.push self.lines[b[0]][:b[1]]
	return result.join(LF)
end function

Editor.setSelection = function(a, b)
	last = self.lines.len - 1
	for p in [a, b]
		if p[0] > last then
			p[0] = last
			p[1] = self.lines[last].len
		end if
	end for
	self.anc = a[:]
	self.pos = b[:]
	self.scrollIntoView a
end function

Editor.jumpToLine = function(lineNum)
	lineNum = _clamp(lineNum, 0, self.lines.len - 1)
	self.anc = [lineNum, 0]
	self.pos = [lineNum, 0]
	self.scrollIntoView self.pos, true
end function

//----------------------------------------------------------------------
// Editing
//----------------------------------------------------------------------

Editor._snapshot = function
	return [self.lines[:], self.anc[:], self.pos[:]]
end function

Editor.storeUndo = function
	self._undoPos += 1
	if self._undoPos < self._undo.len then
		self._undo = self._undo[:self._undoPos]
	end if
	self._undo.push self._snapshot
	if self._undo.len > self.undoLimit then
		self._undo.remove 0
		self._undoPos -= 1
	end if
end function

Editor._applyUndo = function(snap)
	self.anc = snap[1][:]
	self.pos = snap[2][:]
	self._load snap[0]
	self.noteEdited
	self.scrollIntoView self.pos
end function

Editor.undo = function
	if self._undoPos < 0 then return
	// At the top of the stack, save where we are, so redo can come back here.
	if self._undoPos == self._undo.len - 1 then self._undo.push self._snapshot
	self._applyUndo self._undo[self._undoPos]
	self._undoPos -= 1
	self._lastEditTime = -99
end function

Editor.redo = function
	if self._undoPos + 2 >= self._undo.len then return
	self._applyUndo self._undo[self._undoPos + 2]
	self._undoPos += 1
	self._lastEditTime = -99
end function

// Replace the selection (or insert at the caret) with s, then reindent.  The
// heart of every edit, as SetSelText was in Mini Micro 1.
Editor.setSelText = function(s)
	s = s.replace(char(13) + LF, LF).replace(char(13), LF)
	// Edits within a second of each other undo together.
	if time - self._lastEditTime > 1 then self.storeUndo
	self._lastEditTime = time

	a = self.selFirst
	b = self.selLast
	if a != b then
		joined = self.lines[a[0]][:a[1]] + self.lines[b[0]][b[1]:]
		i = b[0]
		while i > a[0]
			self._removeLine i
			i -= 1
		end while
		self._setLine a[0], joined
	end if

	p = a
	if s then
		parts = s.split(LF)
		for i in parts.indexes
			cur = self.lines[p[0]]
			if i < parts.len - 1 then
				self._setLine p[0], cur[:p[1]] + parts[i]
				self._insertLine p[0] + 1, cur[p[1]:]
				p = [p[0] + 1, 0]
				// The indenter decides the indentation of every line after the first.
				parts[i+1] = _lstrip(parts[i+1])
			else
				self._setLine p[0], cur[:p[1]] + parts[i] + cur[p[1]:]
				p[1] += parts[i].len
			end if
		end for
	end if
	self.anc = p
	self.pos = p[:]
	self.reindentLines a[0], p[0]
	self.noteEdited
	self._prefCol = self.colAt(self.pos)
	self._caretOn
	self.scrollIntoView self.pos
end function

// Set each line's leading tabs from the lines above it, as MM1's ReindentLines
// did, running on past toLine for as long as lines below come out different.
// (MM1 always went to the end of the file; the result is the same.)
Editor.reindentLines = function(fromLine, toLine)
	mode = self.mode
	if @mode.indentEffect == null then return
	indent = 0
	continued = false
	if fromLine > 0 then
		prev = fromLine - 1
		eff = mode.indentEffect(self.lines[prev], self.tokensAt(prev))
		indent = _tabCount(self.lines[prev]) + eff[1]
		continued = mode.isContinued(self._states[prev])
	end if
	ln = fromLine
	while ln < self.lines.len
		line = self.lines[ln]
		eff = mode.indentEffect(line, self.tokensAt(ln))
		indent -= eff[0]
		if indent < 0 then indent = 0
		if indent > 16 then indent = 16
		body = _lstrip(line)
		want = TAB * indent + body
		if continued then want = TAB * indent + "  " + body
		if want != line then
			delta = want.len - line.len
			for p in [self.anc, self.pos]
				if p[0] == ln then p[1] = _clamp(p[1] + delta, want.len - body.len, want.len)
			end for
			self._setLine ln, want
			self._ensureStyled ln
		else if ln > toLine then
			break
		end if
		indent += eff[1]
		continued = mode.isContinued(self._states[ln])
		ln += 1
	end while
end function

Editor.deleteBack = function
	if self.hasSelection then return self.setSelText("")
	p = self.pos
	if p == [0, 0] then return
	// At or inside the indentation, delete all of it and the line break too.
	tabs = _tabCount(self.lines[p[0]])
	if p[1] <= tabs then
		p[1] = tabs
		if p[0] > 0 then
			self.anc = [p[0] - 1, self.lines[p[0] - 1].len]
		else
			self.anc = [0, 0]
		end if
	else
		self.anc = [p[0], p[1] - 1]
	end if
	self.setSelText ""
end function

Editor.deleteForward = function
	if self.hasSelection then return self.setSelText("")
	p = self.pos
	if p[1] < self.lines[p[0]].len then
		self.anc = [p[0], p[1] + 1]
	else if p[0] < self.lines.len - 1 then
		self.anc = [p[0] + 1, 0]
	else
		return
	end if
	self.setSelText ""
end function

// Shift-Return: a new line, plus the ender for the block we are in (if
// any) below it, with the caret left between them.
Editor.insertWithEnder = function
	self.setSelText LF
	if @self.mode.findEnder == null then return
	ed = self
	tokensFor = function(i)
		return ed.tokensAt(i)
	end function
	ender = self.mode.findEnder(self.lines, @tokensFor, self.pos[0])
	if ender == null then return
	save = self.pos[:]
	self.setSelText LF + ender
	self.anc = save
	self.pos = save[:]
	// Reindenting the ender's line may have moved where the caret belongs.
	self.pos[1] = self.lines[save[0]].len
	self.anc = self.pos[:]
end function

// Tab selects the next _placeholder_ (shift-Tab, the previous one), as in
// MM1, where templates mark the parts to fill in that way.
Editor.handleTab = function(backward)
	start = self.selLast
	if backward then start = self.selFirst
	n = self.lines.len
	lineNum = start[0]
	while 0 <= lineNum < n
		hits = self._placeholders(self.lines[lineNum])
		if backward then
			rev = []
			for h in hits
				rev.insert 0, h
			end for
			hits = rev
		end if
		for h in hits
			if lineNum == start[0] then
				if backward and h[0] >= start[1] then continue
				if not backward and h[0] < start[1] then continue
			end if
			self.setSelection [lineNum, h[0]], [lineNum, h[1]]
			return
		end for
		if backward then lineNum -= 1 else lineNum += 1
	end while
end function

// Spans of \b_\w*_\b in s.
Editor._placeholders = function(s)
	result = []
	isW = @self.mode.isWordChar
	i = 0
	while i < s.len
		if not isW(s[i]) then
			i += 1
			continue
		end if
		j = i
		while j < s.len and isW(s[j])
			j += 1
		end while
		if j - i >= 2 and s[i] == "_" and s[j-1] == "_" then result.push [i, j]
		i = j
	end while
	return result
end function

// Shift the selected lines by whole tabs (cmd-[ and cmd-]).
Editor.indent = function(levels)
	a = self.selFirst
	b = self.selLast
	self.storeUndo
	self._lastEditTime = -99
	for i in range(a[0], b[0])
		s = self.lines[i]
		if levels > 0 then
			s = TAB * levels + s
		else
			for j in range(1, -levels, 1)
				if s and (s[0] == TAB or s[0] == " ") then s = s[1:]
			end for
		end if
		self._setLine i, s
	end for
	self.anc = [a[0], 0]
	self.pos = [b[0], self.lines[b[0]].len]
	self.noteEdited
end function

// Comment out the selected lines, or uncomment them if the first one is
// already a comment (MM1's CodeMenu, cmd-/).
Editor.toggleComment = function
	a = [self.selFirst[0], 0]
	b = self.selLast
	b[1] = self.lines[b[0]].len
	comment = _lstrip(self.lines[a[0]])[:2] != "//"
	out = []
	for i in range(a[0], b[0])
		s = _lstrip(self.lines[i])
		if comment then
			if s[:2] != "//" then s = "// " + s
		else
			if s[:2] == "//" then s = _lstrip(s[2:])
		end if
		out.push s
	end for
	self.anc = a
	self.pos = b
	self.setSelText out.join(LF)
	self.anc = a
	self.pos = [b[0], self.lines[b[0]].len]
end function

Editor.cut = function
	if not self.hasSelection then return
	rl.SetClipboardText self.selectedText
	self.setSelText ""
end function

Editor.copy = function
	if self.hasSelection then rl.SetClipboardText self.selectedText
end function

Editor.paste = function
	s = rl.GetClipboardText
	if s then self.setSelText s
end function

Editor.selectAll = function
	self.anc = [0, 0]
	last = self.lines.len - 1
	self.pos = [last, self.lines[last].len]
end function

Editor.noteEdited = function
	self.modified = true
	self.dirty = true
end function

Editor.canUndo = function
	return self._undoPos >= 0
end function

Editor.canRedo = function
	return self._undoPos + 2 < self._undo.len
end function

//----------------------------------------------------------------------
// Commands: what the toolbar, its menus, and the shortcut keys do
//----------------------------------------------------------------------

Editor.doCommand = function(cmd, arg=null)
	if cmd == "close" then
		self.finish "close"
	else if cmd == "run" then
		self.finish "run"
	else if cmd == "save" then
		if self.path then self.writeFile self.path else self.dialog = EditorUI.SaveAsDialog.Make(self)
	else if cmd == "saveAs" then
		self.dialog = EditorUI.SaveAsDialog.Make(self)
	else if cmd == "revert" then
		self.revert
	else if cmd == "undo" then
		self.undo
	else if cmd == "redo" then
		self.redo
	else if cmd == "cut" then
		self.cut
	else if cmd == "copy" then
		self.copy
	else if cmd == "paste" then
		self.paste
	else if cmd == "selectAll" then
		self.selectAll
	else if cmd == "find" then
		if self.findPanel then self.closeFind else self.openFind
	else if cmd == "navigate" then
		self.menu = EditorUI.Menu.Make(self._navigateItems, self._menuX("navigate"), self.codeTop)
	else if cmd == "code" then
		self.menu = EditorUI.Menu.Make(self._codeItems, self._menuX("code"), self.codeTop)
	else if cmd == "help" then
		self.dialog = EditorUI.HelpDialog.Make(self)
	else if cmd == "jump" then
		self.dialog = EditorUI.GoToDialog.Make(self)
	else if cmd == "gotoLine" then
		self.jumpToLine arg
		self.focus = null
	else if cmd == "comment" then
		self.toggleComment
	else if cmd == "insertColor" then
		self.dialog = EditorUI.InsertColorDialog.Make(self)
	else if cmd == "snippet" then
		self.insertCode arg
	end if
end function

// Close (and maybe run), saving first if Auto-Save is on, as MM1 did.
Editor.finish = function(result)
	if self.autoSave and self.path and self.dirty then self.writeFile self.path
	self.result = result
	self.done = true
end function

Editor.setAutoSave = function(on)
	Editor.autoSave = on
end function

// A message shown in place of the path for a few seconds.
Editor.flash = function(msg, isError=false)
	self._status = [msg, isError, time + 3]
end function

Editor.statusMessage = function
	if self._status and time < self._status[2] then return self._status
	return null
end function

// Save to path, through a temporary file so a failed write cannot destroy
// the old one.  Returns null, or why it failed as a plain string: the file
// operations return error values, and MS2 halts on any error value a
// statement discards, so they never leave this function.
Editor.writeFile = function(path)
	// file.move onto a folder would move the file into it, like mv.
	info = file.info(path)
	if info != null and info.isDirectory then
		msg = "Unable to save " + path + ": that is a folder"
		self.flash msg, true
		return msg
	end if
	tmp = path + ".tmp"
	err = file.writeLines(tmp, self.lines)
	if err == null then err = file.move(tmp, path)
	if err != null then
		if file.exists(tmp) then ignored = file.delete(tmp)
		// "File error: writeLines: disk is read-only" -> "disk is read-only"
		why = err.message
		parts = why.split(": ")
		if parts.len > 1 then why = parts[-1]
		msg = "Unable to save " + path + ": " + why
		self.flash msg, true
		return msg
	end if
	if path != self.path then
		self.path = path
		m = modeForPath(path)
		if m != self.mode then
			self.mode = m
			self._load self.lines
		end if
	end if
	self.dirty = false
	self._revertTo = [self.lines[:], false]
	self.flash "Saved " + path
	return null
end function

// Back to the text as it was when the editor opened, or last saved.
// Undoable, unlike MM1's.
Editor.revert = function
	if self.lines == self._revertTo[0] then return
	self.storeUndo
	self._lastEditTime = -99
	self._load self._revertTo[0]
	self.dirty = self._revertTo[1]
	self.modified = true
	self.scrollIntoView self.pos
end function

Editor.openFind = function
	self.findPanel = EditorUI.FindPanel.Make(self)
	self.focus = "find"
	self.scrollIntoView self.pos
end function

Editor.closeFind = function
	self.findPanel = null
	self.focus = null
end function

Editor._menuX = function(cmd)
	for b in self.toolbar.buttons
		if b.cmd == cmd then return b.rect[0] - 4
	end for
	return Display.screenLeft
end function

// MM1's NavigateMenu: Jump to Line, then whatever the mode lists.
Editor._navigateItems = function
	items = [{"text": "Jump to Line...", "shortcut": "J", "cmd": "jump"}]
	if @self.mode.navItems == null then return items
	ed = self
	tokensFor = function(i)
		return ed.tokensAt(i)
	end function
	for it in self.mode.navItems(self.lines, @tokensFor)
		items.push {"text": it[1].replace(TAB, " "), "shortcut": null, "cmd": "gotoLine", "arg": it[0]}
	end for
	return items
end function

// MM1's CodeMenu: comment, Insert Color, and the snippets.
Editor._codeItems = function
	a = self.selFirst
	b = self.selLast
	if b[0] > a[0] then noun = "Lines" else noun = "Line"
	if _lstrip(self.lines[a[0]])[:2] == "//" then verb = "Uncomment " else verb = "Comment "
	items = [{"text": verb + noun, "shortcut": "/", "cmd": "comment"},
	  {"text": "Insert Color...", "shortcut": null, "cmd": "insertColor"},
	  {"text": "-", "shortcut": null}]
	for snip in self._snippets
		items.push {"text": snip[0], "shortcut": null, "cmd": "snippet", "arg": snip[1]}
	end for
	return items
end function

// [title, code] for each snippet: "===Title" starts one, and the lines after
// it are its code.
Editor._snippets = function
	result = []
	for path in self.snippetPaths
		lines = file.readLines(path)
		if not lines isa list then continue
		for line in lines
			if line[:3] == "===" then
				result.push [line[3:], []]
			else if result then
				result[-1][1].push line
			end if
		end for
	end for
	for snip in result
		snip[1] = snip[1].join(LF)
	end for
	return result
end function

// Port of CodeMenu.InsertCode: with a selection, the template wraps it (in
// place of _code_); otherwise it goes in after the current line.  Then the
// first placeholder is selected, ready to type over.
Editor.insertCode = function(code)
	a = self.selFirst
	b = self.selLast
	if b[1] == 0 and b[0] > a[0] then
		// A selection ending at the start of a line really ends on the line above.
		b = [b[0] - 1, self.lines[b[0] - 1].len]
	end if
	if a == b or code.indexOf("_code_") == null then
		if code[-1] == LF then code = code[:-1]
		p = [b[0], self.lines[b[0]].len]
		self.anc = p
		self.pos = p[:]
		code = LF + code
		start = b[0] + 1
	else
		self.anc = a
		self.pos = b
		code = code.replace("_code_", self.selectedText)
		start = a[0]
	end if
	self.setSelText code
	self._lastEditTime = -99
	for lineNum in range(start, self.lines.len - 1)
		hits = self._placeholders(self.lines[lineNum])
		if hits then
			self.setSelection [lineNum, hits[0][0]], [lineNum, hits[0][1]]
			break
		end if
	end for
end function

//----------------------------------------------------------------------
// Cursor movement
//----------------------------------------------------------------------

Editor._charAt = function(p)
	s = self.lines[p[0]]
	if p[1] >= s.len then return LF
	return s[p[1]]
end function

// Step pos one character; false if it hit either end of the text.
Editor._advance = function(d)
	p = self.pos
	p[1] += d
	if p[1] < 0 then
		if p[0] == 0 then
			p[1] = 0
			return false
		end if
		p[0] -= 1
		p[1] = self.lines[p[0]].len
	else if p[1] > self.lines[p[0]].len then
		if p[0] == self.lines.len - 1 then
			p[1] -= 1
			return false
		end if
		p[0] += 1
		p[1] = 0
	end if
	return true
end function

// Port of MM1's MoveCursor.  allTheWay: to the start/end of the line (for
// dChar) or of the document (for dLine).
Editor.moveCursor = function(dChar, dLine, allTheWay, shift, byWord)
	self._caretOn
	if self.hasSelection and not shift then
		if dChar != 0 then
			// Collapse toward the end we are moving to, and that is all.
			if dChar > 0 then p = self.selLast else p = self.selFirst
			self.anc = p
			self.pos = p[:]
			self._prefCol = self.colAt(p)
			return
		end if
		if dLine > 0 then p = self.selLast else p = self.selFirst
		self.anc = p
		self.pos = p[:]
	end if
	p = self.pos
	if dChar != 0 then
		if p[1] == 0 and dChar < 0 then byWord = false
		if p[1] == self.lines[p[0]].len and dChar > 0 then byWord = false
		if allTheWay then
			if dChar < 0 then p[1] = 0 else p[1] = self.lines[p[0]].len
		else if byWord then
			st = {"numeric": false}
			if dChar < 0 then self._advance -1
			c = self._charAt(p)
			line = p[0]
			while not _isTokenChar(c, st) and p[0] == line and self._advance(dChar)
				c = self._charAt(p)
			end while
			while _isTokenChar(c, st) and self._advance(dChar)
				c = self._charAt(p)
			end while
			if dChar < 0 and (p[0] > 0 or p[1] > 0) then self._advance 1
		else
			self._advance dChar
		end if
		self._prefCol = self.colAt(p)
	end if
	if dLine < 0 then
		if allTheWay then
			p[0] = 0
			p[1] = 0
		else if p[0] == 0 then
			p[1] = 0
		else
			p[0] -= 1
			p[1] = self.indexForCol(p[0], self._prefCol)
		end if
	else if dLine > 0 then
		last = self.lines.len - 1
		if allTheWay then
			p[0] = last
			p[1] = self.lines[last].len
		else if p[0] == last then
			p[1] = self.lines[last].len
		else
			p[0] += 1
			p[1] = self.indexForCol(p[0], self._prefCol)
		end if
	end if
	if not shift then self.anc = p[:]
	self.scrollIntoView p
end function

//----------------------------------------------------------------------
// Geometry
//----------------------------------------------------------------------

// The screen column of a position, with tabs expanded.
Editor.colAt = function(p)
	s = self.lines[p[0]]
	if s.indexOf(TAB) == null then return p[1]
	col = 0
	tw = self.tabWidth
	for i in range(0, p[1] - 1, 1)
		if s[i] == TAB then col += tw - col % tw else col += 1
	end for
	return col
end function

// The index nearest a screen column on the given line.
Editor.indexForCol = function(lineNum, targetCol)
	s = self.lines[lineNum]
	col = 0
	tw = self.tabWidth
	for i in s.indexes
		if s[i] == TAB then w = tw - col % tw else w = 1
		if col + w / 2 > targetCol then return i
		col += w
	end for
	return s.len
end function

// Each line expanded for display, with a map from index to column (one
// entry past the end); the map is null when the line has no tabs.
Editor._expand = function(s)
	if s.indexOf(TAB) == null then return [s, null]
	out = []
	cols = []
	col = 0
	tw = self.tabWidth
	for c in s
		cols.push col
		if c == TAB then
			n = tw - col % tw
			out.push " " * n
			col += n
		else
			out.push c
			col += 1
		end if
	end for
	cols.push col
	return [out.join(""), cols]
end function

Editor.codeLeft = function
	return Display.screenLeft
end function

Editor.codeTop = function
	return Display.screenTop + self.toolbarHeight
end function

Editor.codeWidth = function
	return Display.screenWidth - self.scrollbarSize
end function

Editor.codeHeight = function
	h = Display.screenHeight - self.toolbarHeight - self.scrollbarSize
	if self.findPanel then h -= self.findPanel.height
	return h
end function

Editor.textLeft = function
	return self.codeLeft + self.gutterWidth
end function

Editor.maxScrollY = function
	return _max(0, (self.lines.len + 1) * self.lineHeight - self.codeHeight)
end function

Editor.maxLineWidth = function
	w = 0
	for s in self.lines
		if s.len > w then w = s.len
	end for
	return w * self.charWidth * 1.5 + 50		// tabs are wider; be generous
end function

Editor.scrollIntoView = function(p, forceTop=false)
	lh = self.lineHeight
	y = p[0] * lh
	viewH = self.codeHeight
	if y < self.scrollY or forceTop then
		self.scrollY = y
	else if y + lh > self.scrollY + viewH then
		self.scrollY = y + lh - viewH
	end if
	self.scrollY = _clamp(self.scrollY, 0, self.maxScrollY)

	x = self.colAt(p) * self.charWidth
	viewW = self.codeWidth - self.gutterWidth
	if p[1] == 0 then
		self.scrollX = 0
	else if x < self.scrollX then
		self.scrollX = _max(x - 20, 0)
	else if x > self.scrollX + viewW - 10 then
		self.scrollX = x - viewW + 50
	end if
end function

// The text position under a window point (clamped to the text).
Editor.posAtXY = function(x, y)
	lineNum = floor((y - self.codeTop + self.scrollY) / self.lineHeight)
	if lineNum < 0 then return [0, 0]
	last = self.lines.len - 1
	if lineNum > last then return [last, self.lines[last].len]
	col = (x - self.textLeft + self.scrollX) / self.charWidth
	return [lineNum, self.indexForCol(lineNum, col)]
end function

//----------------------------------------------------------------------
// Mouse
//----------------------------------------------------------------------

Editor._wordStart = function(s, i)
	while i > 0 and self.mode.isWordChar(s[i-1])
		i -= 1
	end while
	return i
end function

Editor._wordEnd = function(s, i)
	while i < s.len and self.mode.isWordChar(s[i])
		i += 1
	end while
	return i
end function

// MM1's FindMatchingToken: the partner of the quote or bracket at pos on
// one line, or -1.
_findMatch = function(s, pos)
	c = s[pos]
	pairs = {"(":")", "[":"]", "{":"}"}
	if pairs.hasIndex(c) then
		closer = pairs[c]
		depth = 1
		for i in range(pos + 1, s.len - 1, 1)
			if s[i] == c then depth += 1
			if s[i] == closer then depth -= 1
			if depth == 0 then return i
		end for
	else if ")]}".indexOf(c) != null then
		opener = "([{"[")]}".indexOf(c)]
		depth = 1
		for i in range(pos - 1, 0, -1)
			if i < 0 then break
			if s[i] == c then depth += 1
			if s[i] == opener then depth -= 1
			if depth == 0 then return i
		end for
	else if c == """" then
		open = false
		lastQuote = -1
		i = 0
		while i < s.len
			if s[i] == """" then
				if i + 1 < s.len and s[i+1] == """" then
					i += 2
					continue
				end if
				if i == pos and open then return lastQuote
				if i > pos and open then return i
				open = not open
				lastQuote = i
			end if
			i += 1
		end while
	end if
	return -1
end function

// Grow the selection by words or lines after a double or triple click,
// as MM1's ExtendSelection did.
Editor._extendSelection = function(forward)
	if self._clickCount == 2 then
		if not self.hasSelection then
			s = self.lines[self.anc[0]]
			i = self.anc[1]
			m = -1
			if i > 0 and "()[]{}""".indexOf(s[i-1]) != null then
				m = _findMatch(s, i - 1)
			else if i < s.len and "()[]{}""".indexOf(s[i]) != null then
				m = _findMatch(s, i)
			else
				self.anc[1] = self._wordStart(s, i)
				self.pos[1] = self._wordEnd(s, self.pos[1])
			end if
			// Select what is between the pair, not the pair itself.
			if m >= 0 then
				if m < i then
					self.anc[1] = m + 1
					if "([{""".indexOf(s[i-1]) == null then self.pos[1] = i - 1
				else
					self.anc[1] = m
				end if
			end if
		else if forward then
			self.anc[1] = self._wordStart(self.lines[self.anc[0]], self.anc[1])
			self.pos[1] = self._wordEnd(self.lines[self.pos[0]], self.pos[1])
		else
			self.anc[1] = self._wordEnd(self.lines[self.anc[0]], self.anc[1])
			self.pos[1] = self._wordStart(self.lines[self.pos[0]], self.pos[1])
		end if
	else if self._clickCount > 2 then
		if forward then
			self.anc[1] = 0
			self.pos[1] = self.lines[self.pos[0]].len
		else
			self.anc[1] = self.lines[self.anc[0]].len
			self.pos[1] = 0
		end if
	end if
end function

_inRect = function(p, r)
	return r[0] <= p.x < r[0] + r[2] and r[1] <= p.y < r[1] + r[3]
end function

Editor._vThumb = function
	codeH = self.codeHeight
	total = (self.lines.len + 1) * self.lineHeight
	if total <= codeH then return null
	th = _max(20, codeH * codeH / total)
	ty = self.codeTop + (codeH - th) * self.scrollY / self.maxScrollY
	return [self.codeLeft + self.codeWidth + 3, ty, self.scrollbarSize - 6, th]
end function

Editor._hThumb = function
	viewW = self.codeWidth - self.gutterWidth
	totalW = self.maxLineWidth
	if totalW <= viewW then return null
	tw = _max(20, viewW * viewW / totalW)
	tx = self.codeLeft + self.gutterWidth + (viewW - tw) * _min(1, self.scrollX / (totalW - viewW))
	return [tx, self.codeTop + self.codeHeight + 3, tw, self.scrollbarSize - 6]
end function

// Scrollbars: drag the thumb, or click the track to page.
Editor._handleScrollbars = function(inp)
	m = inp.mouse
	ss = self.scrollbarSize
	if self._scrollDrag then
		d = self._scrollDrag
		if not inp.down then
			self._scrollDrag = null
		else if d[0] == "v" then
			t = self._vThumb
			if t then
				span = self.codeHeight - t[3]
				self.scrollY = _clamp(d[2] + (m.y - d[1]) * self.maxScrollY / span, 0, self.maxScrollY)
			end if
		else
			t = self._hThumb
			if t then
				viewW = self.codeWidth - self.gutterWidth
				maxX = self.maxLineWidth - viewW
				self.scrollX = _clamp(d[2] + (m.x - d[1]) * maxX / (viewW - t[2]), 0, maxX)
			end if
		end if
		return true
	end if
	if not inp.pressed then return false
	vTrack = [self.codeLeft + self.codeWidth, self.codeTop, ss, self.codeHeight]
	hTrack = [self.codeLeft, self.codeTop + self.codeHeight, self.codeWidth, ss]
	if _inRect(m, vTrack) then
		t = self._vThumb
		if t == null then return true
		if m.y < t[1] then
			self.scrollY = _max(0, self.scrollY - self.codeHeight)
		else if m.y >= t[1] + t[3] then
			self.scrollY = _min(self.maxScrollY, self.scrollY + self.codeHeight)
		else
			self._scrollDrag = ["v", m.y, self.scrollY]
		end if
		return true
	end if
	if _inRect(m, hTrack) then
		t = self._hThumb
		if t == null then return true
		viewW = self.codeWidth - self.gutterWidth
		maxX = self.maxLineWidth - viewW
		if m.x < t[0] then
			self.scrollX = _max(0, self.scrollX - viewW)
		else if m.x >= t[0] + t[2] then
			self.scrollX = _min(maxX, self.scrollX + viewW)
		else
			self._scrollDrag = ["h", m.x, self.scrollX]
		end if
		return true
	end if
	return false
end function

Editor._handleMouse = function(inp)
	m = inp.mouse
	shift = inp.shift
	if self._handleScrollbars(inp) then return
	inCode = (self.codeLeft <= m.x < self.codeLeft + self.codeWidth and
	  self.codeTop <= m.y < self.codeTop + self.codeHeight)

	wheel = inp.wheel
	if inCode and (wheel.x != 0 or wheel.y != 0) then
		self.scrollY = _clamp(self.scrollY - wheel.y * self.lineHeight * 3, 0, self.maxScrollY)
		self.scrollX = _clamp(self.scrollX - wheel.x * self.charWidth * 3, 0, self.maxLineWidth)
	end if

	if inp.pressed and inCode then
		self.focus = null
		if time - self._lastClickTime > 0.4 then self._clickCount = 1 else self._clickCount += 1
		self._lastClickTime = time
		self._dragging = true
		self.pos = self.posAtXY(m.x, m.y)
		if not shift then self.anc = self.pos[:]
		self._extendSelection not _before(self.pos, self.anc)
		self._prefCol = self.colAt(self.pos)
		self._caretOn
	else if self._dragging and inp.down then
		// Dragging past the edge scrolls.
		if m.y < self.codeTop then self.scrollY = _max(0, self.scrollY - self.lineHeight)
		if m.y > self.codeTop + self.codeHeight then
			self.scrollY = _min(self.maxScrollY, self.scrollY + self.lineHeight)
		end if
		self.pos = self.posAtXY(m.x, m.y)
		self._extendSelection not _before(self.pos, self.anc)
		self._prefCol = self.colAt(self.pos)
	else if self._dragging then
		self._dragging = false
	end if
end function

//----------------------------------------------------------------------
// Keyboard
//----------------------------------------------------------------------

Editor._caretOn = function
	self._caretTime = time
end function

Editor.update = function
	inp = EditorUI.readInput

	// A dialog or menu, while up, gets everything.
	if self.dialog then
		if self.dialog.update(self, inp) then self.dialog = null
		return
	end if
	if self.menu then
		item = self.menu.update(inp)
		if item == null then return
		self.menu = null
		// Only items that need an argument (a line number, a snippet) carry one.
		if item isa map then
			arg = null
			if item.hasIndex("arg") then arg = item.arg
			self.doCommand item.cmd, arg
		end if
		return
	end if

	// Chords that mean the same wherever the keyboard is.
	if inp.mod then
		if self._chord("s") then
			if inp.shift then self.doCommand "saveAs" else self.doCommand "save"
		end if
		if self._chord("w") then self.doCommand "close"
		if self._chord("r") then self.doCommand "run"
		if self._chord("f") then self.doCommand "find"
		if self._chord("j") then self.doCommand "jump"
		if inp.shift and rl.IsKeyPressed(rl.KEY_SLASH) then self.doCommand "help"
		if self.dialog or self.menu or self.done then return
	end if

	cmd = self.toolbar.update(self, inp)
	if cmd then
		self.doCommand cmd
		return
	end if
	mouseTaken = _inRect(inp.mouse, [Display.screenLeft, Display.screenTop, Display.screenWidth, self.toolbarHeight])
	if self.findPanel then
		if self.findPanel.update(self, inp) then mouseTaken = true
		if self.findPanel == null then return		// it closed itself
	end if

	if self.focus == null then self._handleKeys inp
	if not mouseTaken or self._dragging or self._scrollDrag then self._handleMouse inp
end function

Editor._handleKeys = function(inp)
	shift = inp.shift
	ctrl = inp.ctrl
	cmd = inp.cmd
	byWord = inp.alt or ctrl

	if _keyHit(rl.KEY_LEFT) then self.moveCursor -1, 0, cmd, shift, byWord
	if _keyHit(rl.KEY_RIGHT) then self.moveCursor 1, 0, cmd, shift, byWord
	if _keyHit(rl.KEY_UP) then self.moveCursor 0, -1, cmd, shift, byWord
	if _keyHit(rl.KEY_DOWN) then self.moveCursor 0, 1, cmd, shift, byWord
	if rl.IsKeyPressed(rl.KEY_HOME) then
		if ctrl then self.moveCursor 0, -1, true, shift else self.moveCursor -1, 0, true, shift
	end if
	if rl.IsKeyPressed(rl.KEY_END) then
		if ctrl then self.moveCursor 0, 1, true, shift else self.moveCursor 1, 0, true, shift
	end if
	page = self.codeHeight
	if _keyHit(rl.KEY_PAGE_UP) then self.scrollY = _max(0, self.scrollY - page)
	if _keyHit(rl.KEY_PAGE_DOWN) then self.scrollY = _min(self.maxScrollY, self.scrollY + page)

	if _keyHit(rl.KEY_ENTER) or _keyHit(rl.KEY_KP_ENTER) then
		if shift then self.insertWithEnder else self.setSelText LF
	end if
	if _keyHit(rl.KEY_BACKSPACE) then self.deleteBack
	if _keyHit(rl.KEY_DELETE) then self.deleteForward
	if _keyHit(rl.KEY_TAB) then self.handleTab shift
	if rl.IsKeyPressed(rl.KEY_ESCAPE) and self.findPanel then self.closeFind

	if inp.mod then
		if self._chord("x") then self.cut
		if self._chord("c") then self.copy
		if self._chord("v") then self.paste
		if self._chord("a") then self.selectAll
		if self._chord("z") then
			if shift then self.redo else self.undo
		end if
		if rl.IsKeyPressed(rl.KEY_LEFT_BRACKET) then self.indent -1
		if rl.IsKeyPressed(rl.KEY_RIGHT_BRACKET) then self.indent 1
		if rl.IsKeyPressed(rl.KEY_SLASH) and not shift then self.toggleComment
	else
		if rl.IsKeyPressed(rl.KEY_F1) then
			if shift then self.redo else self.undo
		end if
		if rl.IsKeyPressed(rl.KEY_F2) then self.cut
		if rl.IsKeyPressed(rl.KEY_F3) then self.copy
		if rl.IsKeyPressed(rl.KEY_F4) then self.paste
	end if

	for c in inp.chars
		self.setSelText c
	end for
end function

// A letter chord, by the key that types that letter (not its US position).
Editor._chord = function(letter)
	k = key.codeForName(letter)
	return k != null and rl.IsKeyPressed(k)
end function

//----------------------------------------------------------------------
// Drawing
//----------------------------------------------------------------------

_bracketColor = function(colors, depth)
	if depth < 1 then return theme.unmatched
	return colors[(depth - 1) % colors.len]
end function

// Draw text sheared about its baseline.  rlgl transforms each vertex by the
// current matrix as it is batched, so this costs nothing extra to render.
// The matrix is column-major: element 4 adds (that * y) to x.  Screen y
// grows downward, so a negative factor leans the tops to the right.
_drawSlanted = function(font, text, x, y, size, color)
	baseline = size * 717 / 942		// MiniMicro-Regular's ascent, in pixels
	rl.rlPushMatrix
	rl.rlTranslatef x, y + baseline, 0
	rl.rlMultMatrixf [1,0,0,0, -theme.slant,1,0,0, 0,0,1,0, 0,0,0,1]
	rl.DrawTextEx font, text, [0, -baseline], size, 0, color
	rl.rlPopMatrix
end function

_styleColor = function(tok)
	style = tok[2]
	if style == "paren" then return _bracketColor(theme.paren, tok[3])
	if style == "square" then return _bracketColor(theme.square, tok[3])
	if style == "brace" then return _bracketColor(theme.brace, tok[3])
	if theme.style.hasIndex(style) then return theme.style[style]
	return theme.text
end function

Editor.draw = function
	left = Display.screenLeft
	top = Display.screenTop
	w = Display.screenWidth
	h = Display.screenHeight
	lh = self.lineHeight
	cw = self.charWidth
	codeTop = self.codeTop
	codeH = self.codeHeight
	codeW = self.codeWidth
	textLeft = self.textLeft

	rl.DrawRectangle left, codeTop, codeW, codeH, theme.background
	rl.BeginScissorMode left, codeTop, codeW, codeH

	first = floor(self.scrollY / lh)
	last = _min(self.lines.len - 1, floor((self.scrollY + codeH) / lh))
	self._ensureStyled last
	selA = self.selFirst
	selB = self.selLast
	hasSel = selA != selB
	textY0 = codeTop - self.scrollY + 2		// 22-pixel glyphs centered in 26
	numDY = 4		// lines up the smaller numbers' baseline with the code's

	for i in range(first, last, 1)
		if i < 0 then continue
		y = textY0 + i * lh
		s = self.lines[i]
		ex = self._expand(s)
		disp = ex[0]
		cols = ex[1]

		// Selection highlight runs to the edge on all but its last line.
		if hasSel and selA[0] <= i <= selB[0] then
			if i == selA[0] then c0 = self.colAt(selA) else c0 = 0
			x0 = textLeft - self.scrollX + c0 * cw
			if i == selB[0] then
				x1 = textLeft - self.scrollX + self.colAt(selB) * cw
			else
				x1 = left + codeW
			end if
			if i != selA[0] then x0 = _max(left + self.gutterWidth - 4, x0)
			rl.DrawRectangle x0, y - 2, x1 - x0, lh, theme.selection
		end if

		x = textLeft - self.scrollX
		pos = 0
		for tok in self._toks[i]
			if tok[0] > pos then
				if cols then gap = disp[cols[pos]:cols[tok[0]]] else gap = disp[pos:tok[0]]
				if not _blank(gap) then
					if cols then c = cols[pos] else c = pos
					rl.DrawTextEx _codeFont, gap, [x + c * cw, y], _codeSize, 0, theme.text
				end if
			end if
			if cols then
				c = cols[tok[0]]
				t = disp[c:cols[tok[1]]]
			else
				c = tok[0]
				t = disp[tok[0]:tok[1]]
			end if
			if theme.italic.hasIndex(tok[2]) then
				_drawSlanted _codeFont, t, x + c * cw, y, _codeSize, _styleColor(tok)
			else
				rl.DrawTextEx _codeFont, t, [x + c * cw, y], _codeSize, 0, _styleColor(tok)
			end if
			pos = tok[1]
		end for
		if pos < s.len then
			if cols then c = cols[pos] else c = pos
			gap = disp[c:]
			if not _blank(gap) then rl.DrawTextEx _codeFont, gap, [x + c * cw, y], _codeSize, 0, theme.text
		end if
	end for

	// The gutter is drawn over the text, so text scrolled left goes under it.
	rl.DrawRectangle left, codeTop, self.gutterWidth - 4, codeH, theme.background
	for i in range(first, last, 1)
		if i < 0 then continue
		num = str(i + 1)
		num = "0" * _max(0, 5 - num.len) + num
		rl.DrawTextEx _numFont, num, [left + 2, textY0 + i * lh + numDY], _numSize, 0, theme.lineNumber
	end for

	// Caret: blinks, but stays solid for a moment after anything moves it.
	if self.focus == null and not hasSel and ((time - self._caretTime) % 1 < 0.6) then
		cx = textLeft - self.scrollX + self.colAt(self.pos) * cw
		if cx >= textLeft - 1 then
			rl.DrawRectangle cx - 1, textY0 + self.pos[0] * lh - 2, 2, lh, theme.caret
		end if
	end if
	rl.EndScissorMode

	self._drawScrollbars
	self.toolbar.draw self
	if self.findPanel then self.findPanel.draw self
	if self.menu then
		self.menu.draw
	else if self.dialog then
		self.dialog.draw self
	else
		self.toolbar.drawTag self
	end if
end function

Editor._drawScrollbars = function
	ss = self.scrollbarSize
	codeTop = self.codeTop
	codeH = self.codeHeight
	codeW = self.codeWidth
	left = self.codeLeft
	rl.DrawRectangle left + codeW, codeTop, ss, codeH, theme.scrollTrack
	t = self._vThumb
	if t then EditorUI.roundRect t, 5, theme.scrollThumb
	rl.DrawRectangle left, codeTop + codeH, codeW + ss, ss, theme.scrollTrack
	t = self._hThumb
	if t then EditorUI.roundRect t, 5, theme.scrollThumb
end function

return Editor
