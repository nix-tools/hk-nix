# hk-nix's own test suite, exposed as `checks.test-*` so `nix flake check` runs it.
#
# It covers the ways hk-nix can be invoked, because hk-nix supports more of them than
# any one project uses: overlay or not, flake module or not, flake or not, dev shell or
# not. The behavioral tests matter more than the eval ones — the failure this design is
# most exposed to is a hook that runs no steps and exits 0, which looks like success.
{ config, ... }:

{
  perSystem =
    { pkgs, ... }:
    let
      lib = pkgs.lib;
      inherit (config.flake.lib)
        mkHkCheck
        withHkConfig
        mkHkBuiltins
        mkHkBin
        hkRelease
        ;

      # hk-nix does not apply its own overlay, so `pkgs` here is the un-overlaid one
      # and both sides of the overlay are testable in one evaluation.
      plainPkgs = pkgs;
      overlaidPkgs = pkgs.extend (import ./_wrapper.nix).overlay;
      nonFlake = import ../default.nix;

      # Steps reference `false`/`true` by store path, the same discipline consumers are
      # told to follow, so a step's success never depends on the ambient PATH.
      failStep = {
        glob = "*.bad";
        check = "${pkgs.coreutils}/bin/false";
      };
      # The hk the behavioral tests run. Back to `plainPkgs.hk` once nixpkgs ships hk 2.5
      # or later, the oldest whose Pkl evaluator reads the bundle's import expressions.
      testHk = hkBin;

      mkResult =
        settings:
        mkHkCheck {
          pkgs = plainPkgs;
          package = testHk;
          hkSrc = testHk.src;
          src = fixture;
          inherit settings;
        };

      # A clean tree: the check derivation over this must pass.
      fixture = pkgs.runCommand "hk-test-fixture" { } ''
        mkdir -p $out
        echo ok > $out/ok.txt
      '';

      # All three git-event hooks, because hk installs exactly the ones the config
      # declares — so a test declaring only pre-commit would not notice the other two
      # losing their absolute path. Only the pre-commit step ever matches a file.
      mkSettings = glob: {
        hooks =
          lib.genAttrs
            [
              "pre-commit"
              "commit-msg"
              "pre-push"
            ]
            (_: {
              steps.reject_bad = failStep // {
                inherit glob;
              };
            });
      };

      good = mkResult (mkSettings "*.bad");
      # A different config, so runtimeHk differs and the marker must re-trigger.
      other = mkResult (mkSettings "*.alsobad");

      # An hk-native builtin, whose command shells out to `hk util`. Steps like this are
      # the only ones that need hk on the step PATH, so nothing else here would notice
      # it going missing.
      hkNative = mkResult {
        hooks."commit-msg".steps.check_conventional_commit.builtin =
          (mkHkBuiltins {
            pkgs = plainPkgs;
            hkSrc = testHk.src;
          }).check_conventional_commit;
      };

      # The upstream release binary, paired with the Pkl schema from its own source
      # tarball. It runs a different hk version than nixpkgs', so this is where a schema
      # change upstream shows up. Only on the systems jdx/hk publishes assets for.
      #
      # The builtin is there for its import of the bundle's Builtins.pkl, which an hk
      # that evaluates Pkl differently from nixpkgs' may fail to load.
      hkBin = mkHkBin { pkgs = plainPkgs; };
      hkBinResult = mkHkCheck {
        pkgs = plainPkgs;
        package = hkBin;
        hkSrc = hkBin.src;
        src = fixture;
        settings.hooks = {
          "pre-commit".steps.reject_bad = failStep;
          "commit-msg".steps.check_conventional_commit.builtin =
            (mkHkBuiltins {
              pkgs = plainPkgs;
              hkSrc = hkBin.src;
            }).check_conventional_commit;
        };
      };

      cfg = pkgs.writeText "hk.pkl" "// test\n";

      # Evaluate assertions in Nix, report them at build time, so one failing check
      # does not stop the others from being evaluated.
      mkEvalTest =
        name: assertions:
        pkgs.runCommand name { } (
          lib.concatMapStrings (
            a: if a.ok then "echo 'ok   ${a.label}'\n" else "echo 'FAIL ${a.label}' >&2\nfailed=1\n"
          ) assertions
          + ''
            if [ -n "''${failed:-}" ]; then
              echo "--- ${name}: assertions failed ---" >&2
              exit 1
            fi
            touch $out
          ''
        );

      # hk builds an HTTPS client eagerly while loading config, even though our local
      # `amends` never fetches, and the sandbox's default SSL_CERT_FILE is a nonexistent
      # sentinel that makes that client fail to build. Same reason as in run.nix; no
      # request is made.
      sandboxEnv = {
        nativeBuildInputs = [
          pkgs.git
          pkgs.cacert
        ];
        SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      };

      # Common preamble for the behavioral tests: a throwaway repo, and a HOME so
      # `hk install` cannot see a real user's global hooks.
      repoSetup = ''
        export HOME=$PWD
        export NO_COLOR=1
        git config --global user.email test@example.com
        git config --global user.name Test
        git config --global init.defaultBranch main
      '';
    in
    {
      checks = {
        # The API a consumer writes against, in all four combinations of
        # overlay/no-overlay and module/no-module.
        test-api-matrix = mkEvalTest "test-api-matrix" [
          {
            label = "overlay attaches pkgs.hk.withConfig";
            ok = overlaidPkgs.hk ? withConfig;
          }
          {
            label = "plain pkgs.hk carries no withConfig";
            ok = !(plainPkgs.hk ? withConfig);
          }
          {
            label = "overlay does not rebuild hk (same outPath)";
            ok = overlaidPkgs.hk.outPath == plainPkgs.hk.outPath;
          }
          {
            label = "plain pkgs.hk bakes no HK_FILE";
            ok = plainPkgs.hk.name != "hk-hk-nix";
          }
          {
            label = "getExe on a wrapped hk resolves to bin/hk";
            ok = lib.hasSuffix "/bin/hk" (lib.getExe (overlaidPkgs.hk.withConfig cfg));
          }
          {
            label = "pkgs.hk.withConfig agrees with flake.lib.withHkConfig";
            ok =
              (overlaidPkgs.hk.withConfig cfg).outPath == (withHkConfig {
                pkgs = overlaidPkgs;
                package = plainPkgs.hk;
                configFile = cfg;
              }).outPath;
          }
          {
            label = "module wraps without the overlay applied";
            ok = good.runtimeHk.name == "hk-hk-nix";
          }
          {
            label = "module exposes the rendered configFile";
            ok = lib.hasSuffix "hk.pkl" good.configFile.name;
          }
          {
            label = "a config change changes runtimeHk";
            ok = good.runtimeHk.outPath != other.runtimeHk.outPath;
          }
        ];

        # Non-flake consumers reach the same overlay through the root default.nix.
        test-nonflake = mkEvalTest "test-nonflake" [
          {
            label = "default.nix exposes overlays.default";
            ok = nonFlake ? overlays && nonFlake.overlays ? default;
          }
          {
            label = "default.nix exposes lib.withHkConfig";
            ok = lib.isFunction nonFlake.lib.withHkConfig;
          }
          {
            label = "its overlay attaches withConfig";
            ok = (plainPkgs.extend nonFlake.overlays.default).hk ? withConfig;
          }
          {
            label = "it is the same overlay the flake exports";
            ok =
              (plainPkgs.extend nonFlake.overlays.default).hk.withConfig cfg == overlaidPkgs.hk.withConfig cfg;
          }
        ];

        # The shell hook installs config-based hooks, and pins the binary so the hook
        # does not depend on the dev shell being active.
        test-shellhook-install = pkgs.runCommand "test-shellhook-install" sandboxEnv ''
          ${repoSetup}
          mkdir repo && cd repo && git init -q

          ${good.shellHook}

          git config --local --get-regexp '^hook\.hk-.*\.command$' >installed
          cat installed

          for ev in pre-commit commit-msg pre-push; do
            grep -q "hook.hk-$ev.command .*${good.runtimeHk}/bin/hk run $ev --from-hook" installed \
              || { echo "FAIL: $ev not pinned to an absolute store path" >&2; exit 1; }
          done

          grep -q '|| hk run' installed \
            && { echo "FAIL: a bare hk survived the rewrite" >&2; exit 1; }

          [ "$(cat .git/hk-nix.installed)" = "${good.runtimeHk}" ] \
            || { echo "FAIL: marker not written" >&2; exit 1; }

          touch $out
        '';

        # Re-entering the shell is a no-op; changing the config reinstalls. Watch tools
        # re-run the hook constantly, so the no-op case has to stay quiet.
        test-shellhook-idempotence = pkgs.runCommand "test-shellhook-idempotence" sandboxEnv ''
          ${repoSetup}
          mkdir repo && cd repo && git init -q

          ( ${good.shellHook} ) 2>first
          grep -q 'updating' first || { cat first >&2; echo "FAIL: no install" >&2; exit 1; }

          ( ${good.shellHook} ) 2>second
          grep -q 'up to date' second || { cat second >&2; echo "FAIL: not idempotent" >&2; exit 1; }
          grep -q 'updating' second && { cat second >&2; echo "FAIL: reinstalled" >&2; exit 1; }

          # A different config must re-trigger, or a consumer edits hooks and the
          # old ones keep running.
          ( ${other.shellHook} ) 2>third
          grep -q 'updating' third || { cat third >&2; echo "FAIL: no re-trigger" >&2; exit 1; }
          [ "$(cat .git/hk-nix.installed)" = "${other.runtimeHk}" ] \
            || { echo "FAIL: marker not updated" >&2; exit 1; }

          touch $out
        '';

        # The failure this design is most exposed to: hk absent from PATH, where
        # `--from-hook` exits 0 silently and the commit sails through unchecked.
        test-hook-without-devshell = pkgs.runCommand "test-hook-without-devshell" sandboxEnv ''
          ${repoSetup}
          mkdir repo && cd repo && git init -q
          ${good.shellHook}

          # A subshell with an empty PATH, the way a hook fired by an IDE or a GUI
          # client sees it: no hk, no git, nothing. Scoped so the assertions below it
          # still have a shell to run in.
          (
            GIT=${pkgs.git}/bin/git
            export PATH=/nonexistent-on-purpose

            echo fine >ok.txt
            $GIT add ok.txt
            $GIT commit -q -m "test: clean tree" \
              || { echo "FAIL: a clean commit was blocked" >&2; exit 1; }

            echo bad >violation.bad
            $GIT add violation.bad
            if $GIT commit -q -m "test: seeded violation" 2>err; then
              echo "FAIL: the hook did not block a violation (silent pass)" >&2
              exit 1
            fi
          ) || exit 1

          touch $out
        '';

        # An hk-native builtin outside the dev shell: its command runs `hk util`, so hk
        # has to be on the step's own PATH. Nothing else here covers that, because every
        # other test step names its tool by store path.
        test-builtin-without-devshell = pkgs.runCommand "test-builtin-without-devshell" sandboxEnv ''
          ${repoSetup}
          mkdir repo && cd repo && git init -q
          ${hkNative.shellHook}

          (
            GIT=${pkgs.git}/bin/git
            export PATH=/nonexistent-on-purpose

            echo seed >seed.txt
            $GIT add seed.txt
            if $GIT commit -q -m "not a conventional commit at all" 2>err; then
              echo "FAIL: the builtin did not reject a bad commit message" >&2
              exit 1
            fi
            grep -qi 'command not found' err \
              && { echo "FAIL: the builtin could not find hk on PATH" >&2; cat err >&2; exit 1; }

            $GIT commit -q -m "test: a conventional commit message" \
              || { echo "FAIL: a valid commit message was rejected" >&2; exit 1; }
          ) || exit 1

          touch $out
        '';

        # HK=0 is hk's own escape hatch; it has to survive the rewrite.
        test-hook-escape-hatch = pkgs.runCommand "test-hook-escape-hatch" sandboxEnv ''
          ${repoSetup}
          mkdir repo && cd repo && git init -q
          ${good.shellHook}

          echo bad >violation.bad
          git add violation.bad
          HK=0 git commit -q -m "test: bypass" \
            || { echo "FAIL: HK=0 did not bypass the hook" >&2; exit 1; }

          touch $out
        '';

        # The check derivation must actually fail on a violation, or CI is decoration.
        test-check-rejects-violation =
          pkgs.runCommand "test-check-rejects-violation"
            (sandboxEnv // { nativeBuildInputs = sandboxEnv.nativeBuildInputs ++ [ good.runtimeHk ]; })
            ''
              ${repoSetup}
              mkdir repo && cd repo && git init -q
              echo bad >violation.bad
              git add -A

              if hk run pre-commit --all --check; then
                echo "FAIL: hk accepted a seeded violation" >&2
                exit 1
              fi

              touch $out
            '';

        # In a worktree .git is a file, so anything that treats it as a directory or
        # writes a path next to it breaks.
        test-worktree = pkgs.runCommand "test-worktree" sandboxEnv ''
          ${repoSetup}
          mkdir repo && cd repo && git init -q
          echo seed >seed.txt && git add -A && git commit -q -m "test: seed"
          git worktree add -q ../wt 2>/dev/null

          cd ../wt
          [ -f .git ] || { echo "FAIL: .git is not a file, test is void" >&2; exit 1; }

          ${good.shellHook}

          marker=$(git rev-parse --git-path hk-nix.installed)
          [ "$(cat "$marker")" = "${good.runtimeHk}" ] \
            || { echo "FAIL: marker not written in the worktree" >&2; exit 1; }

          git config --local --get-regexp '^hook\.hk-.*\.command$' \
            | grep -q "${good.runtimeHk}/bin/hk" \
            || { echo "FAIL: hooks not installed from the worktree" >&2; exit 1; }

          touch $out
        '';
      }
      // lib.optionalAttrs (hkRelease.assets ? ${pkgs.stdenv.hostPlatform.system}) {
        # The release binary end to end: the schema from the matching source tarball
        # has to parse under that binary, and the step it declares has to fire.
        test-hk-bin =
          pkgs.runCommand "test-hk-bin"
            (sandboxEnv // { nativeBuildInputs = sandboxEnv.nativeBuildInputs ++ [ hkBinResult.runtimeHk ]; })
            ''
              ${repoSetup}
              hk --version | grep -q '${hkBin.version}' \
                || { echo "FAIL: not the pinned release binary" >&2; exit 1; }

              mkdir repo && cd repo && git init -q
              echo bad >violation.bad
              git add -A

              if hk run pre-commit --all --check; then
                echo "FAIL: the release binary accepted a seeded violation" >&2
                exit 1
              fi

              touch $out
            '';
      };
    };
}
