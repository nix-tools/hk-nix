# Expose the hk binary as a package. The formatter is set by treefmt-nix (see
# treefmt.nix).
{
  perSystem =
    { config, ... }:
    {
      packages.hk = config.hk-nix.package;
    };
}
