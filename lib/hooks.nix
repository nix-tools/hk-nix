# hk-nix dogfoods itself: its own git hooks are declared here in Nix and managed by hk-nix.
# It uses hk's `nix_fmt` and `deadnix` builtins, each pinned from nixpkgs, so the same tools
# run in the dev shell and in `nix flake check`.
{
  perSystem =
    { config, ... }:
    let
      inherit (config.hk-nix) builtins;
      steps = {
        nix_fmt.builtin = builtins.nix_fmt;
        deadnix.builtin = builtins.deadnix;
      };
    in
    {
      hk-nix.settings.hooks = {
        "pre-commit" = {
          fix = true;
          stash = "git";
          inherit steps;
        };
        "pre-push".steps = steps;
      };
    };
}
