package doyo

// URL mode: the fallback ladder. Resolve in order, stop at the first
// rung that succeeds: (1) an llms.txt/llms-full.txt manifest, (2) the page's own
// machine-readable Markdown, (3) a heuristic HTML→Markdown extraction flagged
// "verify". Fails loud on JS-SPAs (empty HTML shell).
//
// ## Changes
// - 2026-07-28: Ladder rungs 1–3, concurrent link-following, SPA fail-loud.
// - 2026-08-01: Rung 3 crawls the doc tree — follows same-section HTML links
//   from the target page instead of writing that one page alone.

import "core:fmt"
import "core:strings"

run_url :: proc(t: Target, opt: Options) -> string {
	out := opt.out != "" ? opt.out : strings.concatenate({"./", url_host(t.url)})

	// Rung 1: the nearest llms manifest, walking up the URL path from the target
	// page down to the host root. A page-specific manifest (e.g. one project's
	// own docs section) wins over the site-wide one, so a link into a big multi-
	// product site pulls only that product's docs. llms-full.txt is self-
	// contained; llms.txt lists links we follow.
	for base in url_bases(t.url) {
		if full := fetch_bytes(strings.concatenate({base, "/llms-full.txt"})); full.ok &&
		   !is_probably_html(string(full.data)) {
			fmt.eprintfln("doyo: found llms-full.txt at %s (authoritative)", base)
			return write_output(out, {{path = "llms-full.txt", data = full.data}}, opt.force)
		}
		if man := fetch_bytes(strings.concatenate({base, "/llms.txt"})); man.ok &&
		   !is_probably_html(string(man.data)) {
			section := section_prefix(base, t.url)
			if section != "" {
				fmt.eprintfln("doyo: found llms.txt manifest at %s, following links under %s", base, section)
			} else {
				fmt.eprintfln("doyo: found llms.txt manifest at %s, following links", base)
			}
			return write_llms_manifest(out, man.data, section, opt)
		}
	}

	// Rung 2: the page's own Markdown form (`.md`, or an Accept negotiation).
	if md, ok := fetch_page_markdown(t.url); ok {
		fmt.eprintln("doyo: served site Markdown")
		return write_output(out, {{path = url_to_filename(t.url), data = md}}, opt.force)
	}

	// Rung 3: heuristic HTML→Markdown — a transparent guess, flagged for review.
	// Static doc sites (e.g. an Astro build) render the whole doc tree as one
	// nav of same-section links; a single page grabs almost nothing. So rung 3
	// crawls: from the target page, follow HTML links scoped to the target's own
	// directory (its section) and convert each. The scope mirrors the llms.txt
	// section filter — a deep page pulls its section, not the whole site.
	page := fetch_bytes(t.url)
	if !page.ok {
		return strings.concatenate({"failed to fetch: ", t.url})
	}
	// A JS shell yields no content no matter how we crawl — fail loud up front.
	if _, spa := html_to_markdown(page.data); spa {
		return strings.concatenate(
			{"page appears to be a JS-rendered SPA (empty HTML shell): ", t.url,
			 "\n  doyo cannot render it — out of scope"},
		)
	}
	fmt.eprintln("doyo: crawling from HTML (heuristic) — verify output")
	return crawl_html(out, t.url, page.data, opt)
}

// Rung-3 crawl: breadth-first from `start` (already fetched as `first_html`),
// following only HTML links under the start page's directory (its section), so
// the walk stays inside the targeted docs and never spiders the whole host. The
// visited set dedups and bounds the walk; the page set is the transitive closure
// of section links, so it — and the on-disk output — is the same run to run
// regardless of fetch order.
crawl_html :: proc(out, start: string, first_html: []u8, opt: Options) -> string {
	section := url_dir(start)
	visited := make(map[string]bool)
	visited[start] = true
	files := make([dynamic]File, 0, 16)

	frontier := make([dynamic]string, 0, 16)
	if f, ok := html_page_file(start, first_html); ok {
		append(&files, f)
		enqueue_links(&frontier, &visited, extract_html_links(string(first_html), start), section)
	}

	for len(frontier) > 0 {
		fetched := fetch_many(frontier[:], opt.jobs)
		next := make([dynamic]string, 0, 16)
		for res, i in fetched {
			if !res.ok {continue}
			url := frontier[i]
			if f, ok := html_page_file(url, res.data); ok {
				append(&files, f)
				enqueue_links(&next, &visited, extract_html_links(string(res.data), url), section)
			}
		}
		frontier = next
	}

	fmt.eprintfln("doyo: crawled %d pages (HTML heuristic) — verify output", len(files))
	return write_output(out, files[:], opt.force)
}

