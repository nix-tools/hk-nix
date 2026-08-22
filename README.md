# hk-nix

Manage your [hk](https://github.com/jdx/hk) git hooks with Nix.

With hk-nix you...

- install `hk` with Nix,
- declare your hooks in Nix (rather than Pkl),
- pin linter and checker programs with Nix, and
- always enable hooks by installing them via a devshell.

To get started, read [Git config-based hooks with hk-nix][getting-started].

[getting-started]: https://simonshine.dk/articles/git-config-based-hooks-with-hk-nix/

## How it works

hk is configured with [Pkl](https://pkl-lang.org) (via the hk.pkl file).

hk-nix generates that hk.pkl file from a Nix attrset and points its `amends` at hk's `Config.pkl`
schema, taken from the hk package's own source at an absolute `/nix/store` path.

This means evaluation is fully offline (no `package://` download) and works inside the `nix flake check` sandbox.

It also means the schema always comes from the same hk that runs it.

The generated config is baked into a copy of the hk binary as `HK_FILE`, so it lives entirely in the
Nix store: no hk.pkl in your working tree, and nothing to `.gitignore`.

`hk install` wires up the git hooks, and hk-nix then rewrites each installed hook to name that
binary by absolute store path. The hooks therefore fire from anywhere — an editor, a GUI client, a
plain terminal — and do not depend on the dev shell being active.

hk-nix defaults to using hk's support for [**git 2.54+ config-based hooks**][git-config-hooks].

[git-config-hooks]: https://github.blog/open-source/git/highlights-from-git-2-54/#h-config-based-hooks

## Example usage

A Nix flake that adds hk-nix as input, imports the hk-nix flake module, defines a `pre-commit` hook that runs [treefmt](https://github.com/numtide/treefmt-nix), adds `hk` and `git` to the devshell, and enables the hk-nix shellHook which activates when entering the devshell.

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
            packages = [ config.hk-nix.hk pkgs.git ];
            shellHook = config.hk-nix.shellHook;
          };
        };
    };
}
```

No overlay is needed for this, and nothing is written into your working tree.

### Using builtin linters

hk ships 140+ pre-configured linters and formatters as [builtins](https://hk.jdx.dev/builtins).
hk-nix exposes each one as `config.hk-nix.builtins.<name>` — a record that already carries the
builtin's glob patterns and commands and pins the tool from Nixpkgs. Reference a builtin instead of
hand-writing `glob` + `check`/`fix`:

> ***Note:** Not all builtin hooks are [vendored via nixpkgs][vendored-hooks]; some may fail.*

[vendored-hooks]: https://github.com/nix-tools/hk-nix/issues/1

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
      packages = [ config.hk-nix.hk pkgs.git ];
      shellHook = config.hk-nix.shellHook;
    };
  };
```

