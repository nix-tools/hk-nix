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

hk-nix generates that hk.pkl file from a Nix attrset.

This means evaluation is fully offline (no `package://` download) and works inside the `nix flake check` sandbox.

The generated config is either dumped into a symlinked hk.pkl file, or is baked into the hk binary
as `HK_FILE`, so it lives entirely in the Nix store: no hk.pkl in your working tree, and nothing to
`.gitignore`.

`hk install` wires up the git hooks, and hk-nix then rewrites each installed hook to name that
binary by absolute store path. The hooks therefore fire from anywhere — an editor, a GUI client, a
plain terminal — and do not depend on the dev shell being active.

hk-nix defaults to using hk's support for [**git 2.54+ config-based hooks**][git-config-hooks].

[git-config-hooks]: https://github.blog/open-source/git/highlights-from-git-2-54/#h-config-based-hooks

## Example usage

A Nix flake that adds hk-nix as input, imports the hk-nix flake module, defines a `pre-commit` hook
that runs [treefmt](https://github.com/numtide/treefmt-nix), adds `hk` and `git` to the devshell,
and enables the hk-nix shellHook which activates when entering the devshell.

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

### Using builtin linters

hk ships 140+ pre-configured linters and formatters as [builtins](https://hk.jdx.dev/builtins).
hk-nix exposes each one as `config.hk-nix.builtins.<name>` — a record that already carries the
builtin's glob patterns and commands and pins the tool from Nixpkgs. Reference a builtin instead of
hand-writing `glob` + `check`/`fix`:

> ***Note:** Not all builtin hooks are [vendored via nixpkgs][vendored-hooks]; some may fail unless you vendor them.*

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

You can override a builtin package via `.override { package = ...; }`:

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
| `package` | package | `lib.mkHkBin { inherit pkgs; }` | The hk build to wrap, and the source of the amended Pkl schema. |
| `hkSrc` | path | `package.src` | hk source tree supplying `Config.pkl` and the builtin definitions. |
| `src` | path | `self` | Project root copied into the check derivation. |
| `checkHook` | str | `"pre-commit"` | Hook run (read-only) by `checks.hk`. |
| `hk` | package | *(read-only)* | `package` with the generated config baked in as `HK_FILE`. Put this on PATH. |
| `configFile` | package | *(read-only)* | The generated hk.pkl in the store. |
| `builtins` | attrs | *(read-only)* | hk's builtins as overridable records, keyed by hk identifier. |
| `shellHook` | str | *(read-only)* | Installs the git hooks. |
| `check` | package | *(read-only)* | The `checks.hk` derivation. |

## `HK_FILE`

hk normally uses a file called hk.pkl, which hk-nix can generate from the `settings` options.

The location of this file defaults to the project root, but can be tweaked with the `HK_FILE` environment variable.

hk-nix can bake this environment variable into the `hk` binary, so that you don't need to gitignore it.

An hk on your `PATH` can be doing one of two jobs: running a project's hooks automatically, or being
the hk CLI invoked by a user. hk-nix makes it possible to reference both `hk` with/without baked-in
configs, since accessing a plain CLI can be useful. So `pkgs.hk` is the plain CLI.

If you apply `hk-nix.overlays.default`, then `pkgs.hk` is enriched with a `.withConfig` function
that takes a hk.pkl and returns an `hk` binary with that config baked in:

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

The two then coexist for different purposes:

```nix
environment.systemPackages = [ pkgs.hk ];                              # the CLI
devShells.default.packages = [ (pkgs.hk.withConfig ./hk.pkl) ];        # a hook runner
```

As a convenience, `config.hk-nix.hk` is equivalent to

```nix
pkgs.hk.withConfig config.hk-nix.configFile
```

### Changing the hk binary

`hk-nix.package` defaults to the jdx/hk release binary (see [Prebuilt release
binaries](#prebuilt-release-binaries)), and `hk-nix.hkSrc` defaults to that package's own `src`.

nixpkgs' `pkgs.hk` is not the default until nixpkgs ships hk 2.5 or later: the Builtins.pkl that
hk-nix generates imports each builtin with an import expression, which older hk cannot evaluate.
Any hk you set below has to be 2.5 or later for the same reason.

To run hk built from its own repository, add it as an input and use the overlay it ships:

```nix
inputs.hk.url = "github:jdx/hk";
inputs.hk.inputs.nixpkgs.follows = "nixpkgs";

perSystem =
  { system, ... }:
  {
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      overlays = [
        inputs.hk.overlay
        inputs.hk-nix.overlays.default
      ];
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

#### Prebuilt release binaries

Installing hk from nixpkgs provides a binary cache for somewhat recent versions.

However, hk often releases new versions, and to use the latest, you may miss the binary cache.

You can use [the GitHub releases of jdx/hk][hk-release] as a more cutting-edge binary cache.

[hk-release]: https://github.com/jdx/hk/releases

For this, hk-nix exposes a helper function `flake.lib.mkHkBin` for producing precompiled derivations,
and it is what `hk-nix.package` defaults to:

```nix
perSystem =
  { pkgs, ... }:
  {
    hk-nix.package = inputs.hk-nix.lib.mkHkBin { inherit pkgs; };
  };
```

Its `src` is the matching source tarball rather than the binary archive, so `hkSrc` still finds the
Pkl schema and the builtins, at the version the binary speaks.

To use a release hk-nix has not pinned, pass your own `release`:

```nix
inputs.hk-nix.lib.mkHkBin {
  inherit pkgs;
  release = {
    version = "2.7.0";
    srcHash = "sha256-...";
    assets.x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      hash = "sha256-...";
    };
  };
}
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
  downside is that garbage-collecting that path breaks the hook until you re-enter the dev shell.
- Referencing a builtin reads the builtin list out of `hkSrc` during evaluation, which is an
  import-from-derivation (IFD) when `hkSrc` is a fetched source such as nixpkgs' `pkgs.hk.src`.
  Declaring steps explicitly needs no IFDs.
- `check`/`fix` are shell strings; the `Command { argv = ... }` form is not yet rendered.
