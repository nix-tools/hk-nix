# consumer-facing flake-parts module `hk-nix.flakeModules.default`. It is closed over hk-nix's
# `flake.lib.mkHkCheck`, so the hk renderer and the Config.pkl schema come from the same binary.
#
# ```nix
# imports = [ inputs.hk-nix.flakeModules.default ];
# perSystem = { config, pkgs, lib, ... }: {
#   hk-nix.settings.hooks."pre-commit".steps.nixfmt = {
#     glob = "*.nix";
#     fix  = "${lib.getExe pkgs.nixfmt} {{files}}";
#   };
#   devShells.default = pkgs.mkShell {
#     packages = [ config.hk-nix.hk ];
#     inherit (config.hk-nix) shellHook;
#   };
# };
# ```
{ config, ... }:

let
  inherit (config.flake.lib) mkHkCheck mkHkBuiltins;

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
              hkSrc
              ;
          };
        in
        {
          options.hk-nix = {
            package = lib.mkOption {
              type = lib.types.package;
              default = pkgs.hk;
              defaultText = lib.literalMD "`pkgs.hk` (nixpkgs)";
              description = ''
                The hk package to use, and the source of the Pkl schema hk-nix amends
                (see `hkSrc`). Defaults to nixpkgs' hk; to use another build, either
                set this or define `pkgs.hk` in an overlay of your own.
              '';
            };

            hkSrc = lib.mkOption {
              type = lib.types.path;
              default = cfg.package.src;
              defaultText = lib.literalExpression "package.src";
              description = ''
                The hk source tree supplying the Pkl schema (Config.pkl) and the
                builtin definitions. Defaults to `package`'s own source, so schema and
                binary cannot drift apart; set it only when `package` has no `src`
                (e.g. a prebuilt release binary).
              '';
            };

            hk = lib.mkOption {
              type = lib.types.package;
              readOnly = true;
              description = ''
                The hk to put on the dev shell PATH: `package` with the generated
                hk.pkl baked in as HK_FILE, so hk reads its config from the store and
                nothing is written into the working tree. Equivalent to
                `pkgs.hk.withConfig config.hk-nix.configFile` under hk-nix's overlay,
                but computed without it, so the module works either way.
              '';
            };

            configFile = lib.mkOption {
              type = lib.types.package;
              readOnly = true;
              description = ''
                The generated hk.pkl, rendered from `settings` into the store. Pass it
                to `pkgs.hk.withConfig` to build the same hk this module exposes as
                `hk`, e.g. when placing it in a system configuration rather than a
                dev shell.
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
              description = "Shell hook that installs the git hooks.";
            };
          };

          config = {
            hk-nix.builtins = mkHkBuiltins {
              inherit pkgs;
              inherit (cfg) hkSrc;
            };
            hk-nix.check = result;
            hk-nix.hk = result.runtimeHk;
            hk-nix.configFile = result.configFile;
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
