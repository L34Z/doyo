package doyo

// Light normalization (DESIGN §5): deterministic, line-level, no format parser.
// Strips only provably-contentless rST noise (comments, toctree) and collapses
// image directives to their alt text. Prose, code blocks and inline roles are
// left byte-for-byte raw — rewriting them is where a wrong converter creeps in.
//
// ## Changes
// - 2026-07-28: Implement rST comment/toctree/image handling + Markdown images.

import "core:strings"

// Normalize one file by extension. Unknown extensions pass through untouched —
// doyo defaults to leaving content rather than risking dropping it (DESIGN §4).
clean :: proc(path: string, data: []u8) -> []u8 {
	lower := strings.to_lower(path)
	switch {
	case strings.has_suffix(lower, ".rst"):
		return clean_rst(data)
	case strings.has_suffix(lower, ".md"), strings.has_suffix(lower, ".markdown"):
		return clean_md(data)
	case:
		return data
	}
}

// Markdown: collapse inline images `![alt](url)` to their alt text (the binary
// is useless to an LLM; the alt is prose). Everything else is copied verbatim.
clean_md :: proc(data: []u8) -> []u8 {
	s := string(data)
	b := strings.builder_make(0, len(s))
	i := 0
	for i < len(s) {
		if i + 1 < len(s) && s[i] == '!' && s[i + 1] == '[' {
			close_alt := strings.index(s[i:], "](")
			if close_alt >= 0 {
				alt := s[i + 2 : i + close_alt]
				rest := s[i + close_alt + 2:]
				close_url := strings.index_byte(rest, ')')
				if close_url >= 0 {
					strings.write_string(&b, alt)
					i = i + close_alt + 2 + close_url + 1
					continue
				}
			}
		}
		strings.write_byte(&b, s[i])
		i += 1
	}
	return b.buf[:]
}

// rST: a single linear pass over lines. `..` block starters are classified and
// either dropped (toctree, comment), collapsed to alt+caption (image/figure),
// or — for real directives and hyperlink targets — copied through untouched.
clean_rst :: proc(data: []u8) -> []u8 {
	lines := strings.split(string(data), "\n")
	out := make([dynamic]string, 0, len(lines))

	i := 0
	for i < len(lines) {
		line := lines[i]
		trimmed := strings.trim_left(line, " ")
		indent := len(line) - len(trimmed)

		if is_block_marker(trimmed) {
			after := len(trimmed) == 2 ? "" : strings.trim_left(trimmed[2:], " ")
			name := directive_name(after)
			switch {
			case name == "toctree":
				i = skip_block(lines[:], i, indent)
				continue
			case name == "image", name == "figure":
				i = take_image(lines[:], i, indent, &out)
				continue
			case is_rst_comment(after):
				i = skip_block(lines[:], i, indent)
				continue
			}
		}
		append(&out, line)
		i += 1
	}
	return transmute([]u8)strings.join(out[:], "\n")
}

// A line is a block marker when it starts with `..` alone or `.. `.
is_block_marker :: proc(trimmed: string) -> bool {
	return trimmed == ".." || strings.has_prefix(trimmed, ".. ")
}

// Directive name = the token before `::` (e.g. "toctree" in ".. toctree::").
// Empty when there is no `::` or the token contains spaces (not a directive).
directive_name :: proc(after: string) -> string {
	idx := strings.index(after, "::")
	if idx < 0 {
		return ""
	}
	name := after[:idx]
	return strings.index_byte(name, ' ') < 0 ? name : ""
}

// A comment is a `..` block that is neither a directive (`::`), a hyperlink
// target (`_`), a substitution (`|`), nor a citation/footnote (`[`).
is_rst_comment :: proc(after: string) -> bool {
	if after == "" {
		return true
	}
	switch after[0] {
	case '_', '|', '[':
		return false
	}
	return strings.index(after, "::") < 0
}

// Index of the first line NOT belonging to the block that starts at `start`.
// A block owns following lines that are blank or indented deeper than `base` —
// but never the file's final terminator line, so a trailing newline survives.
skip_block :: proc(lines: []string, start, base: int) -> int {
	j := start + 1
	for j < len(lines) - 1 {
		t := strings.trim_left(lines[j], " ")
		indent := len(lines[j]) - len(t)
		if t == "" || indent > base {
			j += 1
		} else {
			break
		}
	}
	return j
}

// Collapse an image/figure block: emit its `:alt:` text, then any caption prose
// (a figure's indented non-option lines). Returns the index past the block.
take_image :: proc(lines: []string, start, base: int, out: ^[dynamic]string) -> int {
	end := skip_block(lines, start, base)
	alt: string
	caption := make([dynamic]string, 0, 2)
	for j := start + 1; j < end; j += 1 {
		t := strings.trim_left(lines[j], " ")
		if t == "" {
			continue
		}
		if strings.has_prefix(t, ":") {
			if key_idx := strings.index_byte(t[1:], ':'); key_idx >= 0 {
				key := t[1 : 1 + key_idx]
				if key == "alt" {
					alt = strings.trim_space(t[key_idx + 2:])
				}
				continue // an option line (:key: value) — not caption prose
			}
		}
		append(&caption, t) // dedented caption line
	}
	if alt != "" {
		append(out, alt)
	}
	for c in caption {
		append(out, c)
	}
	return end
}
