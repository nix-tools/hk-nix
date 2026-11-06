# The pre-commit hook everything else is built on: one formatting pass, fixing in place.
#
# `fix = true` lets hk rewrite a file instead of only reporting on it, and `stash = "git"` puts
# unstaged work aside while it does, so a partial `git add -p` survives the rewrite.
#
# treefmt-nix owns which formatter handles which syntax; this only decides when it runs.
{ inputs, ... }:
{
  imports = [ inputs.hk-nix.flakeModules.default ];

  perSystem =
    { config, lib, ... }:
    let
      treefmt = lib.getExe config.treefmt.build.wrapper;
    in
    {
      hk-nix.settings.hooks."pre-commit" = {
        fix = true;
        stash = "git";
        steps.treefmt = {
          # treefmt skips files it has no formatter for, so a catch-all glob is cheaper than
          # keeping a list of extensions in sync with the treefmt configuration.
          glob = "**/*";
          check = "${treefmt} --fail-on-change --no-cache {{files}}";
          fix = "${treefmt} {{files}}";
        };
      };
    };
}
