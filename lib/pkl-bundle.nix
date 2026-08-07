# Bundles an hk source tree's Pkl into one importable store dir, exposed as
# `flake.lib.mkPklBundle`. hk ships the 143 individual `pkl/builtins/*.pkl` files
# but NOT the aggregated `Builtins.pkl` — that is a generated artifact (hk's
# scripts/gen_builtins.py) and is gitignored, so it is absent from the source
# tree. We synthesize an equivalent (no python, no pkl, no tools) and assemble a
# directory that hk-nix's generated hk.pkl can amend (Config.pkl) and import
# (Builtins.pkl) fully offline.
#
#   mkPklBundle { pkgs, hkSrc } -> derivation (a /nix/store dir)
#
# The aggregation runs at build time, with `hkSrc` only interpolated into the
# script: `hkSrc` is typically `pkgs.hk.src`, a fetched derivation, so listing its
# builtins during evaluation would mean import-from-derivation.
#
# The bundle's closure is just itself plus the hk source: it references no linter
# packages, so importing it never pulls the 143 tools into a check derivation.
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
        // The `builtins/` this globs must be a REAL directory (per-file symlinks
        // are fine): Pkl `import*` does not descend a symlinked directory.
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
      mkdir -p $out/builtins/test

      # Symlink the schema and project files (Config.pkl, Types.pkl, UserConfig.pkl,
      # PklProject*) beside our Builtins.pkl so their relative imports resolve.
      for f in ${pklDir}/*.pkl ${pklDir}/PklProject ${pklDir}/PklProject.deps.json; do
        [ -e "$f" ] && ln -s "$f" "$out/$(basename "$f")"
      done

      # `builtins/` must be a real dir of per-file symlinks — see the header above.
      for f in ${pklDir}/builtins/*.pkl; do ln -s "$f" "$out/builtins/$(basename "$f")"; done
      for f in ${pklDir}/builtins/test/*; do ln -s "$f" "$out/builtins/test/$(basename "$f")"; done

      # Drop a symlink left by the loops above, so the writes below land in a real file.
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
