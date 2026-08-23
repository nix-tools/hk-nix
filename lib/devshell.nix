{
  perSystem =
    { config, pkgs, ... }:
    {
      devShells.default = pkgs.mkShell {
        packages = [
          config.hk-nix.hk
          pkgs.git
          pkgs.just
          pkgs.nixfmt
          pkgs.deadnix
        ];
        inherit (config.hk-nix) shellHook;
      };
    };
}
