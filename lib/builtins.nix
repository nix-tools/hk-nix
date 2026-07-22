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

      # Builtins whose command runs hk itself (`hk util ...`, `hk test`): the tool
      # is hk, already the runner, so no package is pinned and no PATH is injected.
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
        "hk_test"
        "mixed_line_ending"
        "newlines"
        "no_commit_to_branch"
        "python_check_ast"
        "python_debug_statements"
        "trailing_whitespace"
      ];

      # Curated packages for builtins the `pkgs.<name>` fallback below can't resolve
      # on its own: a different attribute, a package-set member, or a name that
      # collides with an unrelated package. Grows incrementally; see the tracking
      # issue for the builtins still lacking a default.
      exceptions = {
        buf_format = pkgs.buf;
        buf_lint = pkgs.buf;
        buildifier_format = pkgs.buildifier;
        buildifier_lint = pkgs.buildifier;
        bundle_audit = pkgs.bundler-audit;
        cargo_check = pkgs.cargo;
        cargo_clippy = pkgs.clippy;
        cargo_fmt = pkgs.rustfmt;
        clang_format = pkgs.clang-tools;
        cocogitto_commit_msg = pkgs.cocogitto;
        cpp_lint = pkgs.cpplint;
        deno_check = pkgs.deno;
        erb = pkgs.ruby;
        err_check = pkgs.errcheck;
        flake8 = pkgs.python3Packages.flake8;
        ghalint_action = pkgs.ghalint;
        ghalint_workflow = pkgs.ghalint;
        go_fmt = pkgs.go;
        go_fumpt = pkgs.gofumpt;
        go_imports = pkgs.gotools;
        go_lines = pkgs.golines;
        go_sec = pkgs.gosec;
        go_vet = pkgs.go;
        go_vuln_check = pkgs.govulncheck;
        gomod_tidy = pkgs.go;
        harper_commit_message = pkgs.harper;
        just_format = pkgs.just;
        luacheck = pkgs.luaPackages.luacheck;
        markdown_lint = pkgs.markdownlint-cli;
        mix_compile = pkgs.elixir;
        mix_fmt = pkgs.elixir;
        mix_test = pkgs.elixir;
        nix_fmt = pkgs.nixfmt;
        nixpkgs_format = pkgs.nixpkgs-fmt;
        ox_lint = pkgs.oxlint;
        php_cs = pkgs.phpPackages.php-codesniffer;
        pinact_update = pkgs.pinact;
        pkl_format = pkgs.pkl;
        rubocop_server = pkgs.rubocop;
        ruff_format = pkgs.ruff;
        sql_fluff = pkgs.sqlfluff;
        standard_rb = pkgs.rubyPackages.standard;
        staticcheck = pkgs.go-tools;
        taplo_format = pkgs.taplo;
        tf_lint = pkgs.tflint;
        tofu = pkgs.opentofu;
        tombi_format = pkgs.tombi;
        tsc = pkgs.typescript;
        vacuum = pkgs.vacuum-go;
        xmllint = pkgs.libxml2.bin;
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