// Convert one fetched HTML page to a File with the heuristic notice prepended.
// ok=false when the page is an empty SPA shell, so the crawl skips it rather
// than writing a blank file.
html_page_file :: proc(url: string, html: []u8) -> (f: File, ok: bool) {
	md, spa := html_to_markdown(html)
	if spa {
		return {}, false
	}
	notice := strings.concatenate({"<!-- extracted from HTML (heuristic) — verify -->\n\n", md})
	return File{path = url_to_filename(url), data = transmute([]u8)notice}, true
}

// Add section-scoped, not-yet-seen links to `frontier`, marking each visited so
// no URL is fetched twice. Links outside the section prefix are dropped.
enqueue_links :: proc(
	frontier: ^[dynamic]string,
	visited: ^map[string]bool,
	links: []string,
	section: string,
) {
	for l in links {
		if !strings.has_prefix(l, section) {continue}
		if visited[l] {continue}
		visited[l] = true
		append(frontier, l)
	}
}

// Follow an llms.txt manifest: fetch every linked page concurrently and write
// each, plus the manifest itself. When `section` is non-empty, only links under
// that path prefix are followed, so a broad site manifest reached from a deep
// page pulls just that page's section, not sibling products.
write_llms_manifest :: proc(out: string, manifest: []u8, section: string, opt: Options) -> string {
	links := extract_links(string(manifest))
	kept := make([dynamic]string, 0, len(links))
	for l in links {
		if section == "" || strings.has_prefix(l, section) {
			append(&kept, l)
		}
	}

	fetched := fetch_many(kept[:], opt.jobs)
	files := make([dynamic]File, 0, len(kept) + 1)
	append(&files, File{path = "llms.txt", data = manifest})
	for f, i in fetched {
		if f.ok {
			append(&files, File{path = url_to_filename(kept[i]), data = f.data})
		}
	}
	return write_output(out, files[:], opt.force)
}

