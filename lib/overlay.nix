# The overlay that lives inside hk-nix, exposed as `flake.overlays.default`: it
# defines `pkgs.hk`, built from the pinned jdx/hk flake input so the binary
# matches the Config.pkl schema hk-nix amends. Consumers who prefer nixpkgs' hk
# simply don't apply this overlay and set `hk-nix.package = pkgs.hk` instead.
{ inputs, ... }:

{
  flake.overlays.default = final: _prev: {
    hk =
      let
        # Build from the pinned input, but skip hk's own test suite: one branch-detection
        # test (test_get_current_branch_attached_and_detached) fails in the nix sandbox,
        # and we only need the binary, not upstream's test results.
        base = (final.callPackage "${inputs.hk}/default.nix" { }).overrideAttrs (_: {
          doCheck = false;
        });
      in
      base.overrideAttrs (prev: {
        passthru = (prev.passthru or { }) // {
          # Given the generated (store-path) hk.pkl, bake it in as HK_FILE so hk reads its
          # config from the store and needs no working-tree hk.pkl. hk-nix keys off the
          # presence of this attribute: when the package carries it (i.e. this overlay is
          # active) hk-nix drops the hk.pkl symlink; nixpkgs' hk lacks it, so hk-nix cannot
          # assume a baked HK_FILE and keeps symlinking. See run.nix.
          hkNixWithConfig =
            configFile:
            final.symlinkJoin {
              name = "hk-hk-nix";
              paths = [ base ];
              nativeBuildInputs = [ final.makeWrapper ];
              postBuild = "wrapProgram $out/bin/hk --set-default HK_FILE ${configFile}";
            };
        };
      });
  };
}
