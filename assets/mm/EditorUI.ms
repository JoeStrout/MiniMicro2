// EditorUI: everything around the editor's text -- the toolbar, its menus,
// the dialogs, and the Find/Replace panel.  Ported from Mini Micro 1's
// CodeEditorStuff (CodeEditorToolbar.cs, ToolbarMenu.cs, CodeMenu.cs,
// NavigateMenu.cs, FindResultsList.cs and the dialogs), drawn with raylib
// primitives where MM1 had Unity prefabs.
//
// Widgets know nothing of the editor.  The editor reads input once a frame
// (readInput) and hands it to whichever widget has the mouse or the keyboard;
// toolbar buttons and menu items name an editor command, which the editor
// runs with doCommand.

import "importUtil"
ensureImport ["Display", "key", "color"]

rl = raylib
TAB = char(9)
LF = char(10)

UI = {}
UI.font = null		// the editor sets these once its fonts are loaded
UI.size = 17
UI.charW = 10
UI.small = null		// a smaller size, for labels
UI.smallSize = 15
UI.smallW = 9
UI.icons = {}

pal = {}
pal.text = [45, 45, 45, 255]
pal.dimText = [150, 150, 150, 255]
pal.toolbar = [196, 197, 196, 255]
pal.panel = [206, 206, 206, 255]
pal.listBack = [226, 226, 226, 255]
pal.header = [214, 214, 214, 255]
pal.white = [255, 255, 255, 255]
pal.border = [110, 110, 110, 255]
pal.divider = [170, 170, 170, 255]
pal.fieldBorder = [140, 140, 140, 255]
pal.focusRing = [90, 140, 240, 255]
pal.selection = [168, 200, 255, 255]
pal.hilite = [70, 110, 220, 255]
pal.toggleOn = [150, 165, 225, 255]
pal.match = [255, 255, 90, 255]
pal.replaced = [204, 204, 204, 255]
pal.error = [204, 0, 0, 255]
pal.tag = [255, 255, 225, 255]
pal.dialogHeader = [150, 150, 150, 255]
pal.shadow = [0, 0, 0, 60]
pal.scrim = [0, 0, 0, 40]

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

_inRect = function(p, r)
	return r[0] <= p.x < r[0] + r[2] and r[1] <= p.y < r[1] + r[3]
end function

keyHit = function(k)
	return rl.IsKeyPressed(k) or rl.IsKeyPressedRepeat(k)
end function

// A letter chord, by the key that types that letter (not its US position).
chord = function(letter)
	k = key.codeForName(letter)
	return k != null and rl.IsKeyPressed(k)
end function

loadIcons = function(dir)
	if UI.icons or not rl.IsWindowReady then return
	for n in "Close Save Revert RunButton Undo Redo Cut Copy Paste Find Jump Insert Help SearchOptIcons DialogUI ColorSliders".split
		tex = rl.LoadTexture(dir + n + ".png")
		rl.SetTextureFilter tex, rl.TEXTURE_FILTER_BILINEAR
		UI.icons[n] = tex
	end for
end function

// Everything a frame's widgets may want, read once: typed characters come
// from a queue, so only one reader may drain it.
readInput = function
	inp = {}
	inp.shift = rl.IsKeyDown(rl.KEY_LEFT_SHIFT) or rl.IsKeyDown(rl.KEY_RIGHT_SHIFT)
	inp.ctrl = rl.IsKeyDown(rl.KEY_LEFT_CONTROL) or rl.IsKeyDown(rl.KEY_RIGHT_CONTROL)
	inp.cmd = rl.IsKeyDown(rl.KEY_LEFT_SUPER) or rl.IsKeyDown(rl.KEY_RIGHT_SUPER)
	inp.alt = rl.IsKeyDown(rl.KEY_LEFT_ALT) or rl.IsKeyDown(rl.KEY_RIGHT_ALT)
	inp.mod = inp.cmd or inp.ctrl
	// A chord may also deliver a character; ignore it.  So do the Private Use
	// codes some platforms send for function keys.
	inp.chars = []
	while true
		c = rl.GetCharPressed
		if c == 0 then break
		if inp.mod or c < 32 or 57344 <= c <= 63743 then continue
		inp.chars.push char(c)
	end while
	inp.mouse = rl.GetMousePosition
	inp.pressed = rl.IsMouseButtonPressed(0)
	inp.down = rl.IsMouseButtonDown(0)
	inp.wheel = rl.GetMouseWheelMoveV
	return inp
end function

//----------------------------------------------------------------------
// Drawing helpers
//----------------------------------------------------------------------

textWidth = function(s, small=false)
	if small then return s.len * UI.smallW
	return s.len * UI.charW		// the font is monospaced
end function

drawText = function(s, x, y, c=null, small=false)
	if c == null then c = pal.text
	if small then
		if UI.small then rl.DrawTextEx UI.small, s, [x, y], UI.smallSize, 0, c
	else
		if UI.font then rl.DrawTextEx UI.font, s, [x, y], UI.size, 0, c
	end if
end function

// Text vertically centered in a rect's height, at x.
drawTextIn = function(s, x, r, c=null, small=false)
	if small then sz = UI.smallSize else sz = UI.size
	drawText s, x, r[1] + floor((r[3] - sz) / 2), c, small
end function

// Shorten s from the left to fit in width w.
fitLeft = function(s, w)
	n = floor(w / UI.charW)
	if s.len <= n then return s
	return "..." + s[s.len - n + 3:]
end function

roundRect = function(r, radius, c)
	m = _min(r[2], r[3])
	if m > 0 then rl.DrawRectangleRounded r, _min(1, radius * 2 / m), 8, c
end function

roundRectLines = function(r, radius, c, thick=1)
	m = _min(r[2], r[3])
	if m > 0 then rl.DrawRectangleRoundedLinesEx r, _min(1, radius * 2 / m), 8, thick, c
end function

drawCheck = function(x, y, size, c)
	rl.DrawLineEx [x + size*0.2, y + size*0.5], [x + size*0.42, y + size*0.75], 2, c
	rl.DrawLineEx [x + size*0.42, y + size*0.75], [x + size*0.82, y + size*0.22], 2, c
end function

drawCheckbox = function(x, y, checked)
	rl.DrawRectangle x, y, 16, 16, pal.white
	rl.DrawRectangleLines x, y, 16, 16, pal.border
	if checked then drawCheck x, y, 16, pal.text
end function

drawChecker = function(r, cell=8)
	rl.DrawRectangle r[0], r[1], r[2], r[3], pal.white
	for y in range(0, r[3] - 1, cell)
		for x in range(0, r[2] - 1, cell)
			if (x/cell + y/cell) % 2 then
				rl.DrawRectangle r[0] + x, r[1] + y, _min(cell, r[2] - x), _min(cell, r[3] - y), [200, 200, 200, 255]
			end if
		end for
	end for
end function

