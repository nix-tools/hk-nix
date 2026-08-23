{
  perSystem =
    { config, ... }:
    {
      packages.hk = config.hk-nix.package;
    };
}
