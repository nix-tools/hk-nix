# hk pre-push bug: first push to an empty remote

## Symptom

`git push` on a repo that has **never been pushed** fails inside hk's pre-push hook:

```
hk 1.51.0 by @jdx – pre-push – check
⠋ files - Fetching files between origin/HEAD and <sha>
Error: Failed to parse reference: origin/HEAD

Caused by:
    revspec 'origin/HEAD' not found; class=Reference (4); code=NotFound (-3)

Location:
    src/git.rs:1493:18
error: failed to push some refs
```

The push aborts before any linter runs; nothing lands on the remote.

## Root cause (hk 1.51.0)

git feeds the pre-push hook one line per ref on stdin:

```
<local-ref> <local-sha>  <remote-ref> <remote-sha>
```

For a **new branch** the remote sha is all-zeros, so hk can't use it as the diff
base and falls back (`src/cli/run/pre_push.rs`):

1. `matching_remote_branch("origin")` → nothing (never pushed, no `refs/remotes/origin/*`).
2. `resolve_default_branch()` → `default_branch()` (`src/git.rs:349`), which tries:
   - `git symbolic-ref refs/remotes/origin/HEAD` → **fails**. That ref is only created
     by `git clone`, never by `git init` + `git remote add`.
   - `matching_remote_branch("origin")` → nothing.
   - `git ls-remote --heads origin main`/`master` → nothing (**remote is empty**).
   - last resort: returns the literal string `"origin/HEAD"` — with a comment saying
     *"to let callers handle errors"* (`src/git.rs:382`).
3. The caller `files_between_refs` (`src/git.rs:1488`) does **not** handle it — it passes
   `"origin/HEAD"` straight to libgit2's `revparse_single`, which errors out.

That unmet "let callers handle errors" contract is the bug. Two conditions compound,
both from never having pushed:

- **empty remote** → the `main`/`master` ls-remote probes find nothing;
- **`git init` (not clone)** → `refs/remotes/origin/HEAD` was never set.

## Reproduction

Empty bare remote + working repo, hook installed *before* any push:

```sh
git init --bare remote.git
git init work && cd work
git remote add origin ../remote.git
# ... write hk.pkl with a pre-push step ...
git add hk.pkl && git commit -m "install hk"
hk install --legacy
echo hi > first.txt && git add first.txt && git commit -m "add first.txt"
git push -u origin main   # -> revspec 'origin/HEAD' not found
```

The distinguishing factor vs. existing tests: every test in `test/pre_push.bats` does
`git push origin main` *before* `hk install`, so the remote always has a branch (and
`ls-remote main` succeeds) by the time the hook runs. Installing the hook first, against
a never-populated remote, is the only path that reaches the `"origin/HEAD"` literal.

## Fix

In `files_between_refs` (`src/git.rs`), when the from-ref can't be resolved there is no
base to diff against, so lint everything being pushed:

- **libgit2 path**: diff `to_ref` against the empty tree.
- **shell path**: list all files at `to_ref` via `ls-tree` (object-format agnostic).

A first push then lints everything being pushed instead of erroring out.

## Workaround (until a fixed hk ships)

Skip the hook for the first push only:

```sh
git push --no-verify -u origin main   # or: HK=0 git push -u origin main
```

After the first push `refs/remotes/origin/main` exists, so later pushes hit the
`matching_remote_branch` path and the hook works normally.

## Commits

Branch `fix/pre-push-empty-remote` in the hk repo (test first so the maintainer can
verify it fails before the fix):

```
test(pre-push): cover first push to an empty remote
fix(pre-push): lint pushed files when the base ref is unresolvable
```
