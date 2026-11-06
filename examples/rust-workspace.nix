# The Rust pre-push set: what is cheap to run here and expensive to discover in CI.
#
# None of it belongs in the check hook, because the `nix flake check` sandbox has neither the
# workspace's dependency closure nor a network to fetch it with.
{ inputs, ... }:
{
  imports = [ inputs.hk-nix.flakeModules.default ];

  perSystem = _: {
    hk-nix.settings.hooks."pre-push".steps = {
      clippy.check = "cargo clippy --all-targets --all-features -- -D warnings";

      # A manifest edit that left Cargo.lock behind otherwise shows up as a CI failure on
      # --locked, several commits after the one that caused it.
      lock-check.check = "cargo metadata --locked --format-version 1 > /dev/null";

      # Unit tests only: the integration suite starts a Postgres cluster, which is minutes
      # rather than seconds, and CI runs it with `just test-integration`.
      test.check = "cargo test --all-features -- --skip integration";
    };
  };
}
