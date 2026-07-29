# doyo

> [!NOTE]
> This project was made for my personal use and enjoyment. AI was used.

**doyo** (DOcumentation YOinker) is a small and relatively fast single binary tool
to [yoink](https://dictionary.cambridge.org/us/dictionary/english/yoink) project documentation for LLM use.

Supports github repositories and regular http URLs 

Written in [Odin](https://odin-lang.org/).

Indexing and search are left to a separate tool such as graphify.


## Install

The dev environment is a pinned Nix flake. Enter it with:

```
nix develop     # or `direnv allow` if you use direnv
```

That gives you the Odin compiler, the `ols` language server, and `gdb`. At
runtime doyo also shells out to `curl` and `tar`, which the flake does not
provide; use your system's copies.

## Build

```
odin build . -out:build/doyo
```

Then run it:

```
build/doyo <owner/repo | github-url | arbitrary-url>
```

## Usage

```
doyo <owner/repo | github-url | arbitrary-url>
  --path <dir>    override docs-folder detection (repo mode)
  --out <dir>     output location (default ./<owner>-<repo>/ or ./<host>/)
  --force         allow overwriting an existing output dir
  --jobs <n>      concurrent fetches (default 8)
```

Examples:

```
doyo godotengine/godot-docs
doyo https://github.com/ziglang/zig
doyo https://docs.example.com
```

Output goes to `./<owner>-<repo>/` in repo mode or `./<host>/` in URL mode,
mirroring the docs tree as files, plus a sorted `index.md` that lists
everything. doyo refuses to overwrite an existing output directory unless you
pass `--force`.

## How it works

doyo takes two kinds of input.

**GitHub repo** (`owner/repo` or a github.com URL) is the primary path. doyo
downloads the whole repo as a single tarball from `codeload.github.com`, so
there is one request with no API token and no rate-limit fight. It unpacks the
tarball with `tar` and then picks the docs in priority order:

1. `llms.txt` or `llms-full.txt` at the root, treated as an authoritative
   manifest to follow.
2. A `docs/` folder (or `doc/`, `documentation/`), taking everything under it.
3. Otherwise every `*.md` and `*.rst` file in the tree, plus `README`.

Auto-detection skips vendored and tooling trees (`thirdparty/`, `vendor/`,
`node_modules/`) and directories marked internal by a leading dot (`.github/`)
or underscore (`_static/`, `_tools/`). An explicit `--path` is taken as given.

**Arbitrary URL** is the fallback for docs with no public repo. doyo tries three
rungs and stops at the first that works:

1. `llms.txt` or `llms-full.txt` on the host, already Markdown and authored for
   this purpose.
2. The page's own machine-readable form (a `.md` suffix, `?plain=1`, or an
   `Accept: text/markdown` header).
3. A hand-rolled HTML-to-Markdown pass that drops known boilerplate tags
   (`<nav>`, `<header>`, `<footer>`, `<aside>`, `<script>`, `<style>`) and keeps
   the rest. This rung prints `extracted from HTML (heuristic) — verify` per
   page and leans toward leaving cruft in rather than dropping real content.

Fetched pages get a light, line-level cleanup with no format parser. doyo
removes only provably contentless noise: rST comment blocks (`.. comment`),
navigation directives (`.. toctree::`), and CSS class-setters
(`.. rst-class::`, `.. class::`, `.. cssclass::`). For class-setters it drops
only the marker line and never the indented body, so prose survives even when a
doc styles a block. Image directives lose the binary reference but keep the alt
text, since the LLM cannot see the file. Prose, code blocks, and inline roles
(`:ref:`, `:class:`) are left raw because they carry meaning.

Repo mode and URL rungs 1 and 2 serve the publisher's own source, so they are
never wrong. URL rung 3 is a transparent guess, and doyo flags it as one.

## Determinism

Fetching runs a fixed pool of concurrent `curl` subprocesses (8 by default,
set with `--jobs`), and their completion order is not fixed. The transform is
deterministic: each page is written to a path derived from its URL rather than
its arrival order, so the on-disk output is byte-identical from one run to the
next, and `index.md` is sorted once at the end.

The live network is the one thing that is not reproducible, since a site can
change between runs. The determinism guarantee covers the pure transform layer:
the same fetched bytes always produce the same output.

## Scope

In scope for v1:

- GitHub repo mode (tarball, filter, light cleanup).
- Arbitrary-URL mode, all three rungs of the ladder.
- Markdown and reStructuredText source, served lightly cleaned.
- Godot's full docs, via the `godotengine/godot-docs` repo.

Out of scope until a design decision promotes it:

- Faithful format converters (reStructuredText, XML, MDX, AsciiDoc to Markdown).
- JavaScript single-page apps, which need a headless browser.
- Auth-walled or bot-challenged sites.
- Git hosts other than GitHub.
- `robots.txt` compliance, since a human runs the tool on purpose.

doyo fails loud when it hits a JavaScript-rendered shell or a bot-blocked site,
naming the problem rather than guessing.

## Testing and benchmarks

The suite splits at the network boundary. The pure transform (filter, select,
clean) is the only unit-tested layer. A fixture generator in the repo emits a
synthetic tarball with known content, and golden tests assert the exact cleaned
output byte for byte, with no download.

```
odin test src
```

The benchmark runs the same transform over a generated 1000-file docs tree and
reports throughput, with no network variance:

```
odin build bench -out:build/bench && build/bench
```

On the reference tree it processes 1000 files in about 14 ms. The network layer
(the `curl` fetch) has no unit test; it gets a manual smoke check against a
pinned real repo, kept out of the deterministic suite.

## Dependencies

- `curl` at runtime for HTTPS, redirects, and compression. This moves to native
  TLS at Odin 1.0.
- `tar` at runtime to unpack the repo tarball. This may move in-process later.

There are no bundled C libraries. The HTML tokenizer is hand-rolled and owned.
