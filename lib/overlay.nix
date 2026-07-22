# The overlay that lives inside hk-nix, exposed as `flake.overlays.default`: it
# defines `pkgs.hk`, built from the pinned jdx/hk flake input so the binary
# matches the Config.pkl schema hk-nix amends. Consumers who prefer nixpkgs' hk
# simply don't apply this overlay and set `hk-nix.package = pkgs.hk` instead.
{ inputs, ... }:

{
  flake.overlays.default = final: _prev: {
    # Build from the pinned input, but skip hk's own test suite: one branch-detection
    # test (test_get_current_branch_attached_and_detached) fails in the nix sandbox,
    # and we only need the binary, not upstream's test results.
    hk = (final.callPackage "${inputs.hk}/default.nix" { }).overrideAttrs (_: {
      doCheck = false;
    });
  };
}
