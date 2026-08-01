package doyo

import "core:testing"

@(test)
url_bases_walks_path_deepest_first :: proc(t: ^testing.T) {
	bases := url_bases("https://heroiclabs.com/docs/nakama/client-libraries/godot/")
	testing.expect_value(t, len(bases), 5)
	testing.expect_value(t, bases[0], "https://heroiclabs.com/docs/nakama/client-libraries/godot")
	testing.expect_value(t, bases[1], "https://heroiclabs.com/docs/nakama/client-libraries")
	testing.expect_value(t, bases[2], "https://heroiclabs.com/docs/nakama")
	testing.expect_value(t, bases[3], "https://heroiclabs.com/docs")
	testing.expect_value(t, bases[4], "https://heroiclabs.com")
}

@(test)
url_bases_host_only_is_just_root :: proc(t: ^testing.T) {
	bases := url_bases("https://example.com")
	testing.expect_value(t, len(bases), 1)
	testing.expect_value(t, bases[0], "https://example.com")
}

@(test)
url_bases_drops_query_and_fragment :: proc(t: ^testing.T) {
	bases := url_bases("https://example.com/a/b?x=1#frag")
	testing.expect_value(t, len(bases), 3)
	testing.expect_value(t, bases[0], "https://example.com/a/b")
	testing.expect_value(t, bases[1], "https://example.com/a")
	testing.expect_value(t, bases[2], "https://example.com")
}

@(test)
section_prefix_next_segment_after_base :: proc(t: ^testing.T) {
	got := section_prefix(
		"https://heroiclabs.com/docs",
		"https://heroiclabs.com/docs/nakama/client-libraries/godot/",
	)
	testing.expect_value(t, got, "https://heroiclabs.com/docs/nakama/")
}

@(test)
section_prefix_empty_when_target_is_base :: proc(t: ^testing.T) {
	got := section_prefix("https://heroiclabs.com/docs", "https://heroiclabs.com/docs")
	testing.expect_value(t, got, "")
}

@(test)
section_prefix_empty_when_target_outside_base :: proc(t: ^testing.T) {
	got := section_prefix("https://heroiclabs.com/docs", "https://heroiclabs.com/blog/x")
	testing.expect_value(t, got, "")
}

@(test)
url_dir_strips_last_segment :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		url_dir("https://docs.novelai.net/en/scripting/introduction"),
		"https://docs.novelai.net/en/scripting/",
	)
}

@(test)
url_dir_keeps_trailing_slash :: proc(t: ^testing.T) {
	testing.expect_value(t, url_dir("https://x.dev/a/b/"), "https://x.dev/a/b/")
}

@(test)
url_dir_host_only_is_root_slash :: proc(t: ^testing.T) {
	testing.expect_value(t, url_dir("https://x.dev"), "https://x.dev/")
}

@(test)
resolve_url_root_relative :: proc(t: ^testing.T) {
	got := resolve_url("https://x.dev/en/scripting/introduction", "/en/scripting/hooks")
	testing.expect_value(t, got, "https://x.dev/en/scripting/hooks")
}

@(test)
resolve_url_dot_relative :: proc(t: ^testing.T) {
	got := resolve_url("https://x.dev/en/scripting/introduction", "./api-reference")
	testing.expect_value(t, got, "https://x.dev/en/scripting/api-reference")
}

@(test)
resolve_url_parent_relative :: proc(t: ^testing.T) {
	got := resolve_url("https://x.dev/en/scripting/introduction", "../image/basics")
	testing.expect_value(t, got, "https://x.dev/en/image/basics")
}

@(test)
resolve_url_drops_fragment_and_scheme :: proc(t: ^testing.T) {
	base := "https://x.dev/a/b"
	testing.expect_value(t, resolve_url(base, "#top"), "")
	testing.expect_value(t, resolve_url(base, "mailto:hi@x.dev"), "")
	testing.expect_value(t, resolve_url(base, "/c?q=1#f"), "https://x.dev/c")
}

@(test)
extract_html_links_resolves_and_scopes :: proc(t: ^testing.T) {
	html := `<a href="./hooks">h</a><a href="/en/image/x">i</a><a href="#top">t</a>`
	links := extract_html_links(html, "https://x.dev/en/scripting/introduction")
	testing.expect_value(t, len(links), 2)
	testing.expect_value(t, links[0], "https://x.dev/en/scripting/hooks")
	testing.expect_value(t, links[1], "https://x.dev/en/image/x")
}

@(test)
enqueue_links_keeps_only_section :: proc(t: ^testing.T) {
	visited := make(map[string]bool)
	frontier := make([dynamic]string, 0, 4)
	links := []string {
		"https://x.dev/en/scripting/hooks",
		"https://x.dev/en/image/basics", // outside section — dropped
		"https://x.dev/en/scripting/hooks", // duplicate — deduped
	}
	enqueue_links(&frontier, &visited, links, "https://x.dev/en/scripting/")
	testing.expect_value(t, len(frontier), 1)
	testing.expect_value(t, frontier[0], "https://x.dev/en/scripting/hooks")
}
