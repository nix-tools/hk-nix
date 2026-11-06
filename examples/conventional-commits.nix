# Reject a commit message that is not a conventional commit.
#
# hk runs this builtin itself rather than shelling out to a pinned tool, so nothing needs
# installing and the step costs nothing in the closure.
#
# Its only policy knob is --allowed-types. A project that wants to require a scope ships its own
# checker and points the step at it instead:
#
#     steps.conventional.check =
#       "${lib.getExe config.packages.conventional-commit-check} {{commit_msg_file}}";
{ inputs, ... }:
{
  imports = [ inputs.hk-nix.flakeModules.default ];

  perSystem =
    { config, ... }:
    {
      hk-nix.settings.hooks."commit-msg".steps.conventional.builtin =
        config.hk-nix.builtins.check_conventional_commit;
    };
}
