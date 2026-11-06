# The Go pre-push set.
#
# `go mod tidy -diff` is the one worth explaining: a go.sum that does not describe the imports fails
# the Nix build later with a far worse message than this one, and the fix is a single command.
{ inputs, ... }:
{
  imports = [ inputs.hk-nix.flakeModules.default ];

  perSystem =
    { pkgs, lib, ... }:
    {
      hk-nix.settings.hooks."pre-push".steps = {
        vet.check = "go vet ./...";
        staticcheck.check = "${lib.getExe' pkgs.go-tools "staticcheck"} ./...";
        tidy.check = "go mod tidy -diff";

        # Unit tests only; the integration suite needs a database and belongs in CI.
        test.check = "go test -short ./...";
      };
    };
}
