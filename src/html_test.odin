package doyo

import "core:testing"

@(test)
html_headings_become_atx :: proc(t: ^testing.T) {
	// Heading text is wrapped in an inline <a> anchor, as static doc builders
	// emit; the anchor is stripped and the text keeps its '#' marker.
	in_ := `<h1 id="x"><a href="#x">Hooks</a></h1><p>body</p><h2><a href="#y">Available Hooks</a></h2>`
	md, spa := html_to_markdown(transmute([]u8)in_)
	testing.expect(t, !spa)
	testing.expect_value(t, md, "# Hooks\n\nbody\n\n## Available Hooks")
}

@(test)
html_drops_boilerplate_nav :: proc(t: ^testing.T) {
	// A nav full of heading links must not leak into the output.
	in_ := `<nav><h2>Menu</h2><a href="/a">A</a></nav><h1>Title</h1><p>text</p>`
	md, _ := html_to_markdown(transmute([]u8)in_)
	testing.expect_value(t, md, "# Title\n\ntext")
}

@(test)
html_all_heading_levels :: proc(t: ^testing.T) {
	in_ := `<h1>a</h1><h3>b</h3><h6>c</h6>`
	md, _ := html_to_markdown(transmute([]u8)in_)
	testing.expect_value(t, md, "# a\n\n### b\n\n###### c")
}
