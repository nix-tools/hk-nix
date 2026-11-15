# Check external links in the Markdown files staged for commit.
#
# The checker is network-backed, so it does not belong in the read-only sandbox
# that `nix flake check` uses for `checks.hk`. Point that check at a parse-only
# hook instead; it still catches malformed Markdown and invalid URLs without a
# request.
#
# Add `github:sshine/md-linkcheck` as a flake input and replace the placeholder
# below with `inputs'.md-linkcheck.packages.default`. The placeholder keeps this
# example evaluable by the examples harness, which validates configs but never
# runs their hooks.
{ inputs, ... }:
{
  imports = [ inputs.hk-nix.flakeModules.default ];

  perSystem =
    { lib, pkgs, ... }:
    let
      md-linkcheck = pkgs.writeShellScriptBin "md-linkcheck" ''
        echo "examples/linkcheck.nix: replace the md-linkcheck placeholder" >&2
        exit 2
      '';
    in
    {
      hk-nix.checkHook = "check";

      hk-nix.settings.hooks = {
        "pre-commit".steps.linkcheck = {
          # hk passes only the staged files that match the glob as {{files}}.
          glob = "**/*.md";
          # A backlog can intentionally record links that are already known dead.
          exclude = [ "linkcheck-backlog.md" ];
          check = "${lib.getExe md-linkcheck} check {{files}} --exclude-domain example.com";
        };

        "check".steps.linkcheck-parse = {
          glob = "**/*.md";
          exclude = [ "linkcheck-backlog.md" ];
          check = "${lib.getExe md-linkcheck} --quiet extract {{files}}";
        };
      };
    };
}
