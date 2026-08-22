# hk-nix's hk wrapper, as plain Nix. `import-tree` skips paths containing `/_`, so
# this file is not a flake-parts module and carries no flake machinery: the root
# default.nix imports it directly, which is what lets a non-flake consumer apply the
# overlay and call `pkgs.hk.withConfig`. overlay.nix re-exports the same values into
# `flake.lib` and `flake.overlays` for flake consumers.
let
  # Bake a generated hk.pkl into a copy of an hk package as HK_FILE.
  withHkConfig =
    {
      pkgs,
      package,
      configFile,
    }:
    pkgs.symlinkJoin {
      name = "hk-hk-nix";
      paths = [ package ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      # --set-default, so an HK_FILE already in the environment stays authoritative.
      postBuild = "wrapProgram $out/bin/hk --set-default HK_FILE ${configFile}";
      # symlinkJoin does not carry meta over, and without mainProgram `lib.getExe`
      # falls back to guessing the derivation name, i.e. a bin/hk-hk-nix that does
      # not exist.
      meta = (package.meta or { }) // {
        mainProgram = "hk";
      };
    };

  # `pkgs.hk` itself stays plain. Baking is opt-in at the point of use, because that
  # is where it is known which of hk's two jobs this copy has: running one project's
  # hooks, or being the hk CLI. A plain `pkgs.hk` in environment.systemPackages is the
  # CLI; a `withConfig` one in a dev shell runs that project's hooks.
  overlay = final: prev: {
    # Only `passthru` changes, so the derivation hash does not: an overlaid hk is
    # still the cached nixpkgs (or consumer-supplied) build.
    hk = prev.hk.overrideAttrs (old: {
      passthru = (old.passthru or { }) // {
        withConfig =
          configFile:
          withHkConfig {
            pkgs = final;
            package = prev.hk;
            inherit configFile;
          };
      };
    });
  };
in
{
  inherit withHkConfig overlay;
}
