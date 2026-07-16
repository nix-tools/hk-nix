# Export hk-nix's public surface: the consumer flake-parts module, the overlay
# that defines `pkgs.hk`, and the pure Nix -> Pkl renderer.
{ inputs, ... }:

{
  flake.flakeModules.default = import ../lib/flake-module.nix { inherit (inputs) hk; };

  flake.overlays.default = import ../lib/overlay.nix { inherit (inputs) hk; };

  flake.lib.renderHkPkl =
    (import ../lib/render-pkl.nix { inherit (inputs.nixpkgs) lib; }).renderHkPkl;
}