// Mini Micro 1's dialog art (DialogUI.png): [source rect, borders as
// [left, top, right, bottom]], from the sprite sheet's Unity import
// settings.  It is drawn at half size, as it was there.
sprites = {}
sprites.dialog = [[0, 0, 256, 144], [35, 53, 40, 45]]
sprites.button = [[0, 144, 128, 48], [35, 23, 34, 24]]
sprites.thumb = [[206, 142, 25, 30], [0, 0, 0, 0]]
spriteScale = 0.5

// Draw a nine-slice sprite: corners keep their size, edges and middle stretch.
// Borders shrink, as in Unity, when dest is too small to hold them.
nineSlice = function(sprite, dest, tint)
	tex = UI.icons["DialogUI"]
	src = sprite[0]
	b = sprite[1]
	sc = spriteScale
	if b[1] + b[3] > 0 then sc = _min(sc, dest[3] / (b[1] + b[3]))
	if b[0] + b[2] > 0 then sc = _min(sc, dest[2] / (b[0] + b[2]))
	sx = [src[0], src[0] + b[0], src[0] + src[2] - b[2], src[0] + src[2]]
	sy = [src[1], src[1] + b[1], src[1] + src[3] - b[3], src[1] + src[3]]
	dx = [dest[0], dest[0] + b[0]*sc, dest[0] + dest[2] - b[2]*sc, dest[0] + dest[2]]
	dy = [dest[1], dest[1] + b[1]*sc, dest[1] + dest[3] - b[3]*sc, dest[1] + dest[3]]
	for i in range(0, 2)
		for j in range(0, 2)
			w = sx[i+1] - sx[i]
			h = sy[j+1] - sy[j]
			if w <= 0 or h <= 0 or dx[i+1] <= dx[i] or dy[j+1] <= dy[j] then continue
			rl.DrawTexturePro tex, [sx[i], sy[j], w, h], [dx[i], dy[j], dx[i+1] - dx[i], dy[j+1] - dy[j]], [0, 0], 0, tint
		end for
	end for
end function

// Multiply a color by a factor (Unity's button state tints work this way).
_shade = function(c, f, alpha=null)
	if alpha == null then alpha = c[3]
	return [round(c[0] * f), round(c[1] * f), round(c[2] * f), alpha]
end function

//----------------------------------------------------------------------
// TextField: a one-line text input
//----------------------------------------------------------------------

TextField = {}
TextField.text = ""
TextField.caret = 0
TextField.anchor = 0
TextField.scroll = 0
TextField.rect = [0, 0, 100, 24]
TextField.placeholder = ""
TextField._dragging = false

TextField.Make = function(text="")
	f = new TextField
	f.text = text
	f.selectAll
	return f
end function

TextField.setText = function(s)
	self.text = s
	self.selectAll
end function

TextField.selectAll = function
	self.anchor = 0
	self.caret = self.text.len
end function

TextField._selRange = function
	if self.anchor < self.caret then return [self.anchor, self.caret]
	return [self.caret, self.anchor]
end function

TextField._replaceSel = function(s)
	r = self._selRange
	self.text = self.text[:r[0]] + s + self.text[r[1]:]
	self.caret = r[0] + s.len
	self.anchor = self.caret
end function

TextField._moveTo = function(p, extend)
	self.caret = _clamp(p, 0, self.text.len)
	if not extend then self.anchor = self.caret
end function

TextField._step = function(d, inp)
	if self.anchor != self.caret and not inp.shift and not inp.mod then
		r = self._selRange
		if d < 0 then self._moveTo r[0], false else self._moveTo r[1], false
	else if inp.mod then
		if d < 0 then self._moveTo 0, inp.shift else self._moveTo self.text.len, inp.shift
	else
		self._moveTo self.caret + d, inp.shift
	end if
end function

// Keys, for the field that has the keyboard.  Returns "enter", "escape",
// "tab", "changed", or null.
TextField.handleKeys = function(inp)
	before = self.text
	for c in inp.chars
		self._replaceSel c
	end for
	if keyHit(rl.KEY_BACKSPACE) then
		if self.anchor == self.caret then self.anchor = _max(0, self.caret - 1)
		self._replaceSel ""
	end if
	if keyHit(rl.KEY_DELETE) then
		if self.anchor == self.caret then self.anchor = _min(self.text.len, self.caret + 1)
		self._replaceSel ""
	end if
	if keyHit(rl.KEY_LEFT) then self._step -1, inp
	if keyHit(rl.KEY_RIGHT) then self._step 1, inp
	if rl.IsKeyPressed(rl.KEY_HOME) then self._moveTo 0, inp.shift
	if rl.IsKeyPressed(rl.KEY_END) then self._moveTo self.text.len, inp.shift
	if inp.mod then
		r = self._selRange
		if chord("a") then self.selectAll
		if (chord("c") or chord("x")) and r[0] < r[1] then
			rl.SetClipboardText self.text[r[0]:r[1]]
			if chord("x") then self._replaceSel ""
		end if
		if chord("v") then
			s = rl.GetClipboardText
			if s then self._replaceSel s.replace(char(13), LF).split(LF)[0]
		end if
	end if
	if rl.IsKeyPressed(rl.KEY_ENTER) or rl.IsKeyPressed(rl.KEY_KP_ENTER) then return "enter"
	if rl.IsKeyPressed(rl.KEY_ESCAPE) then return "escape"
	if rl.IsKeyPressed(rl.KEY_TAB) then return "tab"
	if self.text != before then return "changed"
	return null
end function

TextField._indexAtX = function(x)
	i = round((x - self.rect[0] - 4 + self.scroll) / UI.charW)
	return _clamp(i, 0, self.text.len)
end function

// True if the mouse is this field's business this frame (so it takes focus).
TextField.handleMouse = function(inp)
	if inp.pressed and _inRect(inp.mouse, self.rect) then
		self._moveTo self._indexAtX(inp.mouse.x), inp.shift
		self._dragging = true
		return true
	end if
	if self._dragging then
		if inp.down then self.caret = self._indexAtX(inp.mouse.x) else self._dragging = false
		return true
	end if
	return false
end function

TextField.draw = function(focused)
	r = self.rect
	rl.DrawRectangle r[0], r[1], r[2], r[3], pal.white
	if focused then
		rl.DrawRectangleLinesEx r, 2, pal.focusRing
	else
		rl.DrawRectangleLines r[0], r[1], r[2], r[3], pal.fieldBorder
	end if
	cw = UI.charW
	inner = r[2] - 10
	cx = self.caret * cw
	if cx - self.scroll > inner then self.scroll = cx - inner
	if cx < self.scroll then self.scroll = cx
	if self.text.len * cw < inner then self.scroll = 0
	x0 = r[0] + 4 - self.scroll
	rl.BeginScissorMode r[0] + 2, r[1] + 2, r[2] - 4, r[3] - 4
	sr = self._selRange
	if focused and sr[0] < sr[1] then
		rl.DrawRectangle x0 + sr[0] * cw, r[1] + 3, (sr[1] - sr[0]) * cw, r[3] - 6, pal.selection
	end if
	if self.text == "" and not focused then
		drawTextIn self.placeholder, r[0] + 4, r, pal.dimText
	else
		drawTextIn self.text, x0, r
	end if
	if focused and sr[0] == sr[1] and time % 1 < 0.6 then
		rl.DrawRectangle x0 + cx - 1, r[1] + 4, 2, r[3] - 8, pal.text
	end if
	rl.EndScissorMode
