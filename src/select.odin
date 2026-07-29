package doyo

// Doc selection: given the full fetched tree, return only the files doyo should
// serve, in priority order. Pure — a filter over the input slice, in
// one linear pass per rung; the result borrows the input Files (no copy).
//
// ## Changes
// - 2026-07-28: Implement priority ladder: override → llms → docs/ → all-docs.

import "core:strings"

// Root-relative doc folders, highest priority first.
DOC_DIRS := []string{"docs/", "doc/", "documentation/"}

// Vendored/tooling directories that are never authored docs. Excluded from
// auto-detection, but NOT from an explicit --path override — there the user has
// chosen the tree deliberately.
NOISE_DIRS := []string{"thirdparty", "third_party", "vendor", "node_modules"}

// A path is noise when any segment is a vendored dir, or an internal dir marked
// by a leading dot (.github, .git) or underscore (Sphinx _static, godot _tools).
is_noise_path :: proc(path: string) -> bool {
	for seg in strings.split(path, "/") {
		if seg == "" {
			continue
		}
		if seg[0] == '.' || seg[0] == '_' {
			return true
		}
		for n in NOISE_DIRS {
			if seg == n {
				return true
			}
		}
	}
	return false
}

// Auto-detection keeps only real doc files that aren't in vendored/dot dirs.
is_wanted :: proc(path: string) -> bool {
	return is_doc_file(path) && !is_noise_path(path)
}

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

	// Rung 1: an llms manifest at root is authoritative on its own.
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
			if strings.has_prefix(f.path, dir) && is_wanted(f.path) {
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
		if is_wanted(f.path) {
			append(&out, f)
		}
	}
	return out[:]
}
