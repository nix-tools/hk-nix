# The consumer-facing flake-parts module, exported as
# `hk-nix.flakeModules.default`. It is closed over hk-nix's own `hk` input so a
# consumer gets the pinned schema + default binary regardless of their inputs.
#
# Import it and declare hooks:
#
#   imports = [ inputs.hk-nix.flakeModules.default ];
#   perSystem = { config, pkgs, lib, ... }: {
#     hk-nix.settings.hooks."pre-commit".steps.nixfmt = {
#       glob = "*.nix";
#       fix  = "${lib.getExe pkgs.nixfmt-rfc-style} {{files}}";
#     };
#     devShells.default = pkgs.mkShell { inherit (config.hk-nix) shellHook; };
#   };
{ hk }:

{ lib, self, ... }:

let
  overlay = import ./overlay.nix { inherit hk; };
  run = import ./run.nix;
in
{
  perSystem =
    { config, pkgs, ... }:
    let
      cfg = config.hk-nix;
      result = run {
        inherit pkgs;
        inherit (cfg)
          package
          src
          settings
          checkHook
          ;
        schemaPath = "${hk}/pkl/Config.pkl";
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
        hk-nix.check = result;
        hk-nix.shellHook = result.shellHook;
        checks.hk = result;
      };
    };
}
