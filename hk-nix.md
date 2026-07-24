+++
date = '2026-07-22T00:00:00+01:00'
draft = true
title = 'Using hk with Nix'
+++

<!--
  INTRO GOES HERE (written separately): pre-commit vs. lefthook vs. hk, and a nod
  to husky / cargo-husky. This article is the hk-positive successor to
  /articles/lefthook-treefmt-direnv-nix and does not re-litigate lefthook's flaws.
-->

[hk][hk] is a fast, modern git hook manager and project linter configured in [Pkl][pkl].
[`hk-nix`][hk-nix] is to hk what [lefthook-nix][lefthook-nix] is to lefthook: you declare your hooks
in Nix, pin every tool with Nix, and the hooks install themselves whenever you enter the devshell.
hk-nix brings hk into the Nix + direnv toolstack.

[hk]: https://hk.jdx.dev/
[pkl]: https://pkl-lang.org/
[hk-nix]: https://github.com/nix-tools/hk-nix
[lefthook-nix]: https://github.com/sudosubin/lefthook.nix

## Synergies

The combination of hk, treefmt, direnv, and Nix creates some strong synergies:

**hk + direnv**: the git hooks install automatically when you `cd` into the directory. No manual `hk
install` step, no "remember to set it up after cloning". Clone the repo, enter it and `direnv
allow`. When the hooks change, direnv can reinstall them for you.

**hk + Nix**: every command a hook runs is referenced by an absolute `/nix/store` path, so the exact
tool that runs locally runs in CI. `nix flake check` runs the same hooks over the whole tree. There
are no formatter versions to coordinate and no setup docs to maintain.

**hk + treefmt**: hk drives *when* things run (which git event, over which staged files, fix vs.
check); treefmt owns *how code gets formatted* across every language in the repo. The two compose
cleanly, but treefmt substitutes calling hk's builtin formatters.

## Getting started

Here is a complete, self-contained `flake.nix` using [flake-parts][flake-parts] that installs hk and
runs [nixfmt][nixfmt] as a pre-commit hook. Starting from flake-parts makes it easy to split the
configuration into modules as the project grows.

[flake-parts]: https://flake.parts/
[nixfmt]: https://github.com/NixOS/nixfmt

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "https://nixos.org/channels/nixpkgs-unstable/nixexprs.tar.xz";
    flake-parts.url = "github:hercules-ci/flake-parts";

    hk-nix.url = "github:nix-tools/hk-nix";
    hk-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ flake-parts, hk-nix, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      imports = [ hk-nix.flakeModules.default ];

      perSystem =
        { config, pkgs, lib, ... }:
        {
          hk-nix.settings.hooks."pre-commit" = {
            fix = true;
            stash = "git";
            steps.nixfmt = {
              glob = "*.nix";
              check = "${lib.getExe pkgs.nixfmt} --check {{files}}";
              fix = "${lib.getExe pkgs.nixfmt} {{files}}";
            };
          };

          devShells.default = pkgs.mkShell {
            packages = [ config.hk-nix.package pkgs.git ];
            shellHook = config.hk-nix.shellHook;
          };
        };
    };
}
```

Activate it for direnv:

```
echo "use flake" > .envrc
direnv allow
```

Entering the devshell — via `direnv allow`, or `nix develop` — runs `config.hk-nix.shellHook`.

This writes the generated `hk.pkl` and installs the git hooks. Now any `git commit` runs nixfmt over
your staged `*.nix` files; with `fix = true`, hk formats them in place, and `stash = "git"` keeps
unstaged changes out of the way while it does. You may want to `.gitignore` the generated symlink:

```gitignore
/hk.pkl
```

Importing `hk-nix.flakeModules.default` also sets `checks.hk`, so CI gets the
same hook, read-only over every file, for free:

```
nix flake check
```

## Config-based hooks

hk-nix defaults to hk's support for **[config-based hooks][git-config-hooks]**, a
mechanism introduced in git 2.54. 

[git-config-hooks]: https://github.blog/open-source/git/highlights-from-git-2-54/#h-config-based-hooks

Historically a git hook could only be an executable script in `.git/hooks` (or in another directory
named by `core.hooksPath`). Sharing hooks across repositories meant copying scripts around or
leaning on a third-party manager, and a repository could effectively run only one script per event.

Git 2.54 lets you define hooks in git *configuration* instead — per-repository,
per-user, or system-wide. A hook is declared with a `hook.<name>.command` and the
event it fires on:

```gitconfig
[hook "linter"]
	event = pre-commit
	command = ~/bin/linter --cpp20
