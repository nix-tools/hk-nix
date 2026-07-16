# hk-nix

A Nix wrapper for [`hk`](https://github.com/jdx/hk), the fast git hook manager
and project linter. It is to `hk` what
[`lefthook.nix`](https://github.com/sudosubin/lefthook.nix) is to `lefthook`:
declare your hooks in Nix, pin the linters with Nix, and get the *same* checks

- **always on** — entering the dev shell installs the git hooks, so they run on
  every commit/push; and
- **always in sync with CI** — the identical hooks run as a `nix flake check`
  derivation.

Commands reference linters by absolute `/nix/store` path, so the exact same
pinned tools run locally and in CI.

## How it works

`hk` is configured with [Pkl](https://pkl-lang.org) (`hk.pkl`). hk-nix generates
that `hk.pkl` from a Nix attrset and points its `amends` at hk's `Config.pkl`
schema **from the pinned `jdx/hk` input at an absolute store path**, so
evaluation is fully offline (no `package://` download) and works inside the
`nix flake check` sandbox. The generated file is symlinked into the repo root
and `hk install` wires up git hooks — using **config-based hooks on git 2.54+**
(`hook.<name>.command` in `.git/config`; `.git/hooks/` is left untouched).

## Usage

```nix
{
  inputs = {
    nixpkgs.url = "https://nixos.org/channels/nixpkgs-unstable/nixexprs.tar.xz";
    flake-parts.url = "github:hercules-ci/flake-parts";

    hk-nix.url = "github:sshine/hk-nix";
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
              check = "${lib.getExe pkgs.nixfmt-rfc-style} --check {{files}}";
              fix = "${lib.getExe pkgs.nixfmt-rfc-style} {{files}}";
            };
          };

          # Always on: installs the hooks when the shell is entered.
          devShells.default = pkgs.mkShell {
            packages = [ config.hk-nix.package pkgs.git ];
            inherit (config.hk-nix) shellHook;
          };
        };
    };
}
```

`imports = [ hk-nix.flakeModules.default ]` also sets `checks.hk`, so `nix flake
check` runs the `pre-commit` hook read-only over all files.

Add the generated symlink to your `.gitignore`:

```gitignore
/hk.pkl
```

## Options (`perSystem.hk-nix`)

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `settings` | attrs | `{ }` | The `hk.pkl` top-level (e.g. `{ hooks = { ... }; }`). |
| `package` | package | overlay's `hk` | The hk binary. Override with `pkgs.hk` (nixpkgs) or another build. |
| `src` | path | `self` | Project root copied into the check derivation. |
| `checkHook` | str | `"pre-commit"` | Hook run (read-only) by `checks.hk`. |
| `shellHook` | str | *(read-only)* | Symlinks `hk.pkl` and installs the git hooks. |
| `check` | package | *(read-only)* | The `checks.hk` derivation. |

### Choosing the hk binary

hk-nix ships `overlays.default` (defines `pkgs.hk`, built from the pinned
`jdx/hk` input) and `hk-nix.package` defaults to it. To use nixpkgs' hk instead:

```nix
nixpkgs.overlays = [ ];            # don't apply hk-nix's overlay
hk-nix.package = pkgs.hk;          # use nixpkgs' hk
```

## Limitations

- The installed hook runs `hk`, so `hk` must be on `PATH` when git fires it.
  The dev shell puts it there; with [direnv](https://direnv.net) it is present
  for editors/terminals opened in the project too. Committing from a context
  with no `hk` on `PATH` (e.g. a GUI launched outside direnv) skips the hook.
- Builtin linters (`Builtins.pkl`) are not wired up yet — declare steps
  explicitly (`glob` + `check`/`fix` shell strings).
- `check`/`fix` are shell strings; the `Command { argv = ... }` form is not yet
  rendered.
- Config is injected by symlinking `hk.pkl`; the `HK_FILE` env-var mechanism is
  not supported yet.
- Per-repo install only (no `hk install --global`).
