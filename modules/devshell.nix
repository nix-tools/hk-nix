# hk-nix's own dev shell. Importing hk-nix's consumer module here activates the
# `hk-nix.*` options (set in hooks.nix) and the `checks.hk` output — hk-nix
# managing hk-nix's hooks. Entering the shell installs the git hooks; `nix
# flake check` runs the same checks.
{ inputs, ... }:

{
  imports = [ (import ../lib/flake-module.nix { inherit (inputs) hk; }) ];

  perSystem =
    { config, pkgs, ... }:
    {
      devShells.default = pkgs.mkShell {
        packages = [
          config.hk-nix.package
          pkgs.git
          pkgs.nixfmt
          pkgs.deadnix
        ];
        inherit (config.hk-nix) shellHook;
      };
    };
}
