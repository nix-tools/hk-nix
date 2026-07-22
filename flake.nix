{
  description = "hk-nix: a Nix wrapper for the hk git hook manager";

  inputs = {
    nixpkgs.url = "https://nixos.org/channels/nixpkgs-unstable/nixexprs.tar.xz";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    import-tree.url = "github:vic/import-tree";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    hk.url = "github:jdx/hk";
    hk.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ flake-parts, import-tree, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (import-tree ./lib);
}