end function

//----------------------------------------------------------------------
// Button: "push" (a labeled pill), "tool" (a toolbar icon), or "toggle"
// (an icon that stays down)
//----------------------------------------------------------------------

Button = {}
Button.rect = [0, 0, 80, 24]
Button.label = ""
Button.style = "push"
Button.icon = null			// key into UI.icons
Button.src = null			// part of the icon texture, or null for all of it
Button.enabled = true
Button.tint = [255, 255, 255, 255]	// for push buttons; dialogs use a light blue
Button.on = false
Button.cmd = null			// the editor command a toolbar button runs
Button.title = ""			// for the help tag
Button.shortcut = ""
Button._pressed = false

Button.Make = function(label, style="push")
	b = new Button
	b.label = label
	b.style = style
	return b
end function

// True when clicked: released over the button after pressing on it.
Button.handleMouse = function(inp)
	if not self.enabled then
		self._pressed = false
		return false
	end if
	over = _inRect(inp.mouse, self.rect)
	if inp.pressed and over then
		self._pressed = true
		return false
	end if
	if self._pressed and not inp.down then
		self._pressed = false
		return over
	end if
	return false
end function

Button.draw = function
	r = self.rect
	over = _inRect(rl.GetMousePosition, r)
	if self.style == "push" then
		// MM1's "Button Rounded" sprite; Unity darkens it to 78% when pressed,
		// and to 78% at half opacity when disabled.
		c = self.tint
		if not self.enabled then
			c = _shade(c, 0.784, 128)
		else if self._pressed and over then
			c = _shade(c, 0.784)
		end if
		if UI.icons.hasIndex("DialogUI") then
			nineSlice sprites.button, r, c
		else
			roundRect r, r[3] / 2, c
			roundRectLines r, r[3] / 2, pal.border
		end if
		if self.enabled then tc = pal.text else tc = pal.dimText
		drawTextIn self.label, r[0] + floor((r[2] - textWidth(self.label, true)) / 2), r, tc, true
		return
	end if
	if self.style == "toggle" then
		if self.on then c = pal.toggleOn else c = pal.white
		rl.DrawRectangle r[0], r[1], r[2], r[3], c
		rl.DrawRectangleLines r[0], r[1], r[2], r[3], pal.border
	else if self.enabled and over then
		if self._pressed then c = [0, 0, 0, 40] else c = [255, 255, 255, 90]
		roundRect r, 6, c
	end if
	if not UI.icons.hasIndex(self.icon) then return
	tex = UI.icons[self.icon]
	src = self.src
	if src == null then src = [0, 0, tex.width, tex.height]
	if self.enabled then tint = pal.white else tint = [255, 255, 255, 80]
	inset = 1 * (self.style == "toggle")
	rl.DrawTexturePro tex, src, [r[0] + inset, r[1] + inset, r[2] - inset*2, r[3] - inset*2], [0, 0], 0, tint
end function

//----------------------------------------------------------------------
// Menu: a list dropped from a toolbar button.  Items are maps with text,
// shortcut (or null), cmd and arg; text "-" is a separator.
//----------------------------------------------------------------------

Menu = {}
Menu.itemH = 22
Menu.maxH = 600

Menu.Make = function(items, x, y)
	m = new Menu
	m.items = items
	w = 60
	for it in items
		if it.text == "-" then continue
		extra = 36
		if it.shortcut then extra = 76
		w = _max(w, textWidth(it.text) + extra)
	end for
	h = _min(items.len * Menu.itemH + 8, Menu.maxH)
	x = _min(x, Display.screenLeft + Display.screenWidth - w - 4)
	m.rect = [x, y, w, h]
	m.scroll = 0
	m.hover = -1
	return m
end function

Menu._step = function(d)
	n = self.items.len
	i = self.hover
	for k in range(1, n)
		i = (i + d + n) % n
		if self.items[i].text != "-" then break
	end for
	self.hover = i
	y = i * self.itemH
	if y < self.scroll then self.scroll = y
	if y + self.itemH > self.scroll + self.rect[3] - 8 then self.scroll = y + self.itemH - self.rect[3] + 8
end function

// Null while the menu stays open; otherwise the chosen item, or "close".
Menu.update = function(inp)
	r = self.rect
	ih = self.itemH
	inside = _inRect(inp.mouse, r)
	maxScroll = _max(0, self.items.len * ih + 8 - r[3])
	if inside and inp.wheel.y != 0 then self.scroll = _clamp(self.scroll - inp.wheel.y * ih, 0, maxScroll)
	if inside and maxScroll > 0 then
		// Resting near either end scrolls, as in MM1.
		if inp.mouse.y < r[1] + 14 then self.scroll = _max(0, self.scroll - 4)
		if inp.mouse.y > r[1] + r[3] - 14 then self.scroll = _min(maxScroll, self.scroll + 4)
	end if
	if inside and (inp.mouse.x != self._lastX or inp.mouse.y != self._lastY) then
		i = floor((inp.mouse.y - r[1] - 4 + self.scroll) / ih)
		if 0 <= i < self.items.len and self.items[i].text != "-" then self.hover = i else self.hover = -1
	end if
	self._lastX = inp.mouse.x
	self._lastY = inp.mouse.y
	if keyHit(rl.KEY_DOWN) then self._step 1
	if keyHit(rl.KEY_UP) then self._step -1
	if rl.IsKeyPressed(rl.KEY_ESCAPE) then return "close"
	if (rl.IsKeyPressed(rl.KEY_ENTER) or rl.IsKeyPressed(rl.KEY_KP_ENTER)) and self.hover >= 0 then
		return self.items[self.hover]
	end if
	if inp.pressed then
		if not inside then return "close"
		self._armed = true
	end if
	if self._armed and not inp.down then
		self._armed = false
		if inside and self.hover >= 0 then return self.items[self.hover]
	end if
	return null
end function
Menu._lastX = -1
Menu._lastY = -1
Menu._armed = false

