package doyo

// Orchestration (DESIGN §3, §7): classify the target, run the matching mode, and
// write output. Returns an error string ("" on success) so the CLI can fail loud
// with a single exit point.
//
// ## Changes
// - 2026-07-28: Dispatch + GitHub repo mode (tarball → filter → clean → write).

import "core:fmt"
import "core:strings"

// Run doyo end to end for parsed options. The one place modes are dispatched.
run :: proc(opt: Options) -> string {
	t := classify_target(opt.target)
	if t.is_repo {
		return run_repo(t, opt)
	}
	return run_url(t, opt)
}

// Repo mode: one tarball fetch, unpack, select docs, light-clean, write tree.
run_repo :: proc(t: Target, opt: Options) -> string {
	if t.owner == "" || t.repo == "" {
		return "could not parse owner/repo from target"
	}
	url := fmt.aprintf("https://codeload.github.com/%s/%s/tar.gz/HEAD", t.owner, t.repo)
	fmt.eprintf("doyo: fetching %s/%s …\n", t.owner, t.repo)

	files, ok := download_and_unpack(url)
	if !ok {
		return strings.concatenate({"failed to fetch or unpack repo tarball: ", url})
	}
	fmt.eprintf("doyo: unpacked %d files, selecting docs …\n", len(files))

	sel := select_docs(files, opt.path)
	if len(sel) == 0 {
		return "no documentation found in repo (try --path <dir>)"
	}

	cleaned := make([]File, len(sel))
	for src, i in sel {
		cleaned[i] = File {
			path = src.path,
			data = clean(src.path, src.data),
		}
	}

	out := opt.out != "" ? opt.out : fmt.aprintf("./%s-%s", t.owner, t.repo)
	if e := write_output(out, cleaned, opt.force); e != "" {
		return e
	}
	fmt.eprintf("doyo: wrote %d docs → %s\n", len(cleaned), out)
	return ""
}
