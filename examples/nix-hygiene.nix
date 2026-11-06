# deadnix on pre-push, with generated files kept out of it.
#
# Not pre-commit: deadnix reports rather than rewrites, so it has nothing to contribute to the
# formatting pass, and a commit has to stay fast enough to make often.
#
# Cargo.nix is crate2nix output, 15k lines carrying unused lambda patterns throughout. It is
# regenerated and never edited, so deadnix would fail every push over something nobody can act on.
# `settings.exclude` drops it from every hook at once, matching what the treefmt configuration
# excludes; the per-step `--exclude` below is the same idea when only one step needs it.
{ inputs, ... }:
{
  imports = [ inputs.hk-nix.flakeModules.default ];

  perSystem =
    { pkgs, lib, ... }:
    {
      hk-nix.settings.exclude = [ "Cargo.nix" ];

      hk-nix.settings.hooks."pre-push".steps.deadnix = {
        glob = "*.nix";
        check = "${lib.getExe pkgs.deadnix} --fail {{files}}";
      };
    };
}
