# Two checks for sqlx's offline query cache, each for a different kind of project.
#
# A query changed without `cargo sqlx prepare` compiles on a developer's machine and fails in the
# Nix sandbox, where no database is reachable. Answering "is .sqlx current?" properly needs a
# database, so that step runs only for someone who has one configured and says so otherwise; CI
# enforces it against the cluster the integration suite starts.
#
# Where the Nix build sets SQLX_OFFLINE itself, the cheaper reproduction is to do the same here:
# an incremental cargo check fails exactly where the build would, for a fraction of the time.
{ inputs, ... }:
{
  imports = [ inputs.hk-nix.flakeModules.default ];

  perSystem = _: {
    hk-nix.settings.hooks."pre-push".steps = {
      sqlx-prepared = {
        glob = "crates/example-store/**/*.rs";
        check = ''
          if [ -n "''${DATABASE_URL:-}" ]; then
            cargo sqlx prepare --workspace --check -- --all-targets
          else
            echo "DATABASE_URL unset, leaving the .sqlx check to CI"
          fi
        '';
      };

      sqlx-offline.check = "SQLX_OFFLINE=true cargo check --workspace --all-targets";
    };
  };
}