Menu.draw = function
	r = self.rect
	ih = self.itemH
	rl.DrawRectangle r[0] + 3, r[1] + 4, r[2], r[3], pal.shadow
	rl.DrawRectangle r[0], r[1], r[2], r[3], [236, 236, 236, 255]
	rl.DrawRectangleLines r[0], r[1], r[2], r[3], pal.border
	rl.BeginScissorMode r[0], r[1] + 1, r[2], r[3] - 2
	for i in self.items.indexes
		y = r[1] + 4 + i * ih - self.scroll
		if y + ih < r[1] or y > r[1] + r[3] then continue
		it = self.items[i]
		if it.text == "-" then
			rl.DrawRectangle r[0] + 6, y + ih/2, r[2] - 12, 1, pal.divider
			continue
		end if
		tc = pal.text
		if i == self.hover then
			rl.DrawRectangle r[0] + 2, y, r[2] - 4, ih, pal.hilite
			tc = pal.white
		end if
		row = [r[0], y, r[2], ih]
		drawTextIn it.text, r[0] + 14, row, tc
		if it.shortcut then
			sc = "^" + it.shortcut
			drawTextIn sc, r[0] + r[2] - 12 - textWidth(sc), row, tc
		end if
	end for
	rl.EndScissorMode
	// Arrows where there is more to scroll to.
	maxScroll = self.items.len * ih + 8 - r[3]
	cx = r[0] + r[2] / 2
	if self.scroll > 0 then rl.DrawTriangle [cx, r[1] + 3], [cx - 6, r[1] + 10], [cx + 6, r[1] + 10], pal.border
	if self.scroll < maxScroll then
		b = r[1] + r[3]
		rl.DrawTriangle [cx - 6, b - 10], [cx, b - 3], [cx + 6, b - 10], pal.border
	end if
end function

//----------------------------------------------------------------------
// Toolbar
//----------------------------------------------------------------------

// [command, icon, title, shortcut, center x], laid out as in MM1.
_toolDefs = [
  ["close", "Close", "Close", "^W", 21],
  ["save", "Save", "Save", "^S", 59],
  ["revert", "Revert", "Revert", "", 98],
  ["run", "RunButton", "Close & Run", "^R", 159],
  ["undo", "Undo", "Undo", "^Z", 221],
  ["redo", "Redo", "Redo", "Shift-^Z", 259],
  ["cut", "Cut", "Cut", "^X", 319],
  ["copy", "Copy", "Copy", "^C", 358],
  ["paste", "Paste", "Paste", "^V", 399],
  ["find", "Find", "Find/Replace", "^F", 460],
  ["navigate", "Jump", "Navigate", "", 500],
  ["code", "Insert", "Code", "", 540],
  ["help", "Help", "Help", "^?", 943]]

Toolbar = {}
Toolbar.pathX = 569
Toolbar.autoSaveX = 815

Toolbar.Make = function
	tb = new Toolbar
	tb.buttons = []
	for d in _toolDefs
		b = Button.Make("", "tool")
		b.cmd = d[0]
		b.icon = d[1]
		b.title = d[2]
		b.shortcut = d[3]
		b.cx = d[4]
		tb.buttons.push b
	end for
	tb.autoSave = {"rect": [0, 0, 0, 0], "visible": false}
	tb.hover = null
	tb._clipTime = -99
	tb._canPaste = false
	return tb
end function

Toolbar.layout = function(ed)
	left = Display.screenLeft
	top = Display.screenTop
	for b in self.buttons
		b.rect = [left + b.cx - 16, top + 2, 32, 32]
	end for
	self.autoSave.rect = [left + self.autoSaveX, top + 8, 106, 20]
	self.autoSave.visible = (ed.path != null and ed.path != "")
end function

Toolbar.refresh = function(ed, inp)
	// Reading the system clipboard is not free; twice a second is plenty.
	if time - self._clipTime > 0.5 then
		self._clipTime = time
		self._canPaste = (rl.GetClipboardText != "")
	end if
	for b in self.buttons
		if b.cmd == "undo" then b.enabled = ed.canUndo
		if b.cmd == "redo" then b.enabled = ed.canRedo
		if b.cmd == "cut" or b.cmd == "copy" then b.enabled = ed.hasSelection
		if b.cmd == "paste" then b.enabled = self._canPaste
		if b.cmd == "save" then
			if inp.shift then
				b.title = "Save As"
				b.shortcut = "Shift-^S"
			else
				b.title = "Save"
				b.shortcut = "^S"
			end if
		end if
	end for
end function

// Returns the command clicked, if any.
Toolbar.update = function(ed, inp)
	self.layout ed
	self.refresh ed, inp
	result = null
	self.hover = null
	for b in self.buttons
		if b.handleMouse(inp) then result = b.cmd
		if _inRect(inp.mouse, b.rect) then self.hover = b
	end for
	if self.autoSave.visible and inp.pressed and _inRect(inp.mouse, self.autoSave.rect) then
		ed.setAutoSave not ed.autoSave
	end if
	if result == "save" and inp.shift then result = "saveAs"
	return result
end function

Toolbar.draw = function(ed)
	left = Display.screenLeft
	top = Display.screenTop
	h = ed.toolbarHeight
	rl.DrawRectangle left, top, Display.screenWidth, h, pal.toolbar
	rl.DrawRectangle left, top + h - 1, Display.screenWidth, 1, pal.divider
	for b in self.buttons
		b.draw
	end for

	pathW = self.autoSaveX - self.pathX - 12
	if not self.autoSave.visible then pathW = 920 - self.pathX
	r = [left + self.pathX, top, pathW, h]
	msg = ed.statusMessage
	if msg then
		if msg[1] then c = pal.error else c = [0, 110, 0, 255]
		drawTextIn fitLeft(msg[0], pathW), r[0], r, c
	else if ed.path then
		drawTextIn fitLeft(ed.path, pathW), r[0], r
	end if

	if self.autoSave.visible then
		ar = self.autoSave.rect
		drawCheckbox ar[0], ar[1] + 2, ed.autoSave
		drawTextIn "Auto-Save", ar[0] + 22, ar, null, true
	end if
end function

// The help tag under the button the mouse is over.
Toolbar.drawTag = function(ed)
	b = self.hover
	if b == null then return
	s = b.title
	if b.shortcut then s += " (" + b.shortcut + ")"
	w = textWidth(s) + 16
	x = b.rect[0] + 16 - w / 2
	x = _clamp(x, Display.screenLeft, Display.screenLeft + Display.screenWidth - w)
	r = [round(x), Display.screenTop + ed.toolbarHeight + 2, w, 24]
	roundRect [r[0] + 2, r[1] + 3, r[2], r[3]], 5, pal.shadow
	roundRect r, 5, pal.tag
	roundRectLines r, 5, pal.border
	drawTextIn s, r[0] + 8, r
end function

//----------------------------------------------------------------------
// Dialogs.  A dialog is modal: while one is up it gets all the input.
// update returns true when the dialog is done.
//----------------------------------------------------------------------

Dialog = {}
Dialog.title = ""
Dialog.w = 400
Dialog.h = 200
Dialog.headerH = 24		// the frame sprite's title bar, at half size
Dialog.tint = [215, 236, 255, 255]
Dialog.buttonTint = [209, 230, 255, 255]

Dialog.layout = function
	x = Display.screenLeft + (Display.screenWidth - self.w) / 2
	y = Display.screenTop + (Display.screenHeight - self.h) / 2 - 40
	self.rect = [round(x), round(y), self.w, self.h]
end function

