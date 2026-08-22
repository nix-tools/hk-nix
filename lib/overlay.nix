# Re-exports the wrapper from _wrapper.nix into the flake outputs. The definitions
# live in plain Nix so non-flake consumers can reach them through the root
# default.nix; this module is only the flake-facing spelling of the same two values.
let
  wrapper = import ./_wrapper.nix;
in
{
  flake.lib.withHkConfig = wrapper.withHkConfig;
  flake.overlays.default = wrapper.overlay;
}