// The section prefix to filter a manifest's links by: the base where the
// manifest was found, plus the target's next path segment. A manifest at
// scheme://host/docs reached from a /docs/nakama/... target yields
// "scheme://host/docs/nakama/", narrowing the follow to that one section.
// Returns "" when the target adds no segment past the base — nothing to narrow
// to, so every link is followed.
section_prefix :: proc(base, target: string) -> string {
	clean := target
	for cut in ([]string{"?", "#"}) {
		if i := strings.index(clean, cut); i >= 0 {
			clean = clean[:i]
		}
	}
	clean = strings.trim_suffix(clean, "/")

	prefix := strings.concatenate({base, "/"})
	if !strings.has_prefix(clean, prefix) {
		return ""
	}
	rest := clean[len(prefix):]
	seg := rest
	if slash := strings.index_byte(rest, '/'); slash >= 0 {
		seg = rest[:slash]
	}
	if seg == "" {
		return ""
	}
	return strings.concatenate({base, "/", seg, "/"})
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

// The ladder of base URLs to probe for an llms manifest, deepest first: the
// target page's own path, then each parent segment, ending at the host root.
// Each base has no trailing slash, so callers append "/llms.txt". Deepest-first
// order means the most specific manifest wins. Query/fragment are dropped.
url_bases :: proc(url: string) -> []string {
	root := url_root(url)
	clean := url
	for cut in ([]string{"?", "#"}) {
		if i := strings.index(clean, cut); i >= 0 {
			clean = clean[:i]
		}
	}
	clean = strings.trim_suffix(clean, "/")

	out := make([dynamic]string, 0, 8)
	for len(clean) > len(root) {
		append(&out, clean)
		slash := strings.last_index_byte(clean, '/')
		if slash < len(root) {
			break
		}
		clean = clean[:slash]
	}
	append(&out, root)
	return out[:]
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

// The directory URL of a page: scheme://host plus the path up to and including
// its last '/'. Query/fragment are dropped. Used to scope the rung-3 crawl and
// to resolve relative links. A URL with no path segment (or none past the host)
// yields the host root with a trailing slash.
url_dir :: proc(url: string) -> string {
	clean := url
	for cut in ([]string{"?", "#"}) {
		if i := strings.index(clean, cut); i >= 0 {
			clean = clean[:i]
		}
	}
	root := url_root(clean)
	if slash := strings.last_index_byte(clean, '/'); slash >= len(root) {
		return clean[:slash + 1]
	}
	return strings.concatenate({root, "/"})
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

// Collect http(s) links from an HTML page's href attributes, each resolved to an
// absolute URL against `page_url`. Fragments (`#…`) and non-http schemes
// (`mailto:`, `tel:`) are dropped. Order follows appearance; deduping is the
// caller's job via the crawl's visited set.
extract_html_links :: proc(html, page_url: string) -> []string {
	out := make([dynamic]string, 0, 32)
	s := html
	for {
		i := strings.index(s, "href=")
		if i < 0 {break}
		s = s[i + 5:]
		if len(s) == 0 {break}
		q := s[0]
		if q != '"' && q != '\'' {continue}
		s = s[1:]
		end := strings.index_byte(s, q)
		if end < 0 {break}
		if link := resolve_url(page_url, s[:end]); link != "" {
			append(&out, link)
		}
		s = s[end + 1:]
	}
	return out[:]
}

// Resolve an href found on `base` to an absolute http(s) URL. Handles absolute
// URLs, scheme-relative (`//host/…`), root-relative (`/path`), and dotted or
// bare relatives (`./x`, `../x`, `x`). Returns "" for fragment-only hrefs and
// non-http schemes. Query/fragment on the href are dropped.
resolve_url :: proc(base, href: string) -> string {
	h := strings.trim_space(href)
	if h == "" || h[0] == '#' {
		return ""
	}
	for cut in ([]string{"#", "?"}) {
		if i := strings.index(h, cut); i >= 0 {
			h = h[:i]
		}
	}
	if h == "" {
		return ""
	}
	if strings.has_prefix(h, "http://") || strings.has_prefix(h, "https://") {
		return h
	}
	scheme_end := strings.index(base, "://")
	if scheme_end < 0 {
		return ""
	}
	if strings.has_prefix(h, "//") { // scheme-relative
		return normalize_url(strings.concatenate({base[:scheme_end], ":", h}))
	}
	if h[0] == '/' { // root-relative
		return normalize_url(strings.concatenate({url_root(base), h}))
	}
	// A colon before any slash means a scheme we don't follow (mailto:, tel:).
	if c := strings.index_byte(h, ':'); c >= 0 {
		if slash := strings.index_byte(h, '/'); slash < 0 || c < slash {
			return ""
		}
	}
	return normalize_url(strings.concatenate({url_dir(base), h})) // dotted/bare relative
}

// Collapse '.' and '..' path segments in an absolute URL, leaving scheme://host
// intact. Keeps a trailing slash if the input path had one.
normalize_url :: proc(url: string) -> string {
	root := url_root(url)
	if len(url) <= len(root) {
		return url
	}
	path := url[len(root):] // begins with '/'
	segs := strings.split(path, "/")
	out := make([dynamic]string, 0, len(segs))
	for seg in segs {
		switch seg {
		case ".", "": // current-dir and empty (from '//') carry no segment
		case "..":
			if len(out) > 0 {
				pop(&out)
			}
		case:
			append(&out, seg)
		}
	}
	rebuilt := strings.concatenate({root, "/", strings.join(out[:], "/")})
	if strings.has_suffix(path, "/") && !strings.has_suffix(rebuilt, "/") {
		rebuilt = strings.concatenate({rebuilt, "/"})
	}
	return rebuilt
}
