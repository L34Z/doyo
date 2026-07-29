package doyo

import "core:testing"

// End-to-end golden over the generated fixture: selection keeps exactly the
// docs/ rST pages (source + png dropped), and each cleaned page matches its
// computed oracle byte-for-byte (GUIDELINES §6 invariant + golden).
@(test)
fixture_pipeline_matches_oracle :: proc(t: ^testing.T) {
	repo := gen_repo(5)
	sel := select_docs(repo)
	testing.expect_value(t, len(sel), 5) // 5 rst pages, no src/main.go, no logo.png

	for f, i in sel {
		got := string(clean(f.path, f.data))
		want := gen_page_clean(i)
		testing.expectf(t, got == want, "page %d\n got: %q\nwant: %q", i, got, want)
	}
}
