# The builtins registry and the settings desugaring that make hk's builtins
# first-class, exposed as `flake.lib.mkHkBuiltins` and `flake.lib.desugarBuiltins`.
#
# `mkHkBuiltins { pkgs, hkSrc }` returns a lazy attrset keyed by hk builtin
# identifier (underscored, e.g. `nix_fmt`). Each entry is an overridable record
#
#     { name = "gitleaks"; package = <pkgs.gitleaks>; override = f; }
#
# where `package` is a Nixpkgs default (resolved lazily — unused builtins never
# force their package) and `.override { package = ...; }` repins the tool. The set
# is surfaced to consumers as the perSystem option `config.hk-nix.builtins.<name>`.
#
# `desugarBuiltins settings` rewrites any step carrying a `builtin` record into the
# renderer's amends escape hatch (see render-pkl.nix):
#
#     steps.gitleaks = { builtin = <record>; glob = "src/**"; }
#   becomes
#     { __amends = "(Builtins.gitleaks)"; glob = "src/**"; env.PATH = "${package}/bin:${basePath}"; }
{ ... }:

{
  config.flake.lib.mkHkBuiltins =
    {
      pkgs,
      hkSrc,
    }:
    let
      lib = pkgs.lib;
      dash = lib.replaceStrings [ "_" ] [ "-" ];

      # Builtin identifiers (underscored), read from the pinned store input.
      names = map (n: lib.replaceStrings [ "-" ] [ "_" ] (lib.removeSuffix ".pkl" n)) (
        lib.filter (n: lib.hasSuffix ".pkl" n) (lib.attrNames (builtins.readDir "${hkSrc}/pkl/builtins"))
      );

      # Builtins whose command runs `hk util ...`: the tool is hk itself, already
      # the runner, so no package is pinned and no PATH is injected.
      hkNativeBuiltins = [
        "byte_order_marker"
        "check_added_large_files"
        "check_byte_order_marker"
        "check_case_conflict"
        "check_conventional_commit"
        "check_executables_have_shebangs"
        "check_merge_conflict"
        "check_symlinks"
        "detect_private_key"
        "fix_byte_order_marker"
        "fix_smart_quotes"
        "mixed_line_ending"
        "newlines"
        "no_commit_to_branch"
        "python_check_ast"
        "python_debug_statements"
        "trailing_whitespace"
      ];

      # Curated overrides where the builtin identifier does not match a Nixpkgs
      # attribute (after the `_`->`-` fallback below). Grows incrementally.
      exceptions = {
        nix_fmt = pkgs.nixfmt;
      };

      # Default package for a builtin: null for hk-native ones; a curated exception;
      # otherwise `pkgs.<name>` or `pkgs.<name-with-dashes>`; else a lazy, helpful
      # throw. Only forced when a declared builtin step reads `.package`.
      defaultPackage =
        name:
        if lib.elem name hkNativeBuiltins then
          null
        else if exceptions ? ${name} then
          exceptions.${name}
        else
          let
            hit = lib.findFirst (a: pkgs ? ${a}) null [
              name
              (dash name)
            ];
          in
          if hit != null then
            pkgs.${hit}
          else
            throw ''
              hk-nix: no default Nixpkgs package for builtin '${name}'. Pin it explicitly, e.g.
                steps.${name}.builtin = config.hk-nix.builtins.${name}.override { package = pkgs.<pkg>; };'';

      mkBuiltin =
        name:
        lib.makeOverridable ({ package }: { inherit name package; }) {
          package = defaultPackage name;
        };
    in
    lib.genAttrs names mkBuiltin;

  # Rewrite builtin-bearing steps under hooks.<hook>.steps into amends markers.
  # `basePath` is a pinned `sh`+coreutils bin path appended after the tool, so the
  # step's PATH is fully store-pinned yet hk can still find a shell to run the
  # command. Pure `builtins.*` otherwise (no pkgs/lib), so it is cheap.
  config.flake.lib.desugarBuiltins =
    { basePath }:
    let
      desugarStep =
        step:
        if !(builtins.isAttrs step) || !(step ? builtin) then
          step
        else
          let
            b = step.builtin;
            overrides = removeAttrs step [ "builtin" ];
            userEnv = overrides.env or { };
            # Pin the tool by store path (plus the base for `sh`); a null package
            # (hk-native builtin) injects no PATH — hk is already the runner. An
            # explicit env is kept, with the pin taking precedence.
            env = if b.package == null then userEnv else userEnv // { PATH = "${b.package}/bin:${basePath}"; };
            base = removeAttrs overrides [ "env" ];
          in
          (if env == { } then base else base // { inherit env; })
          // {
            __amends = "(Builtins.${b.name})";
          };

      desugarHook =
        hook:
        if !(builtins.isAttrs hook) || !(hook ? steps) then
          hook
        else
          hook // { steps = builtins.mapAttrs (_: desugarStep) hook.steps; };
    in
    settings:
    if !(builtins.isAttrs settings) || !(settings ? hooks) then
      settings
    else
      settings // { hooks = builtins.mapAttrs (_: desugarHook) settings.hooks; };
}