// Cancel and OK buttons, at the bottom right.
Dialog.makeButtons = function(okLabel)
	r = self.rect
	self.cancelBtn = Button.Make("Cancel")
	self.okBtn = Button.Make(okLabel)
	self.cancelBtn.tint = self.buttonTint
	self.okBtn.tint = self.buttonTint
	y = r[1] + r[3] - 34
	self.okBtn.rect = [r[0] + r[2] - 96, y, 80, 22]
	self.cancelBtn.rect = [r[0] + r[2] - 184, y, 80, 22]
end function

// "ok", "cancel", or null, from the buttons, Return and Escape.
Dialog.checkButtons = function(inp, fieldKey=null)
	if fieldKey == "escape" or rl.IsKeyPressed(rl.KEY_ESCAPE) then return "cancel"
	if fieldKey == "enter" or rl.IsKeyPressed(rl.KEY_ENTER) or rl.IsKeyPressed(rl.KEY_KP_ENTER) then return "ok"
	if self.cancelBtn.handleMouse(inp) then return "cancel"
	if self.okBtn.handleMouse(inp) then return "ok"
	return null
end function

Dialog.drawFrame = function
	rl.DrawRectangle Display.screenLeft, Display.screenTop, Display.screenWidth, Display.screenHeight, pal.scrim
	r = self.rect
	if UI.icons.hasIndex("DialogUI") then
		// The sprite carries its own drop shadow: 16 pixels either side and
		// 32 below, at full size.
		m = 16 * spriteScale
		nineSlice sprites.dialog, [r[0] - m, r[1], r[2] + m*2, r[3] + m*2], self.tint
	else
		roundRect r, 10, pal.white
		roundRectLines r, 10, pal.border, 1.5
	end if
	hr = [r[0], r[1], r[2], self.headerH]
	drawTextIn self.title, r[0] + floor((r[2] - textWidth(self.title, true)) / 2), hr, pal.white, true
end function

Dialog.drawButtons = function
	self.cancelBtn.draw
	self.okBtn.draw
end function

//----------------------------------------------------------------------

GoToDialog = new Dialog
GoToDialog.title = "Jump to Line"
GoToDialog.w = 320
GoToDialog.h = 130

GoToDialog.Make = function(ed)
	d = new GoToDialog
	d.layout
	d.field = TextField.Make(str(ed.pos[0] + 1))
	d.field.rect = [d.rect[0] + 140, d.rect[1] + d.headerH + 14, 160, 26]
	d.makeButtons "Go"
	return d
end function

GoToDialog.update = function(ed, inp)
	self.field.handleMouse inp
	which = self.checkButtons(inp, self.field.handleKeys(inp))
	if which == "cancel" then return true
	if which == "ok" then
		n = val(self.field.text)
		if n >= 1 then
			ed.jumpToLine n - 1
			return true
		end if
		self.field.selectAll
	end if
	return false
end function

GoToDialog.draw = function(ed)
	self.drawFrame
	f = self.field.rect
	drawTextIn "Line number:", self.rect[0] + 18, f
	self.field.draw true
	self.drawButtons
end function

//----------------------------------------------------------------------

SaveAsDialog = new Dialog
SaveAsDialog.title = "Save As"
SaveAsDialog.w = 500
SaveAsDialog.h = 170

SaveAsDialog.Make = function(ed)
	d = new SaveAsDialog
	d.layout
	if ed.path then
		d.dir = file.parent(ed.path)
		name = file.name(ed.path)
	else
		d.dir = file.curdir
		name = "untitled.ms"
	end if
	d.field = TextField.Make(name)
	// Select the name but not its extension, so typing replaces just that.
	dot = name.len - 1
	while dot > 0 and name[dot] != "."
		dot -= 1
	end while
	if dot > 0 then d.field.caret = dot
	d.field.rect = [d.rect[0] + 100, d.rect[1] + d.headerH + 44, d.w - 118, 26]
	d.error = ""
	d.makeButtons "Save"
	return d
end function

SaveAsDialog.update = function(ed, inp)
	self.field.handleMouse inp
	which = self.checkButtons(inp, self.field.handleKeys(inp))
	if which == "cancel" then return true
	if which != "ok" then return false
	name = self.field.text
	if name == "" then
		self.error = "File name required."
		return false
	end if
	if name[0] == "/" then path = name else path = file.child(self.dir, name)
	if file.name(path).indexOf(".") == null then path += ".ms"
	info = file.info(file.parent(path))
	if info == null or not info.isDirectory then
		self.error = "Invalid path."
		return false
	end if
	err = ed.writeFile(path)
	if err then
		self.error = err
		return false
	end if
	return true
end function

SaveAsDialog.draw = function(ed)
	self.drawFrame
	r = self.rect
	y = r[1] + self.headerH + 12
	drawText "Save in:", r[0] + 18, y
	dir = self.dir
	if dir[-1] != "/" then dir += "/"
	drawText fitLeft(dir, r[2] - 118), r[0] + 100, y
	drawTextIn "Name:", r[0] + 18, self.field.rect
	self.field.draw true
	if self.error then drawText self.error, r[0] + 18, r[1] + r[3] - 33, pal.error
	self.drawButtons
end function

//----------------------------------------------------------------------

// MM1's palette, in its order: clear first (drawn with an X), then the rest.
_colorNames = ("clear black white gray silver maroon red olive yellow orange " +
  "green lime teal aqua navy blue purple fuchsia brown pink").split

_hex2 = function(n)
	digits = "0123456789ABCDEF"
	return digits[floor(n / 16)] + digits[n % 16]
end function

// Laid out as MM1's InsertColorDialog: four sliders over a preview, the
// color string, then the palette.  Positions are from the dialog's top left.
InsertColorDialog = new Dialog
InsertColorDialog.title = "Insert Color"
InsertColorDialog.w = 240
InsertColorDialog.h = 447
InsertColorDialog.lastRGBA = [255, 255, 255, 255]	// it opens as it was last left
InsertColorDialog.lastName = null
InsertColorDialog.sliderNames = ["Red", "Green", "Blue", "Alpha"]

InsertColorDialog.Make = function(ed)
	d = new InsertColorDialog
	d.layout
	d.rgba = InsertColorDialog.lastRGBA[:]
	d.name = InsertColorDialog.lastName
	d.fields = []
	r = d.rect
	for k in range(0, 3)
		f = TextField.Make("")
		f.rect = [r[0] + 170, r[1] + 50 + k * 48, 45, 26]
		d.fields.push f
	end for
	d.focus = 0
	d.active = -1
	d.makeButtons "Insert"
	d.cancelBtn.rect = [r[0] + 40, r[1] + 415, 72, 20]
	d.okBtn.rect = [r[0] + 128, r[1] + 415, 72, 20]
	d._syncFields
	return d
end function

InsertColorDialog._track = function(k)
	return [self.rect[0] + 29, self.rect[1] + 55 + k * 48, 128, 16]
end function

// The thumb's center x for a value: it travels the track less its ends.
InsertColorDialog._thumbX = function(k, v)
	t = self._track(k)
	return t[0] + 6 + v / 255 * (t[2] - 12)
