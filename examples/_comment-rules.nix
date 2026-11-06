# ast-grep rules for strip-comments.nix, built into the store rather than left in the repository
# root, so they are pinned to the hook that reads them.
#
# ast-grep looks for an sgconfig.yml naming the directories its rules live in. `fix: ""` replaces a
# matched node with nothing, which is how a scan becomes a removal.
{ runCommand, writeText }:
let
  sgconfig = writeText "sgconfig.yml" ''
    ruleDirs:
      - rules
  '';

  # Rust distinguishes doc comments from ordinary ones in the grammar, so the rule can keep `///`
  # and `//!` and take everything else.
  rust = writeText "rust.yml" ''
    id: rust-comment
    language: rust
    severity: error
    message: only rustdoc comments are allowed
    rule:
      any:
        - kind: line_comment
        - kind: block_comment
      not:
        has:
          kind: doc_comment
    fix: ""
  '';

  nix = writeText "nix.yml" ''
    id: nix-comment
    language: nix
    severity: error
    message: no comments are allowed in Nix
    rule:
      kind: comment
    fix: ""
  '';

  yaml = writeText "yaml.yml" ''
    id: yaml-comment
    language: yaml
    severity: error
    message: no comments are allowed in YAML
    rule:
      kind: comment
    fix: ""
  '';

  # A shebang is a comment to the grammar and the kernel disagrees, so it is the one exception.
  bash = writeText "bash.yml" ''
    id: bash-comment
    language: bash
    severity: error
    message: no comments are allowed in shell
    rule:
      kind: comment
      not:
        regex: '^#!'
    fix: ""
  '';
in
runCommand "comment-rules" { } ''
  mkdir -p $out/rules
  cp ${sgconfig} $out/sgconfig.yml
  cp ${rust} $out/rules/rust.yml
  cp ${nix} $out/rules/nix.yml
  cp ${yaml} $out/rules/yaml.yml
  cp ${bash} $out/rules/bash.yml
''
