package bench

// Benchmark harness: one command, generated
// reference material, a number in the repo. Runs the whole pure transform
// (select → clean) over a synthetic docs tree and reports throughput. No
// network, so the number is repeatable run to run.
//
// ## Changes
// - 2026-07-28: Initial select+clean throughput benchmark.

import doyo "../src"
import "core:fmt"
import "core:time"

PAGES :: 1000

main :: proc() {
	repo := doyo.gen_repo(PAGES)

	total_bytes := 0
	for f in repo {
		total_bytes += len(f.data)
	}

	start := time.tick_now()
	sel := doyo.select_docs(repo)
	out_bytes := 0
	for f in sel {
		out_bytes += len(doyo.clean(f.path, f.data))
	}
	elapsed := time.tick_since(start)

	secs := time.duration_seconds(elapsed)
	mb := f64(total_bytes) / (1024 * 1024)
	fmt.printf("doyo transform benchmark\n")
	fmt.printf("  pages:      %d\n", PAGES)
	fmt.printf("  input:      %.2f MB across %d files\n", mb, len(repo))
	fmt.printf("  selected:   %d files, %d cleaned bytes\n", len(sel), out_bytes)
	fmt.printf("  elapsed:    %.3f ms\n", time.duration_milliseconds(elapsed))
	fmt.printf("  throughput: %.1f MB/s\n", mb / secs)
}