```

You can configure several hooks for the same event, and Git runs them in the
order it encounters their configuration:

```gitconfig
[hook "linter"]
	event = pre-commit
	command = ~/bin/linter --cpp20

[hook "no-leaks"]
	event = pre-commit
	command = ~/bin/leak-detector
```

Any traditional script in `$GIT_DIR/hooks` still runs, and it runs *last*, so
existing hooks are unaffected. `git hook list` shows the configured hooks and
where each one comes from, and an individual hook can be turned off without
deleting its configuration:

```gitconfig
[hook "linter"]
	enabled = false
```

For hk-nix this matters because installation writes hk's entry into
`.git/config` rather than dropping scripts into `.git/hooks`, leaving that
directory untouched. hk-nix always installs the config-based way (it never passes
`--legacy`), and prepends a recent git to `PATH` so the config-based path is
actually taken.

## Built-in linters

hk ships [140+ pre-configured linters, formatters, and checkers][hk-builtins] as
*builtins*: ready-made step definitions — globs, commands, and sensible defaults —
that you reference by name instead of hand-writing. hk-nix exposes each one as
`config.hk-nix.builtins.<name>`:

[hk-builtins]: https://hk.jdx.dev/builtins

```nix
perSystem =
  { config, pkgs, lib, ... }:
  let hk-builtins = config.hk-nix.builtins; in
  {
    hk-nix.settings.hooks."pre-commit" = {
      fix = true;
      stash = "git";
      steps = {
        gitleaks.builtin = hk-builtins.gitleaks;
        check_merge_conflict.builtin = hk-builtins.check_merge_conflict;
        actionlint.builtin = hk-builtins.actionlint;
      };
    };

    devShells.default = pkgs.mkShell {
      packages = [ config.hk-nix.package pkgs.git ];
      shellHook = config.hk-nix.shellHook;
    };
  };
