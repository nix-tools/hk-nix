default:
    @just --list

# Check that every hk builtin's default package resolves to a real Nixpkgs
# package. Evaluation only — no builds, no downloads. Does not stop at the first
# failure: it classifies every builtin, prints a per-builtin result, tallies
# pass/fail, and exits non-zero if any builtin failed. Run in CI via
# .github/workflows/validate.yml (workflow_dispatch).
validate:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Resolving the default package of every hk builtin (eval-only)…"
    echo
    report=$(nix eval --impure --raw --expr '
      let
        flake = builtins.getFlake (toString ./.);
        # allowUnfree so a correctly-mapped but license-gated package (brakeman,
        # terraform) counts as passing; consumers still set allowUnfree themselves.
        pkgs = import flake.inputs.nixpkgs {
          system = builtins.currentSystem;
          config.allowUnfree = true;
        };
        lib = pkgs.lib;
        bi = flake.lib.mkHkBuiltins { inherit pkgs; hkSrc = flake.inputs.hk; };
        # Pass if the package is null (hk-native, needs none) or its derivation
        # evaluates; tryEval turns a throwing or absent package into a failure.
        ok = name: (builtins.tryEval (
          let p = bi.${name}.package; in p == null || p.drvPath != ""
        )).success;
        line = name: (if ok name then "pass " else "FAIL ") + name;
      in lib.concatStringsSep "\n" (map line (builtins.attrNames bi))
    ')
    printf "%s\n" "$report" | sort
    echo
    pass=$(printf "%s\n" "$report" | grep -c "^pass " || true)
    fail=$(printf "%s\n" "$report" | grep -c "^FAIL " || true)
    echo "── ${pass} passed, ${fail} failed (of $((pass + fail))) ──"
    if [ "${fail}" -ne 0 ]; then
      echo
      echo "Builtins with no resolving default package (add an exceptions entry or use .override):"
      printf "%s\n" "$report" | grep "^FAIL " | sed 's/^FAIL /  - /' | sort
      exit 1
    fi
