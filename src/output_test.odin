package doyo

import "core:testing"

// 2026-07-31: pin the served-name rule (output.odin llms_served_name). llms-full
// content is Markdown under a .txt name; doyo serves it as .md so a Markdown-only
// indexer (doma) picks it up. The bare manifest and every other path are untouched.
@(test)
served_name_renames_only_llms_full :: proc(t: ^testing.T) {
	// llms-full.txt -> .md: the self-contained Markdown docs.
	testing.expect_value(t, served_name("llms-full.txt"), "llms-full.md")
	// The bare manifest is a link list, not prose — keeps .txt.
	testing.expect_value(t, served_name("llms.txt"), "llms.txt")
	// Ordinary docs are never touched.
	testing.expect_value(t, served_name("guide.md"), "guide.md")
	testing.expect_value(t, served_name("api.rst"), "api.rst")
	// The index.md collision guard still composes.
	testing.expect_value(t, served_name("index.md"), "index_.md")
}
