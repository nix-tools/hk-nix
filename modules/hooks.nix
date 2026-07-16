# hk-nix dogfoods itself: its own git hooks are declared here in Nix and managed
# by hk-nix (not lefthook-nix). Commands reference linters by absolute store
# path so the exact same pinned tools run in the dev shell and in `nix flake
# check`.
{
  perSystem =
    { pkgs, lib, ... }:
    let
      nixfmt = lib.getExe pkgs.nixfmt-rfc-style;
      deadnix = lib.getExe pkgs.deadnix;

      steps = {
        nixfmt = {
          glob = "*.nix";
          check = "${nixfmt} --check {{files}}";
          fix = "${nixfmt} {{files}}";
        };
        deadnix = {
          glob = "*.nix";
          check = "${deadnix} --fail {{files}}";
          fix = "${deadnix} --edit {{files}}";
        };
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
