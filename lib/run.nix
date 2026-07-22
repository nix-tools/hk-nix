# Core of hk-nix, exposed as `flake.lib.mkHkCheck` and mirroring lefthook.nix's
# lib/config/default.nix: it returns a single value that is BOTH the `nix flake
# check` derivation and the carrier of the `.shellHook` used to install hooks in
# a dev shell. Same config, run the same way locally and in CI.
#
#   mkHkCheck { pkgs, package, src, settings, schemaPath, checkHook ? "pre-commit" }
#
# The Nix -> Pkl renderer is taken from `flake.lib.renderHkPkl` (see
# render-pkl.nix); `config` here is hk-nix's own, captured by closure, so the
# renderer travels with mkHkCheck into a consumer's flake unchanged.
{ config, ... }:

{
  flake.lib.mkHkCheck =
    {
      pkgs,
      package,
      src,
      settings,
      hkSrc,
      # Which hook the CI check derivation runs (read-only, over all files).
      checkHook ? "pre-commit",
    }:
    let
      lib = pkgs.lib;
      inherit (config.flake.lib) renderHkPkl mkPklBundle desugarBuiltins;

      # Amends Config.pkl and imports Builtins.pkl from a store-path bundle (see
      # pkl-bundle.nix), so builtin steps resolve `Builtins.*` offline in the
      # check sandbox. The bundle pulls no linter packages into the closure.
      pklBundle = mkPklBundle { inherit pkgs hkSrc; };

      # Pinned `sh`+coreutils appended to each builtin step's PATH (see below).
      basePath = lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
      ];

      configFile = pkgs.writeText "hk.pkl" (renderHkPkl {
        # Rewrite `{ builtin = ...; }` steps into `(Builtins.x) { ... }` amends.
        settings = desugarBuiltins { inherit basePath; } settings;
        schemaPath = "${pklBundle}/Config.pkl";
        imports = [ "${pklBundle}/Builtins.pkl" ];
      });

      # CI half: copy the source into a sandbox, make a throwaway git repo with
      # all files staged, and run the hook in check-only mode so it fails (not
      # fixes) on findings. Linters are referenced by absolute store path from
      # `settings`, so they need not be on PATH here.
      check =
        pkgs.runCommand "hk-check"
          {
            nativeBuildInputs = [
              package
              pkgs.git
              pkgs.cacert
            ];
            # hk builds an HTTPS client eagerly while loading config (even though our
            # local `amends` never fetches). The sandbox's default SSL_CERT_FILE is a
            # nonexistent sentinel, which makes that client fail to build — so point
            # it at a real CA bundle. No network request is actually made.
            SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          }
          ''
            set +e
            export HOME="$PWD"
            export NO_COLOR=1

            cp -R ${src} ./src
            chmod -R +w ./src
            rm -rf ./src/.git
            ln -sf ${configFile} ./src/hk.pkl

            cd ./src
            git init -q
            git add -A
            hk run ${lib.escapeShellArg checkHook} --all --check
            code=$?
            if [ "$code" -ne 0 ]; then
              exit "$code"
            fi
            touch "$out"
          '';

      # Dev half: symlink the generated hk.pkl into the repo root and (re)install
      # git hooks. On git 2.54+ `hk install` writes config-based hooks into
      # .git/config and leaves .git/hooks/ untouched; we prepend a recent git to
      # PATH to guarantee that path is taken, and never pass --legacy.
      #
      # Compares before writing to avoid filesystem churn with watch tools (lorri,
      # direnv) and to avoid reinstall loops.
      installationScript = ''
        export PATH=${package}/bin:${pkgs.git}/bin:$PATH
        # TODO: HK_FILE is not supported yet.
        function _log() { echo 1>&2 "$*"; }

        if ! command -v git >/dev/null; then
          _log "WARNING: hk-nix: git command not found, skipping installation."
        elif [ ! -e .git ]; then
          # .git can be an ASCII text file for worktrees, so use -e instead of -d.
          _log "WARNING: hk-nix: .git does not exist, skipping installation."
        else
          if readlink hk.pkl >/dev/null 2>&1 \
              && [[ $(readlink hk.pkl) == ${configFile} ]]; then
            _log "hk-nix: hk configuration up to date"
          else
            _log "hk-nix: updating $PWD hk configuration"

            if [ -L hk.pkl ]; then
              unlink hk.pkl
            fi

            if [ -f hk.pkl ]; then
              _log "WARNING: hk-nix: hk.pkl already exists. Please remove hk.pkl and add hk.pkl to .gitignore."
            else
              ln -s ${configFile} hk.pkl

              # Reinstall so config-based (git 2.54+) hooks stay in sync; never --legacy.
              hk uninstall >/dev/null 2>&1 || true
              hk install
            fi
          fi
        fi

        unset -f _log
      '';
    in
    check
    // {
      inherit configFile;
      shellHook = installationScript;
    };
}
