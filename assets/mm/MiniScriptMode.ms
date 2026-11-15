// MiniScriptMode: styling, indentation, and navigation for MiniScript source.
//
// This is not the language's lexer and must not become one.  It is lossless
// (every comment, quote and operator keeps its exact span), it never fails
// (an unclosed string is an "openString" token, an unknown character is just
// left unstyled), and it works one line at a time, so it can style code that
// is half typed.  Keep it in step with MiniScript2's Lexer.cs by hand.
//
// Styles: keyword identifier number string openString comment operator colon
// separator paren square brace.  Keywords carry their normalized text as a
// fourth element, with "end while" and "else if" each one token, as the
// indenter wants them.  Brackets carry nesting depth (0 for an unmatched
// closer).
//
// Line state is null, or [parenDepth, squareDepth, braceDepth] when the line
// continues onto the next, which is the only time depth carries over.

import "TextMode"

MiniScriptMode = new TextMode
MiniScriptMode.name = "MiniScript"

TAB = char(9)

_keywords = {}
for w in ("and or not while for in if then else break continue function " +
  "return new isa self super locals outer globals end true false null").split
	_keywords[w] = true
end for

// Words that may follow "end", making one keyword of the two.
_enders = {"while":1, "for":1, "if":1, "function":1}

_identChars = {}
for c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789"
	_identChars[c] = true
end for
_digits = {}
for c in "0123456789"
	_digits[c] = true
end for

// Operator tables are strings and lists, not maps, because a map key ending
// in "=" is a property setter in MS2, and most of these end in "=".
_opChars = "+-*/%^=<>.@,"
_takesEquals = "=!<>+-*/%^"		// c followed by "=" is one operator

// Final tokens after which an EOL is a line continuation (Parser.cs,
// AllowsLineContinuation).
_continuers = ", ( [ { + - * / % ^ == != < > <= >= and or isa : = += -= *= /= %= ^=".split

_isIdentChar = function(c)
	return _identChars.hasIndex(c) or (code(c) > 127 and c != char(160))
end function

