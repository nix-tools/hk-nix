# hk-nix's hk wrapper, in two spellings. `flake.lib.withHkConfig` bakes a generated
# hk.pkl into a copy of an hk package as HK_FILE; `flake.overlays.default` hangs the
# same function off `pkgs.hk` as `passthru.withConfig`, so a system configuration can
# spell it `pkgs.hk.withConfig ./hk.pkl` with no flake-parts and no flake at all.
#
# `pkgs.hk` itself stays plain. Baking is opt-in at the point of use, because that is
# where it is known which of hk's two jobs this copy has: running one project's hooks,
# or being the hk CLI. A plain `pkgs.hk` in environment.systemPackages is the CLI; a
# `withConfig` one in a dev shell runs that project's hooks.
{ config, ... }:

let
  inherit (config.flake.lib) withHkConfig;
in
{
  flake.lib.withHkConfig =
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

  flake.overlays.default = final: prev: {
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
}
