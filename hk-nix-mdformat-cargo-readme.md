# When a formatter and a generator disagree about your README

Notes for a blog post.

## The setup

[hashpinner][hashpinner]'s `README.md` is generated, and both halves of that are enforced by git
hooks driven by [hk], configured through [hk-nix]:

- **pre-commit** runs [treefmt] in fix mode. Among its formatters is `mdformat`, which owns every
  `*.md` in the tree — including `README.md`.
- **pre-push** runs `cargo-readme`, which renders `README.tpl` with the crate's CLI docs spliced in,
  and diffs the result against the committed `README.md`.

```nix
readme = {
  check = "${cargo-readme} ${readmeArgs} | diff - README.md";
  fix = "${cargo-readme} ${readmeArgs} -o README.md";
};
```

This is a common shape:

- a fast formatter on commit,
- a slower "is the generated artifact in sync" check on push.

The two hooks had coexisted happily for months.

## The symptom

```
$ git push
✗ readme  – ERROR

readme stderr:
28,29d27
< [releases]: https://github.com/sshine/hashpinner/releases
<
222a221,222
>
> [releases]: https://github.com/sshine/hashpinner/releases
hk ERROR To fix, run: […]/cargo-readme readme --project-root crates/hashpinner \
  --input src/main.rs --template ../../README.tpl -o README.md
```

Read the diff. `<` is what `cargo-readme` produced, `>` is what is committed. Nothing is
missing and nothing is added — the link reference definition has *moved*, from line 28 to the
bottom of a 222-line file. That is the entire disagreement.

The `clippy` and `lock-check` lines in the same run reported `aborted`, which is just hk
cancelling the remaining steps once one failed. Red herrings.

## The loop

The error message helpfully tells you how to fix it, and the fix does not work:

1. Run the suggested command. `README.md` is rewritten in `cargo-readme`'s form, definition at
   line 28.
1. `git commit --amend`. pre-commit fires, treefmt fires, mdformat moves the definition back to
   the bottom, and the amended commit contains the file in mdformat's form.
1. `git push`. pre-push regenerates, gets line 28 again, diffs against the bottom, fails.

Goto 1. Each hook is individually correct and idempotent; neither is looping. What loops is
*you*, because the two hooks disagree on what the file should look like and the fix command
only satisfies one of them. The output is confusing precisely because the tool that failed
tells you to do the thing that the *other* tool will undo, and never mentions that other tool
exists.

## The cause

mdformat is not a patcher, it is a renderer: it parses markdown into an AST and serialises the
AST back out. A link reference definition is not an inline node — it is document-level data
that inline `[text][label]` nodes merely refer to. So its original position in the source is
not part of the AST that mdformat round-trips, and on the way out all definitions are emitted
together at the end of the document.

That is a perfectly reasonable normalisation. It just means:

> A generated markdown file that is also formatted must be a **fixed point** of the formatter,
> or the two checks can never both pass.

`cargo-readme` copies `README.tpl` through verbatim, so the template's byte-level choices —
where you happen to have written a definition — flow straight into the generated output. If
the template is not already in mdformat's canonical form, the generated file cannot be either.

## The best part: what actually triggered it

No hook config was touched. The commit that broke the push was a prose edit, reflowing a
paragraph in `README.tpl`:

```diff
-Prebuilt static binaries for x86_64 and aarch64 Linux are attached to each
-[release](https://github.com/sshine/hashpinner/releases).
+You can download prebuilt [static binaries for x86_64 and aarch64 Linux][releases].
+
+[releases]: https://github.com/sshine/hashpinner/releases
```

An inline link became a reference-style link. Before that edit the template contained no link
reference definitions at all, so `cargo-readme`'s raw output *happened* to be a fixed point of
mdformat, and the two hooks *happened* to agree. The invariant was never established; it held
by accident, and switching one link's syntax revoked it.

This is the interesting failure mode. The bug had been latent in the hook configuration since
the day both hooks were written, and it was armed by someone editing English.

## The fix

Stop comparing raw generator output against a formatted file. Make the generator's output pass
through the formatter, in both the check and the fix, so the pipeline computes the same
normal form the committed file is in:

```nix
# cargo-readme emits markdown that mdformat then rewrites (link reference
# definitions move to the end of the file), so the raw output never equals the
# committed README.md and the two hooks would undo each other forever. Reuse
# treefmt's own mdformat so the plugin set cannot drift from the pre-commit one.
mdformat = config.treefmt.settings.formatter.mdformat.command;

readme = "${cargo-readme} ${readmeArgs} | ${mdformat} -";
```

```nix
readme = {
  check = "${readme} | diff - README.md";
  fix = "${readme} > README.md";
};
```

Two details worth keeping:

- **Reuse treefmt's own mdformat, by store path.** Not `pkgs.mdformat`, and not a bare
  `mdformat` on `PATH`. `config.treefmt.settings.formatter.<name>.command` is the exact wrapped
  binary treefmt invokes, plugins and all. Spelling the tool twice is how you get to have this
  bug again in a year, when one of the two grows a plugin and the other does not. The absolute
  store path matters for a second reason here: hk hooks also run under `nix flake check`, in a
  sandbox with no devshell `PATH`.
- **Fix the other copy of the pipeline.** The same two commands existed in the `justfile` as
  `just readme` / `just readme-check`, and `just ci` depends on the latter — so CI was failing
  the same way for the same reason. A generated-file rule that lives in two places is two
  places to forget. (Better still: have the justfile call the hook, or the hook call the
  justfile. Left undone.)

To let the `justfile` say `mdformat` at all, the same package goes into the devshell:

```nix
# The same mdformat treefmt drives, so `just readme` normalises its output
# exactly the way the pre-commit hook would.
config.treefmt.build.programs.mdformat
```

## Alternatives considered

- **Move the definitions to the bottom of `README.tpl`.** Zero cost, and it works today. But it
  re-establishes the invariant by coincidence rather than by construction — it is the state the
  repo was already in before the prose edit, and the next markdown construct where mdformat has
  an opinion breaks it again. Rejected for being the thing that just failed.
- **Ask mdformat to preserve definition placement.** Not a knob, and it should not be one; the
  AST does not carry the information.
- **Exclude `README.md` from treefmt.** Trades a generated file that is formatted for one that
  is not. Also loses the formatter on the hand-written `README.tpl` prose, which is the part a
  human actually reads while editing.

## The general rule

For any file that is both **generated** and **formatted**, the invariant to enforce is:

```
format(generate(sources)) == committed_file
```

Not `generate(sources) == committed_file`. If the check and the fix in your hook config do not
both spell out the `format(...)`, you have not written a sync check, you have written a race
between two hooks — and it will pass until the day the generator's output stops accidentally
being canonical.

Corollary for hook authors: whenever a **pre-commit fix** step and a **pre-push check** step can
both claim the same file, they need to agree on its normal form by construction. Consider
whether the check even belongs on push, or whether generating-and-formatting should just be a
pre-commit fix step next to the formatter, with push verifying nothing.

## Postscript

This file is in the same repository, so committing it ran it through the same mdformat. I wrote
its three link definitions — `hk`, `hk-nix`, `treefmt` — inline under the paragraph that uses
them, near the top. Scroll to the bottom of the source. They are down there now.

[hashpinner]: https://github.com/sshine/hashpinner
[hk]: https://hk.jdx.dev
[hk-nix]: https://github.com/nix-tools/hk-nix
[treefmt]: https://github.com/numtide/treefmt-nix