MiniScriptMode.styleLine = function(text, stateIn)
	toks = []
	if stateIn then
		pd = stateIn[0]; sd = stateIn[1]; bd = stateIn[2]
	else
		pd = 0; sd = 0; bd = 0
	end if
	n = text.len
	i = 0
	last = null		// text of the last significant token
	while i < n
		c = text[i]
		if c == " " or c == TAB then
			i += 1
			continue
		end if
		start = i
		if c == "/" and i+1 < n and text[i+1] == "/" then
			toks.push [start, n, "comment"]
			break
		end if
		if c == """" then
			i += 1
			closed = false
			while i < n
				if text[i] == """" then
					if i+1 < n and text[i+1] == """" then
						i += 2
						continue
					end if
					closed = true
					i += 1
					break
				end if
				i += 1
			end while
			if closed then toks.push [start, i, "string"] else toks.push [start, i, "openString"]
			last = "string"
			continue
		end if
		if _digits.hasIndex(c) or (c == "." and i+1 < n and _digits.hasIndex(text[i+1])) then
			while i < n and _digits.hasIndex(text[i])
				i += 1
			end while
			if i+1 < n and text[i] == "." and _digits.hasIndex(text[i+1]) then
				i += 1
				while i < n and _digits.hasIndex(text[i])
					i += 1
				end while
			end if
			if i < n and (text[i] == "e" or text[i] == "E") then
				j = i + 1
				if j < n and (text[j] == "+" or text[j] == "-") then j += 1
				if j < n and _digits.hasIndex(text[j]) then
					i = j
					while i < n and _digits.hasIndex(text[i])
						i += 1
					end while
				end if
			end if
			toks.push [start, i, "number"]
			last = "number"
			continue
		end if
		if _isIdentChar(c) then
			i += 1
			while i < n and _isIdentChar(text[i])
				i += 1
			end while
			word = text[start:i]
			if not _keywords.hasIndex(word) then
				toks.push [start, i, "identifier"]
				last = word
				continue
			end if
			// "end while", "else if": one keyword, whatever the spacing.
			if word == "end" or word == "else" then
				j = i
				while j < n and (text[j] == " " or text[j] == TAB)
					j += 1
				end while
				k = j
				while k < n and _isIdentChar(text[k])
					k += 1
				end while
				if j > i and k > j then
					next = text[j:k]
					if (word == "end" and _enders.hasIndex(next)) or (word == "else" and next == "if") then
						word = word + " " + next
						i = k
					end if
				end if
			end if
			toks.push [start, i, "keyword", word]
			last = word
			continue
		end if
		if c == "(" then
			pd += 1
			toks.push [start, i+1, "paren", pd]
		else if c == ")" then
			toks.push [start, i+1, "paren", pd]
			if pd > 0 then pd -= 1
		else if c == "[" then
			sd += 1
			toks.push [start, i+1, "square", sd]
		else if c == "]" then
			toks.push [start, i+1, "square", sd]
			if sd > 0 then sd -= 1
		else if c == "{" then
			bd += 1
			toks.push [start, i+1, "brace", bd]
		else if c == "}" then
			toks.push [start, i+1, "brace", bd]
			if bd > 0 then bd -= 1
		else if i+1 < n and text[i+1] == "=" and _takesEquals.indexOf(c) != null then
			toks.push [start, i+2, "operator"]
			last = c + "="
			i += 2
			continue
		else if _opChars.indexOf(c) != null then
			toks.push [start, i+1, "operator"]
		else if c == ":" then
			toks.push [start, i+1, "colon"]
		else if c == ";" then
			toks.push [start, i+1, "separator"]
		else
			last = c	// unknown character: unstyled
			i += 1
			continue
		end if
		last = c
		i += 1
	end while
	if last != null and _continuers.indexOf(last) != null then return [toks, [pd, sd, bd]]
	return [toks, null]
end function

// State is non-null only when the line ends in a continuation token.
MiniScriptMode.isContinued = function(stateOut)
	return stateOut != null
end function

// The keyword text of a token, or null if it is not a keyword.
_kw = function(tok)
	if tok.len > 3 and tok[2] == "keyword" then return tok[3]
	return null
end function

// Ported from MM1's CodeEditor.IndentEffect.  A comment or ";" ends a
// statement, which is what the real lexer's EOL meant there.
MiniScriptMode.indentEffect = function(text, toks)
	outdentThis = 0
	indentNext = 0
	skip = false
	n = toks.len
	i = 0
	while i < n
		tok = toks[i]
		style = tok[2]
		if style == "separator" then
			skip = false
		else if not skip and style == "keyword" then
			w = tok[3]
			if w == "if" then
				// A block "if" ends with "then"; a one-line "if" has more after it.
				i += 1
				while i < n and toks[i][2] != "separator"
					if _kw(toks[i]) == "then" then
						if i+1 >= n or toks[i+1][2] == "comment" or toks[i+1][2] == "separator" then indentNext += 1
						skip = true
					end if
					i += 1
				end while
				continue
			else if w == "then" then
				if i+1 >= n or toks[i+1][2] == "comment" or toks[i+1][2] == "separator" then indentNext += 1
				skip = true
			else if w == "else" then
				outdentThis += 1
				indentNext += 1
				skip = true
			else if w == "else if" then
				outdentThis += 1
			else if w == "while" or w == "for" or w == "function" then
				indentNext += 1
				skip = true
			else if w[:3] == "end" then
				if indentNext > 0 then indentNext -= 1 else outdentThis += 1
			end if
		end if
		i += 1
	end while
	return [outdentThis, indentNext]
end function

// Ported from MM1's CodeEditor.FindDefaultEnder: the closer for the innermost
// block still open above lineNum.  tokensFor(i) returns line i's tokens.
MiniScriptMode.findEnder = function(lines, tokensFor, lineNum)
	closers = []
	for lineIdx in range(lineNum - 1, 0, -1)
		if lineIdx < 0 then break
		toks = tokensFor(lineIdx)
		onIf = false
		for ti in toks.indexes
			w = _kw(toks[ti])
			if w == null then continue
			if w[:4] == "end " then
				closers.push w
			else if w == "while" or w == "for" or w == "function" then
				onIf = false
				if closers and closers[-1] == "end " + w then
					closers.pop
				else
					return "end " + w
				end if
			else if w == "if" then
				onIf = true
			else if w == "then" and onIf then
				if ti+1 >= toks.len or toks[ti+1][2] == "comment" then
					if closers and closers[-1] == "end if" then
						closers.pop
					else
						return "end if"
					end if
				end if
			else if w == "else" or w == "else if" then
				onIf = false
				// An "end if" below still closes this block; leave it on the stack.
				if not closers or closers[-1] != "end if" then return "end if"
			end if
		end for
	end for
	return null
end function

// Function definitions: a line that starts `name = function` or
// `a.b.c = function`.
MiniScriptMode.navItems = function(lines, tokensFor)
	result = []
	for lineIdx in lines.indexes
		toks = tokensFor(lineIdx)
		i = 0
		while i < toks.len and (toks[i][2] == "identifier" or
		  (toks[i][2] == "keyword" and (toks[i][3] == "self" or toks[i][3] == "globals")) or
		  (toks[i][2] == "operator" and lines[lineIdx][toks[i][0]] == "."))
			i += 1
		end while
		if i == 0 or i+1 >= toks.len then continue
		if lines[lineIdx][toks[i][0]:toks[i][1]] != "=" or _kw(toks[i+1]) != "function" then continue
		result.push [lineIdx, lines[lineIdx][toks[0][0]:toks[i-1][1]]]
	end for
	return result
end function

return MiniScriptMode
