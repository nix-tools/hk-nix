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
`nix flake check` sandbox. `hk install` wires up the git hooks; hk finds the
generated config either baked into the binary as `HK_FILE` (when hk-nix's
overlay is active — see [Choosing the hk binary](#choosing-the-hk-binary)) or,
failing that, symlinked into the repo root as `hk.pkl`.

`hk-nix` defaults to using `hk`'s support for [**git 2.54+ config-based hooks**][git-config-hooks].

[git-config-hooks]: https://github.blog/open-source/git/highlights-from-git-2-54/#h-config-based-hooks

## Usage

A Nix flake that adds `hk-nix` as input, imports the `hk-nix` flake module, defines a `pre-commit` hook that runs [treefmt](https://github.com/numtide/treefmt-nix), adds `hk` and `git` to the devshell, and enables the `hk-nix` shellHook which activates when entering the devshell.

Importing the flake module automatically sets `checks.hk`, so `nix flake check` runs the `pre-commit` hook read-only over all files.


```nix
{
  inputs = {
    nixpkgs.url = "https://nixos.org/channels/nixpkgs-unstable/nixexprs.tar.xz";
    flake-parts.url = "github:hercules-ci/flake-parts";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    hk-nix.url = "github:nix-tools/hk-nix";
    hk-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ flake-parts, hk-nix, treefmt-nix, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      imports = [ hk-nix.flakeModules.default treefmt-nix.flakeModule ];

      perSystem =
        { config, pkgs, ... }:
        {
          treefmt = {
            projectRootFile = "flake.nix";
            programs.nixfmt.enable = true;
          };

          hk-nix.settings.hooks."pre-commit" = {
            fix = true;
            stash = "git";
            steps.treefmt = {
              glob = "*.nix";
              check = "${config.treefmt.build.wrapper}/bin/treefmt --fail-on-change --no-cache {{files}}";
              fix = "${config.treefmt.build.wrapper}/bin/treefmt --no-cache {{files}}";
            };
          };

          devShells.default = pkgs.mkShell {
            packages = [ config.hk-nix.wrappedPackage pkgs.git ];
            shellHook = config.hk-nix.shellHook;
          };
        };
    };
}
```

Without the overlay, hk-nix symlinks the generated config into the repo root, so add it to your
`.gitignore`:

```gitignore
/hk.pkl
```

With the overlay active, `HK_FILE` is baked into the binary and no `hk.pkl` is written, so this
step is unnecessary.

### Using builtin linters

hk ships 140+ pre-configured linters and formatters as [builtins](https://hk.jdx.dev/builtins).
`hk-nix` exposes each one as `config.hk-nix.builtins.<name>` — a record that already carries the
builtin's glob patterns and commands and pins the tool from Nixpkgs. Reference a builtin instead of
hand-writing `glob` + `check`/`fix`:

```nix
perSystem =
  { config, pkgs, lib, ... }:
  let hk = config.hk-nix.builtins; in
  {
    hk-nix.settings.hooks."pre-commit" = {
      fix = true;
      stash = "git";
      steps = {
        betterleaks.builtin = hk.betterleaks;
        actionlint.builtin = hk.actionlint;
        shellcheck.builtin = hk.shellcheck;
      };
    };

    devShells.default = pkgs.mkShell {
      packages = [ config.hk-nix.wrappedPackage pkgs.git ];
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
| `package` | package | `pkgs.hk` (nixpkgs) | The hk binary. Apply hk-nix's overlay to pin the `jdx/hk` build, or set another build. |
| `wrappedPackage` | package | *(read-only)* | The hk to put on PATH: `package`, wrapped to bake in `HK_FILE` when the overlay is active. |
| `src` | path | `self` | Project root copied into the check derivation. |
| `checkHook` | str | `"pre-commit"` | Hook run (read-only) by `checks.hk`. |
| `shellHook` | str | *(read-only)* | Installs the git hooks (and symlinks hk.pkl unless `HK_FILE` is baked in). |
| `check` | package | *(read-only)* | The `checks.hk` derivation. |

### Choosing the hk binary

`hk-nix.package` defaults to nixpkgs' `pkgs.hk`. hk-nix also ships
`overlays.default`, which redefines `pkgs.hk` built from the pinned `jdx/hk`
input (so the binary matches the Config.pkl schema hk-nix amends). To pin that
build instead of nixpkgs':

```nix
nixpkgs.overlays = [ inputs.hk-nix.overlays.default ];   # pin hk to the jdx/hk input
# hk-nix.package now resolves to that pinned pkgs.hk
```

The overlay's hk carries one extra capability: hk-nix wraps it so the generated
hk.pkl is baked in as `HK_FILE`. Config then lives entirely in the Nix store —
hk reads it from there, no `hk.pkl` is symlinked into the repo, and there is
nothing to `.gitignore`. hk-nix keys off the overlay to know this is safe:
nixpkgs' hk carries no such guarantee, so without the overlay hk-nix falls back
to the symlink. Put `config.hk-nix.wrappedPackage` (not `package`) on PATH so
the baked binary is the one that runs the hooks.

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
- With hk-nix's overlay, config lives entirely in a Nix store derivation via a baked-in `HK_FILE`;
  without it, hk-nix falls back to symlinking a `.gitignore`'d hk.pkl into the working tree.
- Per-repo install only (no `hk install --global`).
