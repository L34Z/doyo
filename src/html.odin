package doyo

// URL-mode rung 3: a hand-rolled, owned HTML→Markdown tokenizer.
// Conservative by policy — it drops only known-boilerplate containers
// (nav/header/footer/aside/script/style) and strips remaining tags, keeping all
// other text. It defaults to leaving cruft rather than risking real content.
// Output is a transparent guess; url.odin flags it "verify".
//
// ## Changes
// - 2026-07-28: Initial conservative tokenizer + entity decode + SPA detection.

import "core:strings"

// Containers whose entire contents are boilerplate and must be dropped.
BOILERPLATE_TAGS := []string{"script", "style", "nav", "header", "footer", "aside"}
// Block-level tags whose boundaries become line breaks (structure, not content).
BLOCK_TAGS := []string{"p", "div", "br", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "section", "article"}

// Convert HTML to lightly-cleaned Markdown-ish text. `spa` is true when the
// result is effectively empty — the fetched HTML was a JS shell, which no
// parser can help; the caller fails loud on it.
html_to_markdown :: proc(data: []u8) -> (md: string, spa: bool) {
	s := string(data)
	b := strings.builder_make(0, len(s))
	skip := 0 // depth of open boilerplate containers; text is dropped while > 0

	i := 0
	for i < len(s) {
		if s[i] != '<' {
			if skip == 0 {
				strings.write_byte(&b, s[i])
			}
			i += 1
			continue
		}
		// Parse a tag: <[/]name ...>
		close := i + 1 < len(s) && s[i + 1] == '/'
		j := i + (close ? 2 : 1)
		name_start := j
		for j < len(s) && is_name_byte(s[j]) {
			j += 1
		}
		name := strings.to_lower(s[name_start:j])
		for j < len(s) && s[j] != '>' {
			j += 1
		}
		i = j + 1 // past '>'

		if contains_str(BOILERPLATE_TAGS, name) {
			if close {
				if skip > 0 {skip -= 1}
			} else {
				skip += 1
			}
			continue
		}
		if skip == 0 && contains_str(BLOCK_TAGS, name) {
			strings.write_byte(&b, '\n')
		}
	}

	text := decode_entities(strings.to_string(b))
	text = collapse_blank_lines(text)
	return text, strings.trim_space(text) == ""
}

is_name_byte :: proc(c: u8) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}

contains_str :: proc(set: []string, s: string) -> bool {
	for x in set {
		if x == s {return true}
	}
	return false
}

// Decode the handful of entities that actually appear in prose.
decode_entities :: proc(s: string) -> string {
	repl := []struct {
		from, to: string,
	}{{"&amp;", "&"}, {"&lt;", "<"}, {"&gt;", ">"}, {"&quot;", "\""}, {"&#39;", "'"}, {"&nbsp;", " "}}
	out := s
	for r in repl {
		out, _ = strings.replace_all(out, r.from, r.to)
	}
	return out
}

// Collapse runs of 3+ newlines (with optional surrounding spaces) to 2, and trim.
collapse_blank_lines :: proc(s: string) -> string {
	lines := strings.split(s, "\n")
	out := make([dynamic]string, 0, len(lines))
	blanks := 0
	for line in lines {
		t := strings.trim_space(line)
		if t == "" {
			blanks += 1
			if blanks <= 1 {append(&out, "")}
		} else {
			blanks = 0
			append(&out, t)
		}
	}
	return strings.trim_space(strings.join(out[:], "\n"))
}
