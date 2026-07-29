package doyo

// Doc selection: given the full fetched tree, return only the files doyo should
// serve, in DESIGN §3 priority order. Pure — a filter over the input slice, in
// one linear pass per rung; the result borrows the input Files (no copy).
//
// ## Changes
// - 2026-07-28: Implement priority ladder: override → llms → docs/ → all-docs.

import "core:strings"

// Root-relative doc folders, highest priority first (DESIGN §3.2).
DOC_DIRS := []string{"docs/", "doc/", "documentation/"}

// Select the files to serve. Priority: --path override, then an llms manifest at
// root, then a docs/ folder, else every doc file in the tree. Binary/source
// files are always dropped; only `is_doc_file` paths survive.
select_docs :: proc(files: []File, path_override := "") -> []File {
	out := make([dynamic]File, 0, len(files))

	// Rung 0: explicit override — everything doc-like under the given dir.
	if path_override != "" {
		prefix := strings.trim_suffix(path_override, "/")
		prefix = strings.concatenate({prefix, "/"})
		for f in files {
			if strings.has_prefix(f.path, prefix) && is_doc_file(f.path) {
				append(&out, f)
			}
		}
		return out[:]
	}

	// Rung 1: an llms manifest at root is authoritative on its own (DESIGN §3.1).
	// llms-full.txt is self-contained; llms.txt is the manifest to follow.
	for name in ([]string{"llms-full.txt", "llms.txt"}) {
		for f in files {
			if f.path == name {
				append(&out, f)
				return out[:]
			}
		}
	}

	// Rung 2: a conventional docs folder — take the doc files under it.
	for dir in DOC_DIRS {
		found := false
		for f in files {
			if strings.has_prefix(f.path, dir) && is_doc_file(f.path) {
				append(&out, f)
				found = true
			}
		}
		if found {
			return out[:]
		}
	}

	// Rung 3: no manifest, no docs folder — every doc file in the tree.
	for f in files {
		if is_doc_file(f.path) {
			append(&out, f)
		}
	}
	return out[:]
}
