package doyo

// CLI surface (DESIGN §9): parse args into Options and classify the target as
// GitHub-repo mode or arbitrary-URL mode. Pure string work — unit-tested.
//
// ## Changes
// - 2026-07-28: Options, arg parser, and repo-vs-URL target classification.

import "core:strconv"
import "core:strings"

Options :: struct {
	target: string, // owner/repo, github URL, or arbitrary URL
	path:   string, // --path override (repo mode)
	out:    string, // --out override
	force:  bool,
	jobs:   int,
}

Target :: struct {
	is_repo:     bool,
	owner, repo: string, // repo mode
	url:         string, // url mode
}

// Parse argv (excluding program name). Returns Options and an error string
// ("" on success). Fails loud on unknown flags or missing values (GUIDELINES §5).
parse_args :: proc(args: []string) -> (Options, string) {
	opt := Options {
		jobs = 8,
	}
	i := 0
	for i < len(args) {
		a := args[i]
		switch a {
		case "--path":
			i += 1;if i >= len(args) {return opt, "--path needs a value"}
			opt.path = args[i]
		case "--out":
			i += 1;if i >= len(args) {return opt, "--out needs a value"}
			opt.out = args[i]
		case "--jobs":
			i += 1;if i >= len(args) {return opt, "--jobs needs a value"}
			n, ok := strconv.parse_int(args[i])
			if !ok || n < 1 {return opt, "--jobs needs a positive integer"}
			opt.jobs = n
		case "--force":
			opt.force = true
		case:
			if strings.has_prefix(a, "-") {
				return opt, strings.concatenate({"unknown flag: ", a})
			}
			if opt.target != "" {
				return opt, "more than one target given"
			}
			opt.target = a
		}
		i += 1
	}
	if opt.target == "" {
		return opt, "no target given"
	}
	return opt, ""
}

// Classify a target string. GitHub URLs and bare `owner/repo` are repo mode;
// anything else is URL mode (a bare host gets an https:// scheme).
classify_target :: proc(s: string) -> Target {
	if rest, ok := strip_prefix_any(s, {"https://github.com/", "http://github.com/"}); ok {
		owner, repo := split_owner_repo(rest)
		return {is_repo = true, owner = owner, repo = repo}
	}
	if strings.contains(s, "://") {
		return {url = s}
	}
	// No scheme: `owner/repo` when the first segment is a plain name (no dot).
	if slash := strings.index_byte(s, '/'); slash > 0 {
		first := s[:slash]
		if !strings.contains(first, ".") {
			owner, repo := split_owner_repo(s)
			return {is_repo = true, owner = owner, repo = repo}
		}
	}
	return {url = strings.concatenate({"https://", s})}
}

// First two slash-separated segments as owner/repo, dropping a trailing ".git".
split_owner_repo :: proc(s: string) -> (owner, repo: string) {
	parts := strings.split(s, "/")
	if len(parts) >= 1 {owner = parts[0]}
	if len(parts) >= 2 {repo = strings.trim_suffix(parts[1], ".git")}
	return
}

strip_prefix_any :: proc(s: string, prefixes: []string) -> (string, bool) {
	for p in prefixes {
		if strings.has_prefix(s, p) {
			return s[len(p):], true
		}
	}
	return s, false
}
