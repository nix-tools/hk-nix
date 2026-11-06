# For a project whose `nix flake check` is too slow to run on every push: force evaluation instead.
#
# `nix flake show --all-systems` evaluates every output and builds none, so it catches a broken
# expression or a dangling reference for the price of an eval. That is the right trade when the
# outputs are expensive: here they are speech samples, minutes of CPU synthesis each.
#
# `nix eval` on one attribute is the same move at a smaller scale, and building one named check is
# the next step up, worth its seconds only for the output that can be wrong without anyone noticing
# until it is already running somewhere.
{ inputs, ... }:
{
  imports = [ inputs.hk-nix.flakeModules.default ];

  perSystem =
    { pkgs, ... }:
    {
      hk-nix.settings.hooks."pre-push".steps = {
        eval.check = "nix flake show --all-systems --json >/dev/null";
        version.check = "nix eval --raw .#version >/dev/null";
        manifest.check = "nix build .#checks.${pkgs.stdenv.hostPlatform.system}.manifest --no-link";
      };
    };
}
