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
# typically the release binary's `src`, a fetched derivation, so listing its builtins during
# evaluation would mean import-from-derivation.
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

      # One literal import per builtin, as gen_builtins.py has written since hk 2.5, so a config
      # evaluates only the builtins it uses. The import expression needs hk 2.5's pklr; nixpkgs'
      # hk 2.0.1 rejects it. Filenames use `-`, Pkl identifiers use `_`.
      printf '%s\n' "$header" >$out/Builtins.pkl
      for f in ${pklDir}/builtins/*.pkl; do
        name=$(basename "$f" .pkl)
        ident=''${name//-/_}
        printf '%s = import("builtins/%s.pkl").%s\n' "$ident" "$name" "$ident" >>$out/Builtins.pkl
      done
    '';
}