Each builtin is pinned by absolute `/nix/store` path (injected via the step's `PATH`), so the same
tool runs in the dev shell and in `nix flake check` — no reliance on ambient `PATH`. Builtin names
use the hk identifier (underscores), e.g. `nix_fmt`, `cargo_clippy`, `byte_order_marker`.

#### Overriding a builtin

You can override the builtin package via `.override { package = ...; }`:

```nix
steps.gitleaks.builtin =
  config.hk-nix.builtins.gitleaks.override { package = pkgs.gitleaks_8_18; };
```

You can also override the properties of a step via `glob`, `batch`, `depends`, `profiles`, `env`, ...:

```nix
steps.betterleaks = {
  builtin = config.hk-nix.builtins.betterleaks;
  glob    = "src/**/*";
  depends = "prettier";
};
```

You can also override the package and properties of a step:

```nix
steps.gitleaks = {
  builtin = config.hk-nix.builtins.gitleaks.override { package = myGitleaks; };
  glob    = "src/**/*";
};
```

Some builtins are implemented inside hk itself and pin no package; they run `hk` directly, which is
on the step's `PATH` for that reason.

## Options (`perSystem.hk-nix`)

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `settings` | attrs | `{ }` | The hk.pkl top-level (e.g. `{ hooks = { ... }; }`). |
| `package` | package | `pkgs.hk` (nixpkgs) | The hk build to wrap, and the source of the amended Pkl schema. |
| `hkSrc` | path | `package.src` | hk source tree supplying `Config.pkl` and the builtin definitions. |
| `src` | path | `self` | Project root copied into the check derivation. |
| `checkHook` | str | `"pre-commit"` | Hook run (read-only) by `checks.hk`. |
| `hk` | package | *(read-only)* | `package` with the generated config baked in as `HK_FILE`. Put this on PATH. |
| `configFile` | package | *(read-only)* | The generated hk.pkl in the store. |
| `builtins` | attrs | *(read-only)* | hk's builtins as overridable records, keyed by hk identifier. |
| `shellHook` | str | *(read-only)* | Installs the git hooks. |
| `check` | package | *(read-only)* | The `checks.hk` derivation. |

## Where hk carries its config

An hk on your `PATH` can be doing one of two jobs: running one project's hooks, or being the hk CLI.
Only the first wants a config baked in. hk-nix keeps them separate rather than guessing, so `pkgs.hk`
is always the plain CLI and a config-carrying hk is something you ask for.

Inside the flake module, `config.hk-nix.hk` is that ask, and it needs no overlay.

Elsewhere — a NixOS or home-manager configuration, or no flakes at all — apply `overlays.default`,
which adds one thing to `pkgs.hk`: a `withConfig` function taking an hk.pkl and returning an hk with
it baked in.

```nix
perSystem =
  { system, ... }:
  {
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      overlays = [ inputs.hk-nix.overlays.default ];
    };
  };
```

The two then coexist, each spelling saying which job it is for:

```nix
environment.systemPackages = [ pkgs.hk ];                              # the CLI
devShells.default.packages = [ (pkgs.hk.withConfig ./hk.pkl) ];        # a hook runner
```

To pass the config the flake module generated rather than a handwritten file, use
`pkgs.hk.withConfig config.hk-nix.configFile`, which is exactly what `config.hk-nix.hk` is.

The overlay picks no build of hk and only ever touches `passthru`, so an overlaid `pkgs.hk` is the
same derivation, and the same binary cache hit, as before.

### Changing the hk binary

`hk-nix.package` defaults to nixpkgs' `pkgs.hk`, and `hk-nix.hkSrc` defaults to that package's own
`src`, so hk-nix pins no hk of its own.

To run hk built from its own repository, add it as an input and use the overlay it ships:

```nix
inputs.hk.url = "github:jdx/hk";
inputs.hk.inputs.nixpkgs.follows = "nixpkgs";

perSystem =
  { system, ... }:
  {
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      overlays = [ inputs.hk.overlay inputs.hk-nix.overlays.default ];
    };
  };
```

Order matters: hk-nix's overlay layers `withConfig` onto whatever `pkgs.hk` it finds.

You can also set `hk-nix.package` directly, e.g. to `inputs.hk.packages.${system}.default`.

Either way `hkSrc` follows the package, so a newer hk brings its own schema and builtins along.

hk's own build runs its test suite, which can fail in the Nix sandbox. You can skip it by layering
one more overlay in between:

```nix
overlays = [
  inputs.hk.overlay
  (_: prev: { hk = prev.hk.overrideAttrs (_: { doCheck = false; }); })
  inputs.hk-nix.overlays.default
];
```

## Without flakes

The overlay is plain Nix, so it needs no flake evaluation:

```nix
let
  hk-nix = import (fetchTarball "https://github.com/nix-tools/hk-nix/archive/main.tar.gz");
  pkgs = import <nixpkgs> { overlays = [ hk-nix.overlays.default ]; };
in
pkgs.mkShell {
  packages = [ (pkgs.hk.withConfig ./hk.pkl) ];
}
```

Declaring hooks as a Nix attrset is a flake module feature, so here you write hk.pkl by hand and
hand it to `withConfig`. What you get is the baked `HK_FILE`, and with it a config that lives in the
store rather than the working tree.

## Limitations

- The installed hook names hk by absolute store path, so it survives having no `hk` on `PATH`. The
  cost is that garbage-collecting that path breaks the hook until you re-enter the dev shell, which
  rewrites it. It fails loudly when this happens.
- Builtin linters are available as `config.hk-nix.builtins.<name>` (see
  [Using builtin linters](#using-builtin-linters)); the tool is pinned from
  Nixpkgs and injected via the step's `PATH`. You can still declare steps
  explicitly (`glob` + `check`/`fix` shell strings) for tools without a builtin.
- Referencing a builtin reads the builtin list out of `hkSrc` during evaluation,
  which is an import-from-derivation when `hkSrc` is a fetched source such as
  nixpkgs' `pkgs.hk.src`. Declaring steps explicitly needs no IFD.
- `check`/`fix` are shell strings; the `Command { argv = ... }` form is not yet
  rendered.
- Per-repo install only (no `hk install --global`). hk-nix passes `--force-local`, so a global hk
  install does not stop it from managing this repo's hooks.
