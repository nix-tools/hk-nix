# `tofu validate` on pre-push.
#
# It needs an initialized working directory, so the step makes one first. With the provider already
# in the store that costs no network, and -backend=false keeps it away from state entirely. So this
# says nothing about whether the configuration matches what is deployed, only that it parses and
# typechecks.
{ inputs, ... }:
{
  imports = [ inputs.hk-nix.flakeModules.default ];

  perSystem =
    { pkgs, lib, ... }:
    let
      tofu = lib.getExe pkgs.opentofu;
    in
    {
      hk-nix.settings.hooks."pre-push".steps.tofu-validate = {
        glob = "*.tf";
        check = "${tofu} init -backend=false -input=false -upgrade >/dev/null && ${tofu} validate";
      };
    };
}
