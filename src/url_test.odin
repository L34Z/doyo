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
