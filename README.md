# hk-nix

A Nix wrapper for [`hk`](https://github.com/jdx/hk), the fast git hook manager and project linter.
`hk-nix` is to `hk` what [`lefthook.nix`][lefthook-nix] is to `lefthook`: declare your hooks in Nix,
pin the linters with Nix, and always enable hooks by installing them via a Nix devshell.

[lefthook-nix]: https://github.com/sudosubin/lefthook.nix

`hk-nix` is **always on**: upon entering a devshell, `hk-nix` installs the git hooks, so they run on freshly cloned repositories, given `direnv allow` or `nix develop`, and whenever the hooks change, either by reloading the devshell incidentally or by watching the hooks from `.envrc`.

`hk-nix` is **always in sync with CI**: Commands called by hooks reference linters by absolute `/nix/store` path, so the exact same pinned tools can run locally and in CI. Not only does `hk` provide first-class local CI, `hk-nix` syncs them with `nix flake check` anywhere.

## How it works

`hk` is configured with [Pkl](https://pkl-lang.org) (via the hk.pkl file). `hk-nix` generates
that hk.pkl file from a Nix attrset and points its `amends` at hk's `Config.pkl`
schema **from the pinned `jdx/hk` input at an absolute store path**. This means
evaluation is fully offline (no `package://` download) and works inside the
`nix flake check` sandbox. The generated file is symlinked into the repo root
and `hk install` wires up git hooks.

`hk-nix` defaults to using `hk`'s support for [**git 2.54+ config-based hooks**][git-config-hooks].

[git-config-hooks]: https://github.blog/open-source/git/highlights-from-git-2-54/#h-config-based-hooks

## Usage

A Nix flake that adds `hk-nix` as input, imports the `hk-nix` flake module, defines a `pre-commit` hook, adds `hk` and `git` to the devshell, and enables the `hk-nix` shellHook which activates when entering the devshell.

Importing the flake module automatically sets `checks.hk`, so `nix flake check` runs the `pre-commit` hook read-only over all files.


```nix
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

You may want to add the generated symlink to your `.gitignore`:

```gitignore
/hk.pkl
```

### Using builtin linters

hk ships 140+ pre-configured linters and formatters as [builtins](https://hk.jdx.dev/builtins).
`hk-nix` exposes each one as `config.hk-nix.builtins.<name>` — a record that already carries the
builtin's glob patterns and commands and pins the tool from Nixpkgs. Reference a builtin instead of
hand-writing `glob` + `check`/`fix`:

```nix
perSystem =
  { config, pkgs, lib, ... }:
  # `builtins` is an ordinary name in Nix, not a keyword, so it can be shadowed;
  # nothing here calls a global builtin. Drop this line to keep the global.
  let inherit (config.hk-nix) builtins; in
  {
    hk-nix.settings.hooks."pre-commit" = {
      fix = true;
      stash = "git";
      steps = {
        nix_fmt.builtin = builtins.nix_fmt;
        gitleaks.builtin = builtins.gitleaks;
        prettier.builtin = builtins.prettier;
      };
    };

    devShells.default = pkgs.mkShell {
      packages = [ config.hk-nix.package pkgs.git ];
      shellHook = config.hk-nix.shellHook;
    };
  };
```

Each builtin is pinned by absolute `/nix/store` path (injected via the step's `PATH`), so the same
tool runs in the dev shell and in `nix flake check` — no reliance on ambient `PATH`. Builtin names
use the hk identifier (underscores), e.g. `nix_fmt`, `cargo_clippy`, `byte_order_marker`.

#### Overriding a builtin

Overrides fall on two independent axes:

- **The tool** — repin the package (or its build) with `.override`:

  ```nix
  steps.gitleaks.builtin =
    config.hk-nix.builtins.gitleaks.override { package = pkgs.gitleaks_8_18; };
  ```

- **The hk step** — amend `glob`, `batch`, `depends`, `profiles`, `env`, … with sibling fields on the
  step; every key other than `builtin` is merged into the generated `(Builtins.<name>) { … }` amend:

  ```nix
  steps.gitleaks = {
    builtin = config.hk-nix.builtins.gitleaks;
    glob    = "src/**/*";
    depends = "prettier";
  };
  ```

Both at once:

```nix
steps.gitleaks = {
  builtin = config.hk-nix.builtins.gitleaks.override { package = myGitleaks; };
  glob    = "src/**/*";
};
```

Builtins that run hk itself (e.g. `newlines`, `trailing_whitespace`, `byte_order_marker`) carry
`package = null` and inject no `PATH` — hk is already the runner, so they add nothing to the closure.

## Options (`perSystem.hk-nix`)

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `settings` | attrs | `{ }` | The hk.pkl top-level (e.g. `{ hooks = { ... }; }`). |
| `package` | package | overlay's `hk` | The hk binary. Override with `pkgs.hk` (nixpkgs) or another build. |
| `src` | path | `self` | Project root copied into the check derivation. |
| `checkHook` | str | `"pre-commit"` | Hook run (read-only) by `checks.hk`. |
| `shellHook` | str | *(read-only)* | Symlinks hk.pkl and installs the git hooks. |
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
- Builtin linters are available as `config.hk-nix.builtins.<name>` (see
  [Using builtin linters](#using-builtin-linters)); the tool is pinned from
  Nixpkgs and injected via the step's `PATH`. You can still declare steps
  explicitly (`glob` + `check`/`fix` shell strings) for tools without a builtin.
- `check`/`fix` are shell strings; the `Command { argv = ... }` form is not yet
  rendered.
- Config is injected by symlinking hk.pkl; the `HK_FILE` env-var mechanism is
  not supported yet. Supporting it would be neat, since then it can live in a Nix store derivation, rather than a .gitignore'd working-tree file.
- Per-repo install only (no `hk install --global`).
