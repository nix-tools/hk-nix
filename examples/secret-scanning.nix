# Keeping a secret out of a commit, two ways.
#
# This one runs on pre-commit rather than pre-push, because a leak is the finding where catching it
# one hook later is already too late: the secret is in the history by then and has to be rotated,
# not just amended away.
#
# betterleaks only auto-discovers .betterleaks.toml relative to the path it is given, and the paths
# here are individual files, so the config is named explicitly. --redact keeps the match itself out
# of the hook's output, which otherwise prints the secret to a terminal and a CI log.
#
# gitleaks is an hk builtin, so referencing it brings its globs and a pinned binary along; repin it
# with `.override { package = ...; }`.
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
    {
      hk-nix.settings.hooks."pre-commit".steps = {
        betterleaks.check = "${lib.getExe pkgs.betterleaks} dir --redact --no-banner --config .betterleaks.toml {{files}}";

        gitleaks.builtin = config.hk-nix.builtins.gitleaks;
      };
    };
}
