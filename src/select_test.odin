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
fallback_takes_md_rst_and_readme_only :: proc(t: ^testing.T) {
	// Fallback is *.md / *.rst + README. Plain .txt is not a served
	// format, so notes.txt is dropped along with source/binaries.
	files := tree("guide.md", "api.rst", "notes.txt", "README", "src/main.go", "logo.png")
	got := selected_paths(select_docs(files))
	testing.expect(t, slice.equal(got, []string{"README", "api.rst", "guide.md"}), "md+rst+README only, no txt/src/binary")
}

@(test)
fallback_excludes_vendored_and_dot_dirs :: proc(t: ^testing.T) {
	// Vendored trees and dot-dirs are noise.
	files := tree("README.md", "guide.md", "thirdparty/dep/LICENSE.md", ".github/PR.md", "src/x.go")
	got := selected_paths(select_docs(files))
	testing.expect(t, slice.equal(got, []string{"README.md", "guide.md"}), "no thirdparty/, no .github/")
}

@(test)
fallback_excludes_underscore_tooling_dirs :: proc(t: ^testing.T) {
	// Leading-underscore dirs are tooling/internal by convention (Sphinx _static,
	// godot _tools/_styleguides). Dropped in auto-detection, like dot-dirs.
	files := tree("README.md", "guide.md", "_tools/redirects/README.md", "_styleguides/de.md")
	got := selected_paths(select_docs(files))
	testing.expect(t, slice.equal(got, []string{"README.md", "guide.md"}), "no _tooling dirs")
}

@(test)
path_override_keeps_underscore_dir :: proc(t: ^testing.T) {
	// SAFETY: an explicit --path is always honored, even into an underscore dir.
	files := tree("_internal/real.md", "_internal/more.rst", "other.md")
	got := selected_paths(select_docs(files, "_internal"))
	testing.expect(t, slice.equal(got, []string{"_internal/more.rst", "_internal/real.md"}), "override honors _dir")
}

@(test)
docs_folder_excludes_vendored :: proc(t: ^testing.T) {
	files := tree("docs/intro.rst", "docs/thirdparty/vendor/README.md", "docs/guide.md")
	got := selected_paths(select_docs(files))
	testing.expect(t, slice.equal(got, []string{"docs/guide.md", "docs/intro.rst"}), "vendored dir under docs/ dropped")
}

@(test)
path_override_beats_detection :: proc(t: ^testing.T) {
	files := tree("docs/wrong.md", "manual/real.rst", "manual/deep/more.md", "manual/img.png")
	got := selected_paths(select_docs(files, "manual"))
	testing.expect(t, slice.equal(got, []string{"manual/deep/more.md", "manual/real.rst"}), "override picks manual/, doc files only")
}
