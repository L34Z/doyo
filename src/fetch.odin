package doyo

// Network + unpack layer. This is the impure boundary:
// it shells to `curl` (HTTPS/TLS/redirects) and `tar` (unpack), touches temp
// files, and is deliberately kept out of the deterministic test suite. Fetch
// completion order is nondeterministic; the pure transform downstream is not.
//
// ## Changes
// - 2026-07-28: curl fetch, concurrent fetch pool, tar unpack, dir walk.

import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"

// Result of one fetch: the bytes, and whether curl reported success.
Fetch :: struct {
	data: []u8,
	ok:   bool,
}

// Fetch one URL to bytes via `curl -sSL --fail`. ok=false on any HTTP/network
// error (curl exits non-zero). Binary-safe: stdout is captured as raw bytes.
fetch_bytes :: proc(url: string) -> Fetch {
	state, stdout, _, err := os.process_exec(
		{command = {"curl", "-sSL", "--fail", url}},
		context.allocator,
	)
	if err != nil || !state.success || state.exit_code != 0 {
		return {data = stdout, ok = false}
	}
	return {data = stdout, ok = true}
}

// Download a URL to `dest`, showing curl's own progress bar. stderr is
// inherited (the bar renders live on the terminal); stdout is unused since
// curl writes the body straight to the file with -o. Used for the one big
// repo-tarball fetch, where progress matters, unlike the many small fetches
// downstream that run silently.
fetch_to_file :: proc(url, dest: string) -> bool {
	p, err := os.process_start(
		{command = {"curl", "-L", "--fail", "--progress-bar", "-o", dest, url}, stderr = os.stderr},
	)
	if err != nil {
		return false
	}
	state, werr := os.process_wait(p)
	return werr == nil && state.success && state.exit_code == 0
}

// Fetch with a content-negotiation header, e.g. Accept: text/markdown so a site
// can serve its own machine-readable form.
fetch_with_accept :: proc(url, accept: string) -> Fetch {
	header := strings.concatenate({"Accept: ", accept})
	state, stdout, _, err := os.process_exec(
		{command = {"curl", "-sSL", "--fail", "-H", header, url}},
		context.allocator,
	)
	if err != nil || !state.success || state.exit_code != 0 {
		return {data = stdout, ok = false}
	}
	return {data = stdout, ok = true}
}

// Shared work-list for the fetch pool: workers pull indices atomically and fill
// their own result slot, so no two threads write the same memory.
Fetch_Work :: struct {
	urls:    []string,
	results: []Fetch,
	next:    int,
}

// Fetch many URLs with a fixed pool of `jobs` concurrent curl subprocesses.
// Results are index-aligned with `urls`; order is preserved regardless of
// completion order, keeping downstream output deterministic.
fetch_many :: proc(urls: []string, jobs: int) -> []Fetch {
	work := Fetch_Work {
		urls    = urls,
		results = make([]Fetch, len(urls)),
	}
	n := min(jobs, len(urls))
	if n <= 1 {
		for u, i in urls {
			work.results[i] = fetch_bytes(u)
		}
		return work.results
	}

	worker :: proc(data: rawptr) {
		w := (^Fetch_Work)(data)
		for {
			i := sync.atomic_add(&w.next, 1)
			if i >= len(w.urls) {
				return
			}
			w.results[i] = fetch_bytes(w.urls[i])
		}
	}

	threads := make([]^thread.Thread, n)
	defer delete(threads)
	for i in 0 ..< n {
		threads[i] = thread.create_and_start_with_data(&work, worker)
	}
	for t in threads {
		thread.join(t)
		thread.destroy(t)
	}
	return work.results
}

// Unpack a gzip tarball into a flat []File. Shells to `tar` via a
// temp dir, then walks it. The codeload tarball wraps everything in a single
// `<repo>-<ref>/` dir; that prefix is stripped so paths are repo-relative.
download_and_unpack :: proc(url: string) -> (files: []File, ok: bool) {
	dir, terr := os.make_directory_temp("", "doyo-*", context.allocator)
	if terr != nil {
		return nil, false
	}
	defer os.remove_all(dir)

	// Stream the tarball straight to disk with a live progress bar (curl writes
	// the bar to the inherited stderr), so a big repo never sits in memory.
	tarpath := strings.concatenate({dir, "/repo.tar.gz"})
	if !fetch_to_file(url, tarpath) {
		return nil, false
	}

	// Extract into a dedicated subdir so the tarball file doesn't sit beside the
	// wrapper dir (which would defeat single_subdir's one-entry check).
	xdir := strings.concatenate({dir, "/x"})
	if os.make_directory(xdir) != nil {
		return nil, false
	}
	state, _, _, err := os.process_exec(
		{command = {"tar", "-xzf", tarpath, "-C", xdir}},
		context.allocator,
	)
	if err != nil || !state.success {
		return nil, false
	}

	// Descend through the single wrapper directory codeload adds.
	root := xdir
	if top, found := single_subdir(xdir); found {
		root = strings.concatenate({xdir, "/", top})
	}
	out := make([dynamic]File, 0, 64)
	walk_dir(root, "", &out)
	return out[:], true
}

// The lone subdirectory name of `dir`, if there is exactly one entry and it is a
// directory (the codeload wrapper). Otherwise ("", false).
single_subdir :: proc(dir: string) -> (string, bool) {
	infos, err := os.read_directory_by_path(dir, -1, context.allocator)
	if err != nil || len(infos) != 1 || infos[0].type != .Directory {
		return "", false
	}
	return strings.clone(infos[0].name), true
}

// Recursively read every regular file under `root` into `out`, with `prefix`
// giving each its slash path relative to the walk root.
walk_dir :: proc(root, prefix: string, out: ^[dynamic]File) {
	infos, err := os.read_directory_by_path(root, -1, context.allocator)
	if err != nil {
		return
	}
	for info in infos {
		full := strings.concatenate({root, "/", info.name})
		rel := strings.concatenate({prefix, info.name})
		switch info.type {
		case .Directory:
			walk_dir(full, strings.concatenate({rel, "/"}), out)
		case .Regular:
			if data, rerr := os.read_entire_file(full, context.allocator); rerr == nil {
				append(out, File{path = rel, data = data})
			}
		case .Undetermined, .Symlink, .Named_Pipe, .Character_Device, .Block_Device, .Socket:
		// skipped: non-regular entries carry no doc bytes
		}
	}
}
