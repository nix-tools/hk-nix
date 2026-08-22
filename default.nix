# Entry point for consumers not using flakes. It exposes only the overlay and the
# function behind it, which is all that works without flake-parts: the Nix-attrset
# config and the generated hk.pkl come from the flake module, so a non-flake consumer
# writes hk.pkl by hand and passes it to `withConfig`.
#
#   let
#     hk-nix = import (fetchTarball "https://github.com/nix-tools/hk-nix/archive/main.tar.gz");
#     pkgs = import <nixpkgs> { overlays = [ hk-nix.overlays.default ]; };
#   in pkgs.mkShell {
#     packages = [ (pkgs.hk.withConfig ./hk.pkl) ];
#   }
#
# Deliberately not flake-compat: the overlay is plain Nix, so exposing it needs no
# flake evaluation and no extra dependency.
let
  wrapper = import ./lib/_wrapper.nix;
in
{
  overlays.default = wrapper.overlay;
  lib.withHkConfig = wrapper.withHkConfig;
}
