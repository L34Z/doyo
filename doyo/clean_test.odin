package doyo

import "core:testing"

// Golden helper: clean(path, in) must equal `want`, byte-for-byte (GUIDELINES §6).
golden :: proc(t: ^testing.T, path, in_, want: string, loc := #caller_location) {
	got := string(clean(path, transmute([]u8)in_))
	testing.expectf(t, got == want, "clean(%q)\n--- got ---\n%s\n--- want ---\n%s", path, got, want)
}

@(test)
md_image_becomes_alt_text :: proc(t: ^testing.T) {
	golden(t, "a.md", "See ![the logo](logo.png) here.\n", "See the logo here.\n")
}

@(test)
md_prose_and_code_untouched :: proc(t: ^testing.T) {
	src := "# Title\n\nText with `inline` code.\n\n```go\nfmt.Println(x)\n```\n"
	golden(t, "a.md", src, src)
}

@(test)
rst_toctree_block_removed :: proc(t: ^testing.T) {
	in_ := "Intro\n=====\n\n.. toctree::\n   :maxdepth: 2\n\n   page1\n   page2\n\nBody text.\n"
	golden(t, "a.rst", in_, "Intro\n=====\n\nBody text.\n")
}

@(test)
rst_comment_block_removed :: proc(t: ^testing.T) {
	in_ := ".. This is a comment\n   spanning two lines\n\nReal text.\n"
	golden(t, "a.rst", in_, "Real text.\n")
}

@(test)
rst_image_keeps_alt_drops_ref :: proc(t: ^testing.T) {
	in_ := ".. image:: diagram.png\n   :alt: Architecture diagram\n   :width: 400\n"
	golden(t, "a.rst", in_, "Architecture diagram\n")
}

@(test)
rst_figure_keeps_caption :: proc(t: ^testing.T) {
	in_ := ".. figure:: chart.png\n   :alt: A chart\n\n   The quarterly numbers.\n"
	golden(t, "a.rst", in_, "A chart\nThe quarterly numbers.\n")
}

@(test)
rst_directive_and_target_untouched :: proc(t: ^testing.T) {
	// A real directive (has ::) and a hyperlink target (starts _) carry meaning.
	src := ".. code-block:: python\n\n   print(1)\n\n.. _install: https://x/install\n"
	golden(t, "a.rst", src, src)
}

@(test)
rst_strips_bodyless_style_directive :: proc(t: ^testing.T) {
	// `.. rst-class::` is a docutils class-setter: a CSS tag, no prose. In godot
	// it is bodyless; only the marker line is dropped, the heading stays.
	in_ := ".. rst-class:: classref-group\n\nDescription\n-----------\n"
	golden(t, "a.rst", in_, "\nDescription\n-----------\n")
}

@(test)
rst_style_directive_keeps_its_body :: proc(t: ^testing.T) {
	// SAFETY: a class-setter WITH a styled body (other projects do this) must
	// keep the body — we only ever drop the styling tag, never content.
	in_ := ".. class:: special\n\n   This paragraph is styled.\n"
	golden(t, "a.rst", in_, "\n   This paragraph is styled.\n")
}

@(test)
txt_passthrough :: proc(t: ^testing.T) {
	src := "plain text\nno rules apply\n"
	golden(t, "notes.txt", src, src)
}
