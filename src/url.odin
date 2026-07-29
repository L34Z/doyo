package doyo

// URL mode: the fallback ladder. Resolve in order, stop at the first
// rung that succeeds: (1) an llms.txt/llms-full.txt manifest, (2) the page's own
// machine-readable Markdown, (3) a heuristic HTML→Markdown extraction flagged
// "verify". Fails loud on JS-SPAs (empty HTML shell).
//
// ## Changes
// - 2026-07-28: Ladder rungs 1–3, concurrent link-following, SPA fail-loud.

import "core:fmt"
import "core:strings"

run_url :: proc(t: Target, opt: Options) -> string {
	root := url_root(t.url)
	out := opt.out != "" ? opt.out : strings.concatenate({"./", url_host(t.url)})

	// Rung 1: an llms manifest at the host root is authoritative Markdown.
	// llms-full.txt is self-contained; llms.txt lists links we follow.
	if full := fetch_bytes(strings.concatenate({root, "/llms-full.txt"})); full.ok &&
	   !is_probably_html(string(full.data)) {
		fmt.eprintln("doyo: found llms-full.txt (authoritative)")
		return write_output(out, {{path = "llms-full.txt", data = full.data}}, opt.force)
	}
	if man := fetch_bytes(strings.concatenate({root, "/llms.txt"})); man.ok &&
	   !is_probably_html(string(man.data)) {
		fmt.eprintln("doyo: found llms.txt manifest, following links")
		return write_llms_manifest(out, man.data, root, opt)
	}

	// Rung 2: the page's own Markdown form (`.md`, or an Accept negotiation).
	if md, ok := fetch_page_markdown(t.url); ok {
		fmt.eprintln("doyo: served site Markdown")
		return write_output(out, {{path = url_to_filename(t.url), data = md}}, opt.force)
	}

	// Rung 3: heuristic HTML→Markdown — a transparent guess, flagged for review.
	page := fetch_bytes(t.url)
	if !page.ok {
		return strings.concatenate({"failed to fetch: ", t.url})
	}
	md, spa := html_to_markdown(page.data)
	if spa {
		return strings.concatenate(
			{"page appears to be a JS-rendered SPA (empty HTML shell): ", t.url,
			 "\n  doyo cannot render it — out of scope"},
		)
	}
	notice := strings.concatenate({"<!-- extracted from HTML (heuristic) — verify -->\n\n", md})
	fmt.eprintln("doyo: extracted from HTML (heuristic) — verify output")
	return write_output(out, {{path = url_to_filename(t.url), data = transmute([]u8)notice}}, opt.force)
}

// Follow an llms.txt manifest: fetch every linked page concurrently
// and write each, plus the manifest itself.
write_llms_manifest :: proc(out: string, manifest: []u8, root: string, opt: Options) -> string {
	links := extract_links(string(manifest))
	fetched := fetch_many(links, opt.jobs)

	files := make([dynamic]File, 0, len(links) + 1)
	append(&files, File{path = "llms.txt", data = manifest})
	for f, i in fetched {
		if f.ok {
			append(&files, File{path = url_to_filename(links[i]), data = f.data})
		}
	}
	return write_output(out, files[:], opt.force)
}

// Try the page's machine-readable Markdown: a `.md` sibling, then an
// Accept:text/markdown negotiation. Accept only if the body isn't HTML.
fetch_page_markdown :: proc(url: string) -> ([]u8, bool) {
	if !strings.has_suffix(url, ".md") {
		if f := fetch_bytes(strings.concatenate({url, ".md"})); f.ok &&
		   !is_probably_html(string(f.data)) {
			return f.data, true
		}
	}
	if f := fetch_with_accept(url, "text/markdown"); f.ok &&
	   !is_probably_html(string(f.data)) && len(strings.trim_space(string(f.data))) > 0 {
		return f.data, true
	}
	return nil, false
}

// Body looks like HTML when its first non-space byte opens a tag.
is_probably_html :: proc(s: string) -> bool {
	t := strings.trim_space(s)
	return len(t) > 0 && t[0] == '<'
}

// scheme://host of a URL (its root), for locating llms.txt.
url_root :: proc(url: string) -> string {
	scheme_end := strings.index(url, "://")
	if scheme_end < 0 {
		return url
	}
	rest := url[scheme_end + 3:]
	if slash := strings.index_byte(rest, '/'); slash >= 0 {
		return url[:scheme_end + 3 + slash]
	}
	return url
}

// Host portion of a URL, used to name the output directory.
url_host :: proc(url: string) -> string {
	r := url_root(url)
	if i := strings.index(r, "://"); i >= 0 {
		return r[i + 3:]
	}
	return r
}

// Derive a safe relative output filename from a URL. Empty/trailing-slash paths
// become index.md; every saved page ends in .md. Query/fragment are dropped.
url_to_filename :: proc(url: string) -> string {
	path := url
	if i := strings.index(url, "://"); i >= 0 {
		rest := url[i + 3:]
		if slash := strings.index_byte(rest, '/'); slash >= 0 {
			path = rest[slash + 1:]
		} else {
			path = ""
		}
	}
	for cut in ([]string{"?", "#"}) {
		if i := strings.index(path, cut); i >= 0 {
			path = path[:i]
		}
	}
	path = strings.trim_suffix(path, "/")
	if path == "" {
		return "index.md"
	}
	if !strings.has_suffix(path, ".md") && !strings.has_suffix(path, ".rst") &&
	   !strings.has_suffix(path, ".txt") {
		path = strings.concatenate({path, ".md"})
	}
	return path
}

// Collect absolute http(s) links from Markdown `](url)` targets.
extract_links :: proc(md: string) -> []string {
	out := make([dynamic]string, 0, 16)
	s := md
	for {
		open := strings.index(s, "](")
		if open < 0 {break}
		s = s[open + 2:]
		close := strings.index_byte(s, ')')
		if close < 0 {break}
		link := strings.trim_space(s[:close])
		if strings.has_prefix(link, "http://") || strings.has_prefix(link, "https://") {
			append(&out, link)
		}
		s = s[close + 1:]
	}
	return out[:]
}
