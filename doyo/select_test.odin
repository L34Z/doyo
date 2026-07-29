package doyo

import "core:slice"
import "core:testing"

// Helper: build a tree from paths (content is the path itself, irrelevant here).
tree :: proc(paths: ..string) -> []File {
	out := make([]File, len(paths))
	for p, i in paths {
		out[i] = File{path = p, data = transmute([]u8)p}
	}
	return out
}

// Helper: the selected paths as a sorted set for order-independent comparison.
selected_paths :: proc(files: []File) -> []string {
	out := make([]string, len(files))
	for f, i in files {
		out[i] = f.path
	}
	slice.sort(out)
	return out
}

@(test)
llms_full_wins_over_everything :: proc(t: ^testing.T) {
	files := tree("llms-full.txt", "docs/intro.rst", "README.md", "src/main.go")
	got := selected_paths(select_docs(files))
	testing.expect_value(t, len(got), 1)
	testing.expect_value(t, got[0], "llms-full.txt")
}

@(test)
docs_folder_takes_only_doc_files :: proc(t: ^testing.T) {
	files := tree("docs/intro.rst", "docs/guide.md", "docs/logo.png", "src/main.go", "README.md")
	got := selected_paths(select_docs(files))
	testing.expect(t, slice.equal(got, []string{"docs/guide.md", "docs/intro.rst"}), "docs/ md+rst only, no png, no src")
}

@(test)
fallback_takes_all_docs_plus_readme :: proc(t: ^testing.T) {
	files := tree("guide.md", "api.rst", "notes.txt", "README", "src/main.go", "logo.png")
	got := selected_paths(select_docs(files))
	testing.expect(t, slice.equal(got, []string{"README", "api.rst", "guide.md", "notes.txt"}), "all doc files + README, no src/binary")
}

@(test)
path_override_beats_detection :: proc(t: ^testing.T) {
	files := tree("docs/wrong.md", "manual/real.rst", "manual/deep/more.md", "manual/img.png")
	got := selected_paths(select_docs(files, "manual"))
	testing.expect(t, slice.equal(got, []string{"manual/deep/more.md", "manual/real.rst"}), "override picks manual/, doc files only")
}
