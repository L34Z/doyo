package doyo

// Fixtures are code (GUIDELINES §6): gen_repo emits a synthetic repo tree with
// known ground truth — a docs/ folder of rST pages carrying every construct the
// cleaner touches (comment, image, prose) plus source/binary noise that must be
// dropped. Used by golden tests and by the benchmark, scaled by page count. No
// download, fully deterministic.
//
// ## Changes
// - 2026-07-28: Initial generator + known-clean oracle.

import "core:fmt"

// Build a repo of `pages` rST doc pages under docs/, plus dropped noise files.
// Deterministic: page i is a pure function of i, so ground truth is computable.
gen_repo :: proc(pages: int) -> []File {
	out := make([dynamic]File, 0, pages + 2)
	for i in 0 ..< pages {
		append(&out, File{path = fmt.aprintf("docs/page%04d.rst", i), data = transmute([]u8)gen_page(i)})
	}
	// Noise doyo must drop: source code and a binary asset.
	append(&out, File{path = "src/main.go", data = transmute([]u8)string("package main\n")})
	append(&out, File{path = "docs/logo.png", data = {0x89, 'P', 'N', 'G'}})
	return out[:]
}

// Raw rST for page i: a comment to strip, an image to collapse, real prose.
gen_page :: proc(i: int) -> string {
	return fmt.aprintf(
		".. This is page comment\n\nPage %d\n========\n\n.. image:: img%d.png\n   :alt: Figure %d\n\nProse body for page %d.\n",
		i, i, i, i,
	)
}

// The exact bytes `clean` must produce for gen_page(i) — the golden oracle.
gen_page_clean :: proc(i: int) -> string {
	return fmt.aprintf(
		"Page %d\n========\n\nFigure %d\nProse body for page %d.\n",
		i, i, i,
	)
}
