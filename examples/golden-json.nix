# Parse the golden corpus, nothing more.
#
# These files are captured from a real external-dns rather than written by hand, so the way they go
# wrong is a hand-edit that stops them being JSON at all. Catching that needs no network and no
# build, which is why it can sit on pre-push next to the expensive steps.
{ inputs, ... }:
{
  imports = [ inputs.hk-nix.flakeModules.default ];

  perSystem =
    { pkgs, lib, ... }:
    {
      hk-nix.settings.hooks."pre-push".steps.golden = {
        glob = "crates/example/tests/golden/*.json";
        check = "${lib.getExe pkgs.jq} -e . {{files}} > /dev/null";
      };
    };
}
