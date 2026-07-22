# Bundles a pinned hk source tree's Pkl into one importable store dir, exposed as
# `flake.lib.mkPklBundle`. hk ships the 143 individual `pkl/builtins/*.pkl` files
# but NOT the aggregated `Builtins.pkl` — that is a generated artifact (hk's
# scripts/gen_builtins.py) and is gitignored, so it is absent from the pinned
# flake input. We synthesize an equivalent in pure Nix (no python, no pkl, no
# tools) and assemble a directory that hk-nix's generated hk.pkl can amend
# (Config.pkl) and import (Builtins.pkl) fully offline.
#
#   mkPklBundle { pkgs, hkSrc } -> derivation (a /nix/store dir)
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
      lib = pkgs.lib;
      pklDir = "${hkSrc}/pkl";

      # Builtin identifiers, read straight from the pinned store input. Filenames
      # use `-`, Pkl identifiers use `_` (mirrors gen_builtins.py).
      builtinNames = map (n: lib.removeSuffix ".pkl" n) (
        lib.filter (n: lib.hasSuffix ".pkl" n) (lib.attrNames (builtins.readDir "${pklDir}/builtins"))
      );
      ident = lib.replaceStrings [ "-" ] [ "_" ];

      # The aggregator: a `meta` annotation class (referenced by every builtin) and
      # a re-export of each builtin as a top-level property, so a consumer writes
      # `Builtins.gitleaks` rather than `Builtins["builtins/gitleaks.pkl"].gitleaks`.
      builtinsPkl = pkgs.writeText "Builtins.pkl" (
        ''
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

        ''
        + lib.concatMapStringsSep "\n" (
          n: ''${ident n} = Builtins["builtins/${n}.pkl"].${ident n}''
        ) builtinNames
        + "\n"
      );
    in
    pkgs.runCommand "hk-pkl-bundle" { } ''
      mkdir -p $out/builtins/test

      # Symlink the schema and project files (Config.pkl, Types.pkl, UserConfig.pkl,
      # PklProject*) beside our Builtins.pkl so their relative imports resolve.
      for f in ${pklDir}/*.pkl ${pklDir}/PklProject ${pklDir}/PklProject.deps.json; do
        [ -e "$f" ] && ln -s "$f" "$out/$(basename "$f")"
      done

      # `builtins/` must be a real dir of per-file symlinks — see Builtins.pkl above.
      for f in ${pklDir}/builtins/*.pkl; do ln -s "$f" "$out/builtins/$(basename "$f")"; done
      for f in ${pklDir}/builtins/test/*; do ln -s "$f" "$out/builtins/test/$(basename "$f")"; done

      rm -f $out/Builtins.pkl
      cp ${builtinsPkl} $out/Builtins.pkl
    '';
}
