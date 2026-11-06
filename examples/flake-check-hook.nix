# A hook of its own for `nix flake check` to run, because neither of the other two fits it.
#
# `checks.hk` runs one hook over the whole tree, read-only, inside the Nix sandbox. pre-commit is
# the default and the wrong choice here: it fixes files. pre-push is the wrong choice too, since
# its steps want a cargo dependency closure and the refs they diff against, and the sandbox has
# neither.
#
# What does fit is the linters: they report without ever rewriting, so treefmt cannot own them,
# and they need nothing but the files. Declaring them once and sharing the set means the pinned
# tools and their globs are written in one place and run in both.
{ inputs, ... }:
{
  imports = [ inputs.hk-nix.flakeModules.default ];

  perSystem =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      lintSteps = {
        deadnix = {
          glob = "*.nix";
          check = "${lib.getExe pkgs.deadnix} --fail {{files}}";
        };
        hadolint.builtin = config.hk-nix.builtins.hadolint;
        shellcheck.builtin = config.hk-nix.builtins.shellcheck;
      };
    in
    {
      hk-nix.checkHook = "check";

      hk-nix.settings.hooks = {
        "check".steps = lintSteps;

        "pre-push".steps = lintSteps // {
          clippy.check = "cargo clippy --all-targets --all-features -- -D warnings";
        };
      };
    };
}
