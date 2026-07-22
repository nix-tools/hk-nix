# The consumer-facing flake-parts module, exported as
# `hk-nix.flakeModules.default`. It is closed over hk-nix's own `hk` input (and
# its `flake.lib.mkHkCheck` / `flake.overlays.default`) so a consumer gets the
# pinned schema + default binary regardless of their inputs.
#
# Import it and declare hooks:
#
#   imports = [ inputs.hk-nix.flakeModules.default ];
#   perSystem = { config, pkgs, lib, ... }: {
#     hk-nix.settings.hooks."pre-commit".steps.nixfmt = {
#       glob = "*.nix";
#       fix  = "${lib.getExe pkgs.nixfmt} {{files}}";
#     };
#     devShells.default = pkgs.mkShell { inherit (config.hk-nix) shellHook; };
#   };
#
# hk-nix also dogfoods this module on itself: `imports = [ consumerModule ]`
# below activates the `hk-nix.*` options and `checks.hk` output in hk-nix's own
# flake, so hooks.nix can declare hk-nix's hooks and `nix flake check` runs them.
{ config, inputs, ... }:

let
  hk = inputs.hk;
  inherit (config.flake.lib) mkHkCheck mkHkBuiltins;
  overlay = config.flake.overlays.default;

  consumerModule =
    { lib, self, ... }:
    {
      perSystem =
        { config, pkgs, ... }:
        let
          cfg = config.hk-nix;
          result = mkHkCheck {
            inherit pkgs;
            inherit (cfg)
              package
              src
              settings
              checkHook
              ;
            hkSrc = hk;
          };
        in
        {
          options.hk-nix = {
            package = lib.mkOption {
              type = lib.types.package;
              default = (overlay pkgs pkgs).hk;
              defaultText = lib.literalMD "hk from hk-nix's overlay (pinned `jdx/hk` input)";
              description = ''
                The hk package to use. Defaults to hk-nix's own overlay build of the
                pinned jdx/hk input. Override with `pkgs.hk` (nixpkgs) or any other
                build to choose a different source.
              '';
            };

            src = lib.mkOption {
              type = lib.types.path;
              default = self;
              defaultText = lib.literalExpression "self";
              description = "Project root copied into the hk check derivation.";
            };

            settings = lib.mkOption {
              type = lib.types.attrs;
              default = { };
              example = lib.literalExpression ''
                { hooks."pre-commit".steps.nixfmt = { glob = "*.nix"; fix = "nixfmt {{files}}"; }; }
              '';
              description = ''
                The hk.pkl top-level as a Nix attrset. Commands should reference
                linters by absolute store path (e.g. `''${lib.getExe pkgs.foo}`) so
                the same pinned tools run in the dev shell and in CI.
              '';
            };

            checkHook = lib.mkOption {
              type = lib.types.str;
              default = "pre-commit";
              description = "Hook run (read-only, over all files) by the `checks.hk` derivation.";
            };

            builtins = lib.mkOption {
              type = lib.types.lazyAttrsOf lib.types.raw;
              readOnly = true;
              description = ''
                hk's builtin linters as overridable records, keyed by hk identifier
                (underscored, e.g. `nix_fmt`). Use as
                `steps.<step>.builtin = config.hk-nix.builtins.<name>;` and repin the
                tool with `.override { package = ...; }`. The package resolves lazily,
                so unreferenced builtins pull nothing into the closure.
              '';
            };

            check = lib.mkOption {
              type = lib.types.package;
              readOnly = true;
              description = "The nix flake check derivation (`hk run <checkHook> --all --check`).";
            };

            shellHook = lib.mkOption {
              type = lib.types.str;
              readOnly = true;
              description = "Shell hook that symlinks hk.pkl and installs the git hooks.";
            };
          };

          config = {
            hk-nix.builtins = mkHkBuiltins {
              inherit pkgs;
              hkSrc = hk;
            };
            hk-nix.check = result;
            hk-nix.shellHook = result.shellHook;
            checks.hk = result;
          };
        };
    };
in
{
  flake.flakeModules.default = consumerModule;

  # Dogfood: hk-nix manages hk-nix's own hooks via the same module it exports.
  imports = [ consumerModule ];
}
