# Refuse to push a release tag that names a version the tagged commit does not carry.
#
# pre-push is the only hook that gets told what is being pushed, as lines of
# `<local ref> <local sha> <remote ref> <remote sha>` on standard input. hk exposes that as
# {{hook_stdin}}, so the step pipes it into a script rather than reading stdin itself.
#
# A deletion arrives with an all-zero local sha and is skipped. Everything else is read out of the
# tagged commit with `git show`, not out of the working tree, because the two can differ.
{ inputs, ... }:
{
  imports = [ inputs.hk-nix.flakeModules.default ];

  perSystem =
    { pkgs, lib, ... }:
    let
      check-tag-version = pkgs.writeShellApplication {
        name = "check-tag-version";
        runtimeInputs = [
          pkgs.git
          pkgs.gnused
        ];
        text = ''
          status=0
          while read -r local_ref local_sha _remote_ref _remote_sha; do
            case "$local_ref" in refs/tags/v*) ;; *) continue ;; esac
            case "$local_sha" in *[!0]*) ;; *) continue ;; esac

            tag="''${local_ref#refs/tags/}"
            commit="$(git rev-parse "$local_sha^{commit}")"
            crate="$(git show "$commit:Cargo.toml" \
              | sed -n '/^\[workspace\.package\]/,/^\[/{ s/^version = "\(.*\)"/\1/p }')"

            if [ "$tag" != "v$crate" ]; then
              echo "$tag names v$crate at ''${commit:0:12}" >&2
              status=1
            fi
          done
          exit "$status"
        '';
      };
    in
    {
      hk-nix.settings.hooks."pre-push".steps.tag-version.check =
        ''printf '%s\n' "{{hook_stdin}}" | ${lib.getExe check-tag-version}'';
    };
}