end function

InsertColorDialog._swatch = function(i)
	r = self.rect
	return [r[0] + 22 + (i % 10) * 20, r[1] + 347 + floor(i / 10) * 20, 16, 16]
end function

InsertColorDialog._syncFields = function
	for k in range(0, 3)
		self.fields[k].setText str(self.rgba[k])
	end for
end function

InsertColorDialog.colorString = function
	if self.name then return self.name
	s = "#"
	for v in self.rgba
		s += _hex2(v)
	end for
	return """" + s + """"
end function

InsertColorDialog.update = function(ed, inp)
	m = inp.mouse
	if inp.pressed then
		for i in _colorNames.indexes
			if _inRect(m, self._swatch(i)) then
				self.rgba = color.toList(color[_colorNames[i]])[:]
				self.name = "color." + _colorNames[i]
				self._syncFields
			end if
		end for
		for k in range(0, 3)
			t = self._track(k)
			if _inRect(m, [t[0], t[1], t[2], t[3] + 10]) then self.active = k
		end for
	end if
	if self.active >= 0 then
		if inp.down then
			t = self._track(self.active)
			self.rgba[self.active] = round(_clamp((m.x - t[0] - 6) / (t[2] - 12), 0, 1) * 255)
			self.name = null
			self.fields[self.active].setText str(self.rgba[self.active])
		else
			self.active = -1
		end if
	end if
	for k in range(0, 3)
		if self.fields[k].handleMouse(inp) then self.focus = k
	end for
	f = self.fields[self.focus]
	fk = f.handleKeys(inp)
	if fk == "changed" then
		self.rgba[self.focus] = _clamp(round(val(f.text)), 0, 255)
		self.name = null
	else if fk == "tab" then
		f.setText str(self.rgba[self.focus])
		if inp.shift then self.focus = (self.focus + 3) % 4 else self.focus = (self.focus + 1) % 4
		self.fields[self.focus].selectAll
	end if
	which = self.checkButtons(inp, fk)
	if which == "cancel" then return true
	if which == "ok" then
		InsertColorDialog.lastRGBA = self.rgba[:]
		InsertColorDialog.lastName = self.name
		ed.setSelText self.colorString
		return true
	end if
	return false
end function

InsertColorDialog.draw = function(ed)
	self.drawFrame
	r = self.rect
	c = self.rgba
	haveArt = UI.icons.hasIndex("ColorSliders") and UI.icons.hasIndex("DialogUI")
	for k in range(0, 3)
		t = self._track(k)
		drawText self.sliderNames[k], t[0], t[1] - 16, pal.text, true
		if haveArt then
			// ColorSliders.png: one 256x32 track per channel, top to bottom.
			rl.DrawTexturePro UI.icons.ColorSliders, [0, k * 32, 256, 32], t, [0, 0], 0, pal.white
		else
			hi = [0, 0, 0, 255]
			hi[k % 3] = 255
			rl.DrawRectangleGradientH t[0], t[1], t[2], t[3], [0, 0, 0, 255], hi
		end if
		x = self._thumbX(k, c[k])
		ts = sprites.thumb[0]
		tw = ts[2] * spriteScale
		th = ts[3] * spriteScale
		if haveArt then
			rl.DrawTexturePro UI.icons.DialogUI, ts, [round(x - tw/2), t[1] + 9, tw, th], [0, 0], 0, pal.white
		else
			rl.DrawTriangle [x, t[1] + 9], [x - 6, t[1] + 9 + th], [x + 6, t[1] + 9 + th], pal.text
		end if
		self.fields[k].draw k == self.focus
	end for

	// Preview: the color over a checkerboard, so alpha shows.
	pv = [r[0] + 20, r[1] + 239, 200, 80]
	drawChecker pv, 8
	rl.DrawRectangleLines pv[0], pv[1], pv[2], pv[3], pal.divider
	rl.DrawRectangle pv[0] + 27, pv[1] + 10, pv[2] - 54, pv[3] - 20, c
	s = self.colorString
	drawText s, r[0] + floor((r[2] - textWidth(s, true)) / 2), r[1] + 324, pal.text, true

	for i in _colorNames.indexes
		sw = self._swatch(i)
		sc = color.toList(color[_colorNames[i]])
		rl.DrawRectangle sw[0], sw[1], sw[2], sw[3], pal.white
		rl.DrawRectangle sw[0], sw[1], sw[2], sw[3], sc
		rl.DrawRectangleLines sw[0], sw[1], sw[2], sw[3], pal.border
		if sc[3] == 0 then
			rl.DrawLine sw[0] + 3, sw[1] + 3, sw[0] + sw[2] - 3, sw[1] + sw[3] - 3, pal.border
			rl.DrawLine sw[0] + sw[2] - 3, sw[1] + 3, sw[0] + 3, sw[1] + sw[3] - 3, pal.border
		end if
	end for
	self.drawButtons
end function

//----------------------------------------------------------------------

_helpRows = [
  ["^S / Shift-^S", "Save / Save As"],
  ["^W", "Close the editor"],
  ["^R", "Close and run"],
  ["^Z / Shift-^Z", "Undo / Redo  (also F1 / Shift-F1)"],
  ["^X ^C ^V", "Cut, Copy, Paste  (also F2, F3, F4)"],
  ["^A", "Select all"],
  ["^F", "Find and replace"],
  ["^J", "Jump to line"],
  ["^/", "Comment or uncomment lines"],
  ["^[  ^]", "Shift lines left or right"],
  ["Shift-Return", "New line, plus the block's ""end"""],
  ["Tab / Shift-Tab", "Next / previous _placeholder_"],
  ["Alt-arrows", "Move by word"],
  ["Double-click", "Select a word, or between brackets"]]

HelpDialog = new Dialog
HelpDialog.title = "Code Editor Help"
HelpDialog.w = 600
HelpDialog.h = 470

HelpDialog.Make = function(ed)
	d = new HelpDialog
	d.layout
	d.makeButtons "OK"
	return d
end function

HelpDialog.update = function(ed, inp)
	return self.checkButtons(inp) != null
end function

HelpDialog.draw = function(ed)
	self.drawFrame
	r = self.rect
	y = r[1] + self.headerH + 12
	for row in _helpRows
		drawText row[0], r[0] + 24, y, [68, 68, 170, 255]
		drawText row[1], r[0] + 210, y
		y += 24
	end for
	drawText "^ means Ctrl, or Cmd on a Mac.", r[0] + 24, y + 6, pal.dimText
	drawText "More: miniscript.org/wiki/Mini_Micro", r[0] + 24, y + 30, pal.dimText
	self.okBtn.draw
end function

//----------------------------------------------------------------------
// FindPanel: Find/Replace, docked under the code (MM1's EditorBottomPanel
// and FindResultsList).  Results start out checked; "Replace N" replaces
// the checked ones.
//----------------------------------------------------------------------

FindPanel = {}
FindPanel.height = 244
FindPanel.rowH = 24
FindPanel.listTop = 40		// from the panel's top
FindPanel.scrollbarSize = 17

