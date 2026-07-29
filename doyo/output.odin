package doyo

// Output layer (DESIGN §7): mirror the selected docs to a directory tree plus a
// sorted index.md. Non-destructive — refuse to overwrite an existing output dir
// without --force. The index is sorted once, so on-disk output is byte-identical
// run to run for the same fetched bytes.
//
// ## Changes
// - 2026-07-28: Non-destructive tree writer + sorted index.

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
		dest := strings.concatenate({out_dir, "/", reserve_index(f.path)})
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

// index.md is reserved for the manifest; a doc that would take that name is
// written as index_.md so the manifest never clobbers real content.
reserve_index :: proc(path: string) -> string {
	return path == "index.md" ? "index_.md" : path
}

// A sorted Markdown manifest of every written file (DESIGN §7). Sorting makes
// the manifest independent of fetch/arrival order.
build_index :: proc(files: []File) -> string {
	paths := make([]string, len(files))
	for f, i in files {
		paths[i] = f.path
	}
	for &p in paths {
		p = reserve_index(p)
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
