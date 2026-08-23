{
  perSystem =
    { config, ... }:
    let
      hk-builtins = config.hk-nix.builtins;
      treefmt = config.treefmt.build.wrapper;
      steps.treefmt = {
        glob = "**/*.nix";
        check = "${treefmt}/bin/treefmt --fail-on-change --no-cache {{files}}";
        fix = "${treefmt}/bin/treefmt --no-cache {{files}}";
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
        "commit-msg".steps.check_conventional_commit.builtin = hk-builtins.check_conventional_commit;
      };
    };
}