FindPanel.Make = function(ed)
	p = new FindPanel
	initial = ""
	if ed.hasSelection and ed.selFirst[0] == ed.selLast[0] then initial = ed.selectedText
	p.findField = TextField.Make(initial)
	p.replField = TextField.Make("")
	p.replField.placeholder = "Enter replacement text..."
	p.field = p.findField
	p.toggles = []
	srcs = [[0, 0, 66, 64], [66, 0, 66, 64], [132, 0, 66, 64]]
	titles = ["Match Case", "Whole Words", "Selection Only"]
	for i in range(0, 2)
		b = Button.Make("", "toggle")
		b.icon = "SearchOptIcons"
		b.src = srcs[i]
		b.title = titles[i]
		p.toggles.push b
	end for
	p.replBtn = Button.Make("Replace 0")
	p.results = []
	p.status = "Text"
	p.scroll = 0
	p.selRow = -1
	p.layout
	p.search ed
	return p
end function

FindPanel.top = function
	return Display.screenTop + Display.screenHeight - self.height
end function

FindPanel.layout = function
	left = Display.screenLeft
	t = self.top
	x = left + 9 + textWidth("Find:", true) + 6
	self.findField.rect = [x, t + 8, 334 - 8 - x + left, 24]
	for i in range(0, 2)
		self.toggles[i].rect = [left + 334 + i * 36, t + 6, 32, 28]
	end for
	self.replLabelX = left + 451
	x = self.replLabelX + textWidth("Replace with:", true) + 6
	self.replBtn.rect = [left + 852, t + 8, 102, 24]
	self.replField.rect = [x, t + 8, self.replBtn.rect[0] - 10 - x, 24]
	self.listRect = [left, t + self.listTop, Display.screenWidth, self.height - self.listTop]
end function

FindPanel.checkedCount = function
	n = 0
	for m in self.results
		if m.checked then n += 1
	end for
	return n
end function

FindPanel._typeAt = function(ed, lineNum, idx)
	for tok in ed.tokensAt(lineNum)
		if tok[0] <= idx < tok[1] then
			if tok[2] == "comment" then return "comment"
			if tok[2] == "string" or tok[2] == "openString" then return "string"
			return "code"
		end if
	end for
	return "code"
end function

FindPanel.search = function(ed)
	self.results = []
	self.scroll = 0
	self.selRow = -1
	pat = self.findField.text
	if pat == "" then
		self.status = "Text"
		return
	end if
	ignoreCase = not self.toggles[0].on
	wholeWords = self.toggles[1].on
	if ignoreCase then pat = pat.lower
	a = 0
	b = ed.lines.len - 1
	if self.toggles[2].on then
		a = ed.selFirst[0]
		b = ed.selLast[0]
	end if
	isW = @ed.mode.isWordChar
	for i in range(a, b)
		s = ed.lines[i]
		hay = s
		if ignoreCase then hay = s.lower
		start = 0
		while start <= hay.len - pat.len
			if start == 0 then j = hay.indexOf(pat) else j = hay.indexOf(pat, start - 1)
			if j == null then break
			start = j + 1
			if wholeWords then
				if j > 0 and isW(s[j-1]) then continue
				e = j + pat.len
				if e < s.len and isW(s[e]) then continue
			end if
			m = {"line": i, "start": j, "len": pat.len, "text": s, "checked": true, "replaced": false}
			m.type = self._typeAt(ed, i, j)
			self.results.push m
			start = j + pat.len
		end while
	end for
	n = self.results.len
	self.status = n + " occurrence" + "s" * (n != 1) + " found"
end function

FindPanel.replace = function(ed)
	rep = self.replField.text
	count = 0
	for idx in self.results.indexes
		m = self.results[idx]
		if not m.checked then continue
		m.checked = false
		s = ed.lines[m.line]
		e = m.start + m.len
		// The line may have changed since we searched; skip what no longer matches.
		if s[m.start:e] != m.text[m.start:e] then continue
		if count == 0 then ed.storeUndo
		ns = s[:m.start] + rep + s[e:]
		ed._setLine m.line, ns
		dlen = rep.len - m.len
		m.text = ns
		m.len = rep.len
		m.replaced = true
		for later in self.results[idx+1:]
			if later.line != m.line then break
			later.text = ns
			later.start += dlen
		end for
		count += 1
	end for
	if count then ed.noteEdited
	self.status = count + " occurrence" + "s" * (count != 1) + " replaced"
end function

FindPanel._maxScroll = function
	return _max(0, self.results.len * self.rowH - self.listRect[3] + 22)
end function

// The scrollbar's track and thumb rects; the thumb is null when everything fits.
FindPanel._scrollRects = function
	lr = self.listRect
	sb = self.scrollbarSize
	track = [lr[0] + lr[2] - sb, lr[1] + 22, sb, lr[3] - 22]
	total = self.results.len * self.rowH
	if total <= track[3] then return [track, null]
	th = _max(20, track[3] * track[3] / total)
	ty = track[1] + (track[3] - th) * self.scroll / self._maxScroll
	return [track, [track[0] + 3, ty, sb - 6, th]]
end function

// Drag the thumb, or click the track to page.  True if the scrollbar has the mouse.
FindPanel._handleScrollbar = function(inp)
	if self._drag then
		if not inp.down then
			self._drag = null
		else
			sr = self._scrollRects
			if sr[1] then
				span = sr[0][3] - sr[1][3]
				self.scroll = _clamp(self._drag[1] + (inp.mouse.y - self._drag[0]) * self._maxScroll / span, 0, self._maxScroll)
			end if
		end if
		return true
	end if
	if not inp.pressed then return false
	sr = self._scrollRects
	if not _inRect(inp.mouse, sr[0]) then return false
	thumb = sr[1]
	if thumb == null then return true
	page = sr[0][3] - self.rowH
	if inp.mouse.y < thumb[1] then
		self.scroll = _max(0, self.scroll - page)
	else if inp.mouse.y >= thumb[1] + thumb[3] then
		self.scroll = _min(self._maxScroll, self.scroll + page)
	else
		self._drag = [inp.mouse.y, self.scroll]
	end if
	return true
end function
FindPanel._drag = null

FindPanel.selectRow = function(ed, i)
	if i < 0 or i >= self.results.len then return
	self.selRow = i
	m = self.results[i]
	ed.jumpToLine m.line - 4
	ed.setSelection [m.line, m.start], [m.line, m.start + m.len]
	// Keep the row in view, too.
	y = i * self.rowH
	visH = self.listRect[3] - 22
	if y < self.scroll then self.scroll = y
	if y + self.rowH > self.scroll + visH then self.scroll = y + self.rowH - visH
end function

