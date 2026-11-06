# Seconds, not minutes: an eval catches every Nix error and dangling reference, and `helm lint`
# catches a chart that would fail to render once the cluster tries. The webpack build this project
# also has is ninety seconds and belongs in CI.
{ inputs, ... }:
{
  imports = [ inputs.hk-nix.flakeModules.default ];

  perSystem =
    { pkgs, lib, ... }:
    {
      hk-nix.settings.hooks."pre-push".steps = {
        eval.check = "nix eval --raw .#chartVersion >/dev/null";
        helm-lint.check = "${lib.getExe pkgs.kubernetes-helm} lint chart/example";
      };
    };
}
