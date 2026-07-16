# Expose the hk binary as a package and set the formatter.
{
  perSystem =
    { config, pkgs, ... }:
    {
      packages.hk = config.hk-nix.package;

      formatter = pkgs.nixfmt-rfc-style;
    };
}
