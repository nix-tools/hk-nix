# hk-nix's own dev shell. The `hk-nix.*` options and `checks.hk` output are
# activated by flake-module.nix (which self-imports the consumer module), so
# here we just consume `config.hk-nix`. Entering the shell installs the git
# hooks; `nix flake check` runs the same checks.
{
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