```

A builtin identifies the tool; hk-nix pins it from Nixpkgs and injects it into the
step's `PATH` by absolute store path. Repin a tool with `.override`, and adjust
the hk step (glob, dependencies, profiles, …) with sibling fields:

```nix
steps.gitleaks = {
  builtin = config.hk-nix.builtins.gitleaks.override { package = pkgs.gitleaks_8_18; };
  glob = "src/**/*";
};
```

### What hk-nix adds on top of hk

hk on its own configures hooks; it does not install anything. hk-nix closes that
gap, and this is the whole reason to use it:

1. **It installs hk itself.** The hk binary is pinned through your flake and put
   on the devshell `PATH`. Contributors do not install hk out of band, and
   everyone runs the same version.
2. **It installs every tool your hooks reference.** Whether a step is a builtin
   or a custom `check`/`fix` string, the formatter, linter, or checker it names is
   pinned from Nixpkgs and referenced by `/nix/store` path. There is nothing to
   `apt install` or `npm install`; the same binaries run locally and in
   `nix flake check`.
3. **It keeps the hooks installed, continuously.** Because installation happens in
   the devshell `shellHook`, the hooks are (re)installed every time direnv loads
   the environment — on a freshly cloned repo on a new machine, and again whenever
   the hooks themselves change.

That third point is the direnv synergy in full. The generated `hk.pkl` and the
installed hooks are produced when you enter the devshell, so if you edit your hook
configuration you need direnv to reload. Tell it to watch the file that defines
the hooks, and the reinstall becomes automatic:

```bash
watch_file flake.nix
use flake
```

For a larger, modular flake, `watch_file` only the module that actually affects
the hooks, so unrelated changes don't churn the devshell:

```bash
watch_file modules/hooks.nix
use flake
```

Now editing a hook triggers a direnv reload, which regenerates `hk.pkl` and
reinstalls the hooks — no `hk install`, no stale configuration.

### Which builtins earn their place

Not every builtin belongs in an hk step. If a tool *formats* code — nixfmt,
prettier, black, rustfmt, gofmt, even a dead-code remover like deadnix — it is
better centralized in treefmt (next section) than wired up one builtin at a time.
The builtins that pull their weight as hk steps are the ones treefmt cannot
express, because they analyze or gate rather than rewrite:

- **Secret and security scanning:** `gitleaks`, `detect_private_key`.
- **Commit hygiene:** `check_merge_conflict`, `check_added_large_files`,
  `check_case_conflict`, `check_symlinks`, `check_executables_have_shebangs`,
  `no_commit_to_branch`.
- **Commit-message hooks** (on the `commit-msg` event, which is not a formatting
  concern at all): `check_conventional_commit`, `harper_commit_message`,
  `cocogitto_commit_msg`.
- **Linters that report but never rewrite:** `shellcheck`, `actionlint`,
  `hadolint`, `yamllint`, `cargo_clippy`, `golangci_lint`, `mypy`.

## Combining treefmt-nix and hk-nix

hk has a `nix_fmt` builtin, and you could format your whole project by stacking up
one formatting builtin per language. But formatting is exactly the job
[treefmt][treefmt] exists to own: one configuration mapping each syntax to its
formatter, one `treefmt` command that formats the entire tree, and — via
[treefmt-nix][treefmt-nix] — a `nix fmt` and a formatting `nix flake check`. The
one thing treefmt does not do is install itself into git.

[treefmt]: https://treefmt.com/
[treefmt-nix]: https://github.com/numtide/treefmt-nix

So the synergy is to let each tool do the half it is good at: treefmt is the
single source of truth for formatting across every language, and hk runs the
resulting wrapper as one step. You get treefmt's unified, multi-language
formatting *and* hk's always-on hooks, CI parity, and staged-file scoping.

Add treefmt-nix as an input, import its flake module, and describe your
formatters once:

```nix
imports = [
  hk-nix.flakeModules.default
  inputs.treefmt-nix.flakeModule
];

perSystem =
  { config, pkgs, ... }:
  {
    treefmt = {
      projectRootFile = "flake.nix";
      programs.nixfmt.enable = true;
      programs.prettier.enable = true; # add formatters for every language you use
    };

    hk-nix.settings.hooks."pre-commit" = {
      fix = true;
      stash = "git";
      # {{files}} is the staged files; treefmt applies whichever formatter matches
      # each one and ignores the rest. --fail-on-change turns "would reformat" into
      # a non-zero exit so the commit is blocked; --no-cache avoids a writable-cache
      # requirement inside the nix flake check sandbox.
      steps.treefmt = {
        check = "${config.treefmt.build.wrapper}/bin/treefmt --fail-on-change --no-cache {{files}}";
        fix = "${config.treefmt.build.wrapper}/bin/treefmt --no-cache {{files}}";
      };
    };

    devShells.default = pkgs.mkShell {
      packages = [ config.hk-nix.package pkgs.git ];
      shellHook = config.hk-nix.shellHook;
    };
  };
```

`config.treefmt.build.wrapper` is a treefmt binary with your generated config
baked in, referenced — like every other tool — by absolute store path. The result
is one formatting story used three ways: `nix fmt` in the shell, the pre-commit
hook via hk, and `nix flake check` (both `checks.treefmt` from treefmt-nix and the
formatting inside `checks.hk`) in CI.

The direnv loop applies here too. If your treefmt configuration lives in its own
module, watch it so a new formatter or an enabled program reinstalls the hook
without a manual step:

```bash
watch_file modules/treefmt.nix
watch_file modules/hooks.nix
use flake
```

Formatting through treefmt and gating through hk's non-formatting builtins, both
installed and pinned by Nix and kept in sync by direnv, is the whole stack working
together: clone the repo, `cd` in, and every contributor is formatting and
committing with the same tools you are.