// Returns true if the mouse was the panel's this frame.
FindPanel.update = function(ed, inp)
	self.layout
	panel = [Display.screenLeft, self.top, Display.screenWidth, self.height]
	inside = _inRect(inp.mouse, panel)
	if self.findField.handleMouse(inp) then
		self.field = self.findField
		ed.focus = "find"
	end if
	if self.replField.handleMouse(inp) then
		self.field = self.replField
		ed.focus = "find"
	end if
	for b in self.toggles
		if b.handleMouse(inp) then
			b.on = not b.on
			self.search ed
		end if
	end for
	self.replBtn.enabled = self.checkedCount > 0
	if self.replBtn.handleMouse(inp) then self.replace ed

	lr = self.listRect
	rows = [lr[0], lr[1] + 22, lr[2] - self.scrollbarSize, lr[3] - 22]
	if _inRect(inp.mouse, lr) and inp.wheel.y != 0 then
		self.scroll = _clamp(self.scroll - inp.wheel.y * self.rowH * 2, 0, self._maxScroll)
	end if
	// A drag that started on the thumb keeps the mouse wherever it goes.
	if self._handleScrollbar(inp) then inside = true
	if self._drag == null and inp.pressed and _inRect(inp.mouse, rows) then
		i = floor((inp.mouse.y - rows[1] + self.scroll) / self.rowH)
		if 0 <= i < self.results.len then
			if inp.mouse.x >= rows[0] + rows[2] - 34 then
				// Shift, alt or cmd-click sets every row the same way, as in MM1.
				v = not self.results[i].checked
				if inp.shift or inp.alt or inp.cmd then
					for m in self.results
						m.checked = v
					end for
				else
					self.results[i].checked = v
				end if
			else
				self.selectRow ed, i
				ed.focus = null
			end if
		end if
	end if
	if inp.pressed and _inRect(inp.mouse, [lr[0] + lr[2] - 34, lr[1], 34, 22]) then
		// The check-mark header toggles them all.
		v = self.checkedCount < self.results.len
		for m in self.results
			m.checked = v
		end for
	end if
	self.replBtn.label = "Replace " + self.checkedCount

	if ed.focus == "find" then
		k = self.field.handleKeys(inp)
		if k == "changed" and self.field == self.findField then self.search ed
		if k == "tab" then
			if self.field == self.findField then self.field = self.replField else self.field = self.findField
			self.field.selectAll
		end if
		if k == "escape" then ed.closeFind
		if k == "enter" then
			if self.field == self.findField then
				if self.selRow < 0 then self.search ed
				if self.results then self.selectRow ed, (self.selRow + 1) % self.results.len
			else if self.replBtn.enabled then
				self.replace ed
			end if
		end if
		if keyHit(rl.KEY_DOWN) then self.selectRow ed, self.selRow + 1
		if keyHit(rl.KEY_UP) then self.selectRow ed, self.selRow - 1
	end if
	return inside
end function

_typeLabels = {"code": "code", "string": """str""", "comment": "// ..."}
_typeColors = {"code": [51, 51, 51, 255], "string": [204, 0, 0, 255], "comment": [102, 102, 102, 255]}

FindPanel.draw = function(ed)
	left = Display.screenLeft
	w = Display.screenWidth
	t = self.top
	rl.DrawRectangle left, t, w, self.listTop, pal.panel
	rl.DrawRectangle left, t, w, 1, pal.border
	drawTextIn "Find:", left + 9, self.findField.rect, null, true
	self.findField.draw ed.focus == "find" and self.field == self.findField
	for b in self.toggles
		b.draw
	end for
	drawTextIn "Replace with:", self.replLabelX, self.replField.rect, null, true
	self.replField.draw ed.focus == "find" and self.field == self.replField
	self.replBtn.draw

	lr = self.listRect
	sb = self.scrollbarSize
	checkX = lr[0] + lr[2] - sb - 34
	// Header
	hr = [lr[0], lr[1], lr[2], 22]
	rl.DrawRectangle hr[0], hr[1], hr[2], hr[3], pal.header
	rl.DrawRectangle hr[0], hr[1] + 21, hr[2], 1, pal.divider
	drawTextIn "Line", lr[0] + 3, hr, null, true
	drawTextIn "Type", lr[0] + 62, hr, null, true
	drawTextIn self.status, lr[0] + 122, hr, null, true
	drawCheck checkX + 9, hr[1] + 3, 16, pal.text
	for x in [57, 117]
		rl.DrawRectangle lr[0] + x, hr[1], 1, 22, pal.divider
	end for
	rl.DrawRectangle checkX, hr[1], 1, 22, pal.divider

	// Rows
	rows = [lr[0], lr[1] + 22, lr[2] - sb, lr[3] - 22]
	rl.DrawRectangle rows[0], rows[1], lr[2], rows[3], pal.listBack
	rl.BeginScissorMode rows[0], rows[1], rows[2], rows[3]
	rh = self.rowH
	first = floor(self.scroll / rh)
	cw = UI.charW
	textX = lr[0] + 122
	maxChars = floor((checkX - textX - 6) / cw)
	for i in range(first, first + ceil(rows[3] / rh))
		if i >= self.results.len then break
		m = self.results[i]
		y = rows[1] + i * rh - self.scroll
		rr = [rows[0], y, rows[2], rh]
		if i == self.selRow then rl.DrawRectangle rr[0], rr[1], rr[2], rr[3], pal.selection
		num = str(m.line + 1)
		drawTextIn "0" * _max(0, 4 - num.len) + num, lr[0] + 3, rr
		label = _typeLabels[m.type]
		drawTextIn label, lr[0] + 87 - textWidth(label) / 2, rr, _typeColors[m.type]
		// Trim the left of a long line so the match stays in view.
		s = m.text.replace(TAB, " ")
		st = m.start
		trim = _min(st, _max(0, st + m.len - maxChars))
		s = s[trim:trim + maxChars]
		st -= trim
		if m.replaced then hc = pal.replaced else hc = pal.match
		rl.DrawRectangle textX + st * cw, y + 2, m.len * cw, rh - 4, hc
		drawTextIn s, textX, rr
		drawCheckbox checkX + 9, y + 4, m.checked
	end for
	rl.EndScissorMode

	// Scrollbar
	sr = self._scrollRects
	t = sr[0]
	rl.DrawRectangle t[0], t[1], t[2], t[3], [243, 244, 243, 255]
	if sr[1] then roundRect sr[1], 5, [190, 190, 190, 255]
end function

//----------------------------------------------------------------------

EditorUI = {}
EditorUI.UI = UI
EditorUI.pal = pal
EditorUI.roundRect = @roundRect
EditorUI.loadIcons = @loadIcons
EditorUI.readInput = @readInput
EditorUI.keyHit = @keyHit
EditorUI.chord = @chord
EditorUI.TextField = TextField
EditorUI.Button = Button
EditorUI.Menu = Menu
EditorUI.Toolbar = Toolbar
EditorUI.GoToDialog = GoToDialog
EditorUI.SaveAsDialog = SaveAsDialog
EditorUI.InsertColorDialog = InsertColorDialog
EditorUI.HelpDialog = HelpDialog
EditorUI.FindPanel = FindPanel
return EditorUI
