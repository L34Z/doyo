package doyo

// Output layer: mirror the selected docs to a directory tree plus a
// sorted index.md. Non-destructive — refuse to overwrite an existing output dir
// without --force. The index is sorted once, so on-disk output is byte-identical
// run to run for the same fetched bytes.
//
// ## Changes
// - 2026-07-28: Non-destructive tree writer + sorted index.
// - 2026-07-31: Serve llms-full.txt as llms-full.md (served_name). It is Markdown
//   despite the .txt name (llms.txt convention), and a Markdown-only downstream
//   indexer — doma walks *.md — silently skips a .txt and indexes nothing. The
//   bare llms.txt manifest is a link list, not prose, so it keeps .txt.

import "core:os"
import "core:slice"
import "core:strings"

// Write already-cleaned `files` under `out_dir`, plus index.md. Refuses to touch
// an existing `out_dir` unless `force`. Returns an error string ("" on success).
write_output :: proc(out_dir: string, files: []File, force: bool) -> string {
	if os.exists(out_dir) && !force {
		return strings.concatenate(
			{"output dir already exists: ", out_dir, " (pass --force to overwrite)"},
		)
	}
	if err := os.make_directory_all(out_dir); err != nil && err != .Exist {
		return strings.concatenate({"cannot create output dir: ", out_dir})
	}

	for f in files {
		dest := strings.concatenate({out_dir, "/", served_name(f.path)})
		if slash := strings.last_index_byte(dest, '/'); slash >= 0 {
			os.make_directory_all(dest[:slash])
		}
		if os.write_entire_file_from_bytes(dest, f.data) != nil {
			return strings.concatenate({"cannot write: ", dest})
		}
	}

	index := build_index(files)
	if os.write_entire_file_from_string(strings.concatenate({out_dir, "/index.md"}), index) != nil {
		return "cannot write index.md"
	}
	return ""
}

// The on-disk name for a served file: the llms rename first, then the index.md
// collision guard. Applied at both write time and in the manifest, so disk and
// index.md always agree.
served_name :: proc(path: string) -> string {
	return reserve_index(llms_served_name(path))
}

// 2026-07-31: llms-full.txt is self-contained Markdown that merely carries a .txt
// extension by the llms.txt convention, so doyo serves it as .md. Reason: a
// Markdown-only downstream indexer (doma walks *.md) silently skips a .txt file
// and indexes nothing, and doyo's contract is "a local folder of clean Markdown"
// — a .txt in that folder is the one thing not labeled as what it is. The bare
// llms.txt manifest is a link list, not prose, so it keeps .txt and stays out of
// a prose index. This rename is the whole fix; index.md follows automatically
// because it is built from served names.
llms_served_name :: proc(name: string) -> string {
	return name == "llms-full.txt" ? "llms-full.md" : name
}

// index.md is reserved for the manifest; a doc that would take that name is
// written as index_.md so the manifest never clobbers real content.
reserve_index :: proc(path: string) -> string {
	return path == "index.md" ? "index_.md" : path
}

// A sorted Markdown manifest of every written file. Sorting makes
// the manifest independent of fetch/arrival order.
build_index :: proc(files: []File) -> string {
	paths := make([]string, len(files))
	for f, i in files {
		paths[i] = f.path
	}
	for &p in paths {
		p = served_name(p)
	}
	slice.sort(paths)

	b := strings.builder_make()
	strings.write_string(&b, "# Index\n\n")
	for p in paths {
		strings.write_string(&b, "- [")
		strings.write_string(&b, p)
		strings.write_string(&b, "](")
		strings.write_string(&b, p)
		strings.write_string(&b, ")\n")
	}
	return strings.to_string(b)
}
