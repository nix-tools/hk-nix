# treefmt-nix owns the formatter matrix (which formatter handles which syntax)
# and provides the `nix fmt` formatter and a `checks.treefmt`. hk-nix's hook runs
# the resulting wrapper (see hooks.nix), so formatting has one source of truth
# while hk-nix drives when it runs.
{ inputs, ... }:

{
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem.treefmt = {
    projectRootFile = "flake.nix";
    programs.nixfmt.enable = true;
    programs.deadnix.enable = true;
  };
}
