package doyo

// doyo — DOcumentation YOinker. Pure transform core.
//
// The whole domain is a flat list of files. A repo (or fetched URL tree) is a
// `[]File`: dense, index-addressable, copied only at explicit boundaries. Every
// pure function here is a straight-line pass over that slice — no object graph,
// no hidden state (GUIDELINES §1).
//
// ## Changes
// - 2026-07-28: Initial pure core: File, doc-extension classification.

import "core:strings"

// A single file in a fetched tree. `path` is the tree-relative slash path
// (e.g. "docs/intro.rst"); `data` is the raw bytes exactly as fetched.
File :: struct {
	path: string,
	data: []u8,
}

// Extensions doyo treats as LLM-readable documentation source (DESIGN §8).
DOC_EXTS := []string{".md", ".markdown", ".rst", ".txt"}

// A file counts as documentation when it carries a doc extension, or is a
// README of any/no extension (READMEs are authoritative even when extensionless).
is_doc_file :: proc(path: string) -> bool {
	base := basename(path)
	if strings.has_prefix(strings.to_lower(base), "readme") {
		return true
	}
	lower := strings.to_lower(path)
	for ext in DOC_EXTS {
		if strings.has_suffix(lower, ext) {
			return true
		}
	}
	return false
}

// Final slash-separated path component.
basename :: proc(path: string) -> string {
	i := strings.last_index_byte(path, '/')
	return i < 0 ? path : path[i + 1:]
}
