# Ban the handful of call sites that would fetch over the network during a build.
#
# Each of these reaches out from a build script or from the asset bundler, which fails in the Nix
# sandbox and makes the build unreproducible everywhere else. The failure it produces is a sandbox
# error several layers from the line that caused it, so catching it by name here is worth the
# grep.
#
# The patterns match call syntax rather than bare words, so prose about any of them stays legal.
{ inputs, ... }:
{
  imports = [ inputs.hk-nix.flakeModules.default ];

  perSystem =
    { pkgs, lib, ... }:
    let
      rg = lib.getExe pkgs.ripgrep;
    in
    {
      hk-nix.settings.hooks."pre-push".steps.hermetic = {
        glob = "*.rs";
        check = ''! ${rg} --quiet -e 'asset!\("https?://' -e 'host: *Asset' -e 'iconify::' {{files}}'';
      };
    };
}
