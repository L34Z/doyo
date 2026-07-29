package doyo

import "core:testing"

@(test)
classify_bare_owner_repo :: proc(t: ^testing.T) {
	tg := classify_target("godotengine/godot-docs")
	testing.expect(t, tg.is_repo, "bare owner/repo is repo mode")
	testing.expect_value(t, tg.owner, "godotengine")
	testing.expect_value(t, tg.repo, "godot-docs")
}

@(test)
classify_github_url_strips_git :: proc(t: ^testing.T) {
	tg := classify_target("https://github.com/a/b.git")
	testing.expect(t, tg.is_repo, "github URL is repo mode")
	testing.expect_value(t, tg.owner, "a")
	testing.expect_value(t, tg.repo, "b")
}

@(test)
classify_arbitrary_host_gets_scheme :: proc(t: ^testing.T) {
	tg := classify_target("example.com/docs")
	testing.expect(t, !tg.is_repo, "host with dot is url mode")
	testing.expect_value(t, tg.url, "https://example.com/docs")
}

@(test)
classify_full_url_preserved :: proc(t: ^testing.T) {
	tg := classify_target("https://docs.example.com/guide")
	testing.expect(t, !tg.is_repo, "non-github URL is url mode")
	testing.expect_value(t, tg.url, "https://docs.example.com/guide")
}

@(test)
parse_flags_and_target :: proc(t: ^testing.T) {
	opt, err := parse_args([]string{"owner/repo", "--jobs", "4", "--force", "--out", "d"})
	testing.expect_value(t, err, "")
	testing.expect_value(t, opt.target, "owner/repo")
	testing.expect_value(t, opt.jobs, 4)
	testing.expect(t, opt.force, "force set")
	testing.expect_value(t, opt.out, "d")
}

@(test)
parse_rejects_unknown_flag :: proc(t: ^testing.T) {
	_, err := parse_args([]string{"x", "--nope"})
	testing.expect(t, err != "", "unknown flag is an error")
}

@(test)
parse_requires_target :: proc(t: ^testing.T) {
	_, err := parse_args([]string{"--force"})
	testing.expect(t, err != "", "missing target is an error")
}
