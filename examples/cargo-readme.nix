# Keep README.md generated from the crate's rustdoc, and fail the push when it has fallen behind.
#
# `check` regenerates to stdout and diffs against the committed file; `fix` writes it. Calling
# cargo-readme by store path means supplying the subcommand name by hand, because without it clap
# only prints its usage.
#
# cargo-readme resolves --input and --template against the working directory rather than against
# --project-root, and the hook runs from the project root, so both are spelled relative to it.
#
# cargo-readme emits markdown that mdformat then rewrites, moving link reference definitions to the
# end of the file. The raw output therefore never equals the committed README.md, and a formatting
# hook and a generation hook would undo each other forever. Piping through treefmt's own mdformat
# gives the two one fixpoint to agree on, and takes the plugin set from the same place.
{ inputs, ... }:
{
  imports = [ inputs.hk-nix.flakeModules.default ];

  perSystem =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      readmeArgs = "--project-root crates/example --input crates/example/src/lib.rs --template README.tpl";

      cargo-readme = "${lib.getExe' pkgs.cargo-readme "cargo-readme"} readme";
      mdformat = config.treefmt.settings.formatter.mdformat.command;

      readme = "${cargo-readme} ${readmeArgs} | ${mdformat} -";
    in
    {
      hk-nix.settings.hooks."pre-push".steps.readme = {
        check = "${readme} | diff - README.md";
        fix = "${readme} > README.md";
      };
    };
}
