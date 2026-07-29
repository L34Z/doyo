package main

// doyo — DOcumentation YOinker (DESIGN.md). Thin CLI shell: parse args, run,
// fail loud with a single non-zero exit on any error (GUIDELINES §5).
//
// ## Changes
// - 2026-07-28: Replace scaffold; wire arg-parse → doyo.run with usage + exit.

import doyo "src"
import "core:fmt"
import "core:os"

USAGE :: `doyo <owner/repo | github-url | arbitrary-url>
  --path <dir>    override docs-folder detection (repo mode)
  --out <dir>     output location (default ./<owner>-<repo>/ or ./<host>/)
  --force         allow overwriting an existing output dir
  --jobs <n>      concurrent fetches (default 8)
`

main :: proc() {
	for a in os.args[1:] {
		if a == "-h" || a == "--help" {
			fmt.print(USAGE)
			os.exit(0)
		}
	}
	opt, err := doyo.parse_args(os.args[1:])
	if err != "" {
		fmt.eprintf("doyo: %s\n\n%s", err, USAGE)
		os.exit(1)
	}
	if e := doyo.run(opt); e != "" {
		fmt.eprintf("doyo: %s\n", e)
		os.exit(1)
	}
}
