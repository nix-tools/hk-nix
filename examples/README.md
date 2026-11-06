# Examples

Each file here is a flake-parts module of the shape a project keeps in `nix/hooks.nix`: import the
hk-nix flake module, declare steps, done. Copy one into your own flake and it works.

Two things every example takes for granted:

- **treefmt is configured elsewhere.** Examples read `config.treefmt.build.wrapper` and
  `config.treefmt.settings.formatter.mdformat.command`; the formatter matrix itself belongs in your
  own treefmt-nix module.
- **Tools are named by absolute store path.** The `nix flake check` sandbox runs hooks without the
  dev shell's `PATH`, so a bare `treefmt` or `deadnix` is not found there. `lib.getExe` everywhere
  is what makes the same pinned tool run in the shell and in CI.

Paths, crate names and globs are placeholders. `crates/example`, `chart/example` and
`.betterleaks.toml` are there to make the shape legible, not to be copied as-is.

## Validation

`nix flake check` builds a `checks.example-*` for every file: it evaluates the module, renders the
Pkl, and runs `hk validate` over the result, which fails on a config hk could not load and on a
property hk would silently drop. The hooks are never executed, since between them they name cargo,
go, tofu and helm.

See [lib/examples.nix](../lib/examples.nix) for how that works.
