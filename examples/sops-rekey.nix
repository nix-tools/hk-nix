# Fail the commit when a secret is no longer encrypted to the recipients .sops.yaml would assign it,
# which is what happens when someone adds an age key and forgets `sops updatekeys`.
#
# There is no read-only form of that question, so the check answers it by re-keying a throwaway copy
# of each file and seeing whether anything changed. The copy carries .sops.yaml along, because sops
# resolves the rules relative to the file it is rewriting.
{ inputs, ... }:
{
  imports = [ inputs.hk-nix.flakeModules.default ];

  perSystem =
    { pkgs, lib, ... }:
    let
      rekey-check = pkgs.writeShellApplication {
        name = "sops-rekey-check";
        runtimeInputs = [
          pkgs.sops
          pkgs.diffutils
          pkgs.coreutils
        ];
        text = ''
          shopt -s nullglob
          files=(secrets/*.yaml)
          [ ''${#files[@]} -eq 0 ] && exit 0

          root="$PWD"
          tmpdir="$(mktemp -d)"
          trap 'rm -rf "$tmpdir"' EXIT
          cp "$root/.sops.yaml" "$tmpdir/.sops.yaml"

          needs_rekey=0
          for f in "''${files[@]}"; do
            mkdir -p "$tmpdir/$(dirname "$f")"
            cp "$root/$f" "$tmpdir/$f"
            if (cd "$tmpdir" && sops updatekeys --yes "$f") >/dev/null 2>&1; then
              if ! diff -q "$root/$f" "$tmpdir/$f" >/dev/null 2>&1; then
                echo "$f is not encrypted to the current .sops.yaml recipients"
                needs_rekey=1
              fi
            else
              echo "could not check $f (is your age key available?)"
              needs_rekey=1
            fi
          done

          if [ "$needs_rekey" -ne 0 ]; then
            echo "run: sops updatekeys secrets/*.yaml"
            exit 1
          fi
        '';
      };
    in
    {
      hk-nix.settings.hooks."pre-commit".steps.sops-rekey = {
        glob = [
          ".sops.yaml"
          "secrets/*.yaml"
        ];
        check = lib.getExe rekey-check;
      };
    };
}
