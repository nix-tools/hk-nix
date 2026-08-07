# The overlay that lives inside hk-nix, exposed as `flake.overlays.default`: it
# takes whatever `pkgs.hk` already is and teaches it to carry hk-nix's generated
# hk.pkl, baked in as HK_FILE. It does not pick a build of hk — a consumer who
# wants one other than nixpkgs' applies an overlay defining `pkgs.hk` before this
# one (see "Changing the hk binary" in the README).
{ ... }:

{
  flake.overlays.default = final: prev: {
    # Only `passthru` changes, so the derivation hash does not: an overlaid hk is
    # still the cached nixpkgs (or consumer-supplied) build.
    hk = prev.hk.overrideAttrs (old: {
      passthru = (old.passthru or { }) // {
        # Given the generated (store-path) hk.pkl, bake it in as HK_FILE so hk reads its
        # config from the store and needs no working-tree hk.pkl. hk-nix keys off the
        # presence of this attribute: when the package carries it (i.e. this overlay is
        # active) hk-nix drops the hk.pkl symlink; a plain hk lacks it, so hk-nix cannot
        # assume a baked HK_FILE and keeps symlinking. See run.nix.
        hkNixWithConfig =
          configFile:
          final.symlinkJoin {
            name = "hk-hk-nix";
            paths = [ prev.hk ];
            nativeBuildInputs = [ final.makeWrapper ];
            postBuild = "wrapProgram $out/bin/hk --set-default HK_FILE ${configFile}";
          };
      };
    });
  };
}
