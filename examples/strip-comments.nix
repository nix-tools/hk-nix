# Remove every source comment that is not a doc comment, on pre-commit.
#
# A parser rather than a regex, because a `//` inside a string literal is not a comment and no
# pattern over lines can tell the difference. ast-grep matches on the tree-sitter node kind, so the
# rules in _comment-rules.nix stay four lines each.
#
# `check` reports and writes nothing. `fix` has to scan first and only then rewrite, because
# `--update-all --error` exits 0: --error reports what still matches, and after the rewrite nothing
# does, so the obvious spelling would fix the files and call the commit clean.
#
# `exclusive = true` keeps it from running beside treefmt, which writes the same files. Naming it so
# it sorts first means hk runs it first and alone, and treefmt afterwards cleans up the blank lines
# a removed comment leaves behind.
#
# Helm templates are excluded: they end in .yaml but hold Go template syntax, and a YAML parser
# rewriting them would produce something that no longer renders.
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
      treefmt = lib.getExe config.treefmt.build.wrapper;

      rules = pkgs.callPackage ./_comment-rules.nix { };
      scan = "${lib.getExe pkgs.ast-grep} scan -c ${rules}/sgconfig.yml";
    in
    {
      hk-nix.settings.hooks."pre-commit" = {
        fix = true;
        stash = "git";
        steps = {
          strip-comments = {
            glob = [
              "*.rs"
              "*.nix"
              "*.yaml"
              "*.yml"
              "*.sh"
            ];
            exclude = [ "charts/**" ];
            exclusive = true;
            check = "${scan} --error {{files}}";
            fix = "${scan} --error {{files}} || { ${scan} --update-all {{files}}; exit 1; }";
          };

          treefmt.check = "${treefmt} --fail-on-change --no-cache {{files}}";
          treefmt.fix = "${treefmt} {{files}}";
        };
      };
    };
}
