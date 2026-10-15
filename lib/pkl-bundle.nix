# Bundles an hk source tree's Pkl into one importable store dir, exposed as `flake.lib.mkPklBundle`.
# hk ships individual `pkl/builtins/*.pkl` files but not the aggregated `Builtins.pkl`. It is a
# generated artifact (hk's scripts/gen_builtins.py) and is gitignored, so it is absent from the
# source tree. hk-nix synthesizes an equivalent and assembles a directory that hk-nix's generated
# hk.pkl can amend (Config.pkl) and import (Builtins.pkl) fully offline.
#
# ```nix
# mkPklBundle { pkgs, hkSrc } -> derivation (a /nix/store dir)
# ```
#
# The aggregation runs at build time, with `hkSrc` only interpolated into the script: `hkSrc` is
# typically `pkgs.hk.src`, a fetched derivation, so listing its builtins during evaluation would
# mean import-from-derivation.
#
# The bundle's closure is just itself: every file is copied, so the hk source is only a build input,
# and it references no linter packages, so importing it never pulls the 143 tools into a check
# derivation.
{ ... }:

{
  config.flake.lib.mkPklBundle =
    {
      pkgs,
      hkSrc,
    }:
    let
      pklDir = "${hkSrc}/pkl";

      # The aggregator's header: a `meta` annotation class, referenced by every builtin.
      header = ''
        // Synthesized by hk-nix, mirroring hk's scripts/gen_builtins.py header.
        // The `builtins/` this globs must hold real files: pklr 5 (hk 2.6) skips
        // symbolic links when it lists a glob, as pkl does.
        import* "builtins/*.pkl" as Builtins

        class ProjectIndicator {
          file: String?
          glob: String?
          contains: String?
        }
        class meta extends Annotation {
          category: String?
          description: String?
          project_indicators: Listing<ProjectIndicator>?
        }
      '';
    in
    pkgs.runCommand "hk-pkl-bundle" { inherit header; } ''
      mkdir -p $out

      # Copy the schema and project files (Config.pkl, Types.pkl, UserConfig.pkl,
      # PklProject*) and the builtins beside our Builtins.pkl so their relative imports resolve.
      for f in ${pklDir}/*.pkl ${pklDir}/PklProject ${pklDir}/PklProject.deps.json; do
        [ -e "$f" ] && cp "$f" "$out/"
      done
      cp -r ${pklDir}/builtins $out/

      # Drop a read-only copy left by the loop above, so the writes below can replace it.
      rm -f $out/Builtins.pkl

      # Re-export each builtin as a top-level property, so a consumer writes
      # `Builtins.gitleaks` rather than `Builtins["builtins/gitleaks.pkl"].gitleaks`.
      # Filenames use `-`, Pkl identifiers use `_` (mirrors gen_builtins.py).
      printf '%s\n' "$header" >$out/Builtins.pkl
      for f in ${pklDir}/builtins/*.pkl; do
        name=$(basename "$f" .pkl)
        ident=''${name//-/_}
        printf '%s = Builtins["builtins/%s.pkl"].%s\n' "$ident" "$name" "$ident" >>$out/Builtins.pkl
      done
    '';
}
