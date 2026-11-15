// TextMode: what the editor knows about one kind of file.
//
// The editor never lexes anything itself.  It asks the mode for each line's
// tokens, caches them along with the state the line ends in, and hands the
// cached tokens to every feature that needs them (styling, indentation,
// enders, bracket matching).  This base class is plain text: no styling, and
// every optional feature off.  Subclasses override only what they support.
//
// A token is [startIndex, endIndex, style], endIndex exclusive, indexed in
// characters of the line (not screen columns; the editor expands tabs).
// Bracket tokens carry a fourth element, the nesting depth inside them, so the
// renderer can rotate colors.  Text no token covers is drawn unstyled.
//
// Line state is whatever a mode needs to carry from one line to the next, and
// must compare with == so the editor can tell when re-styling may stop.  null
// means "nothing carried", and is the state the first line starts in.

TextMode = {}
TextMode.name = "Text"

// Return [tokens, stateOut] for one line.
TextMode.styleLine = function(text, stateIn)
	return [[], null]
end function

// Return [outdentThis, indentNext] for one line, given its tokens; or null
// if this mode does no auto-indentation.
TextMode.indentEffect = null

// Return the closing line ("end while" etc.) for the innermost open block
// above the given line, or null.  Takes the editor's line list and a function
// that returns cached tokens for a line number.
TextMode.findEnder = null

// Return a list of [lineNum, label] for the Navigate menu, or null.
TextMode.navItems = null

// Whether a line ending in this state continues onto the next (which the
// indenter marks with two extra spaces).
TextMode.isContinued = function(stateOut)
	return false
end function

// Characters that make up a "word" for double-click and word-wise movement.
TextMode.isWordChar = function(c)
	return c and ("a" <= c <= "z" or "A" <= c <= "Z" or
	  "0" <= c <= "9" or c == "_" or code(c) > 127)
end function

return TextMode
