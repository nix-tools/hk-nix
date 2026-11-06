# Validation for examples/, exposed as `checks.example-*` so `nix flake check` covers it.
#
# Each file there is a flake-parts module a consumer could drop into their own flake, so it is
# documentation first and has to stay correct second. It is evaluated in a throwaway flake,
# rendered to Pkl, and handed to `hk validate`, which rejects a config hk could not load and warns
# about properties a release build would silently drop. The hooks themselves are never run: an
# example names cargo, go and tofu, none of which the sandbox has.
#
# The rendered Pkl has its string context discarded before it is written, so the check evaluates
# every linter the examples name without building any of them. The Pkl bundle stays a real
# dependency, because the generated file amends it by store path.
{ config, inputs, ... }:

{
  perSystem =
    { pkgs, system, ... }:
    let
      lib = pkgs.lib;
      inherit (config.flake.lib)
        mkHkBin
        mkPklBundle
        renderHkPkl
        desugarBuiltins
        ;

      hk = mkHkBin { inherit pkgs; };
      bundle = mkPklBundle {
        inherit pkgs;
        hkSrc = hk.src;
      };

      basePath = lib.makeBinPath [
        hk
        pkgs.bash
        pkgs.coreutils
      ];

      # An example configures hooks and nothing else, so the formatter matrix it reads
      # (`config.treefmt.*`) has to come from somewhere. In a real project that is the consumer's
      # own treefmt module; here it is this.
      harness = {
        perSystem.treefmt = {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
          programs.mdformat.enable = true;
        };
      };

      # What an example sees as `inputs`. flake-parts reads `self.inputs` to build each module's
      # `inputs'`, so the fake self has to carry them too.
      harnessInputs = rec {
        inherit (inputs) nixpkgs flake-parts treefmt-nix;
        hk-nix.flakeModules.default = config.flake.flakeModules.default;
        self = {
          outPath = ../.;
          inputs = harnessInputs;
        };
      };

      # Files starting with an underscore are an example's helpers, not examples.
      exampleFiles = lib.filterAttrs (
        name: type: type == "regular" && lib.hasSuffix ".nix" name && !lib.hasPrefix "_" name
      ) (builtins.readDir ../examples);

      # `debug = true` is what makes the evaluated perSystem config reachable from outside, which
      # is the only way to read back what the example declared.
      settingsOf =
        file:
        (inputs.flake-parts.lib.mkFlake { inputs = harnessInputs; } {
          systems = [ system ];
          debug = true;
          imports = [
            inputs.treefmt-nix.flakeModule
            harness
            (import file)
          ];
        }).allSystems.${system}.hk-nix.settings;

      mkCheck =
        fileName:
        let
          name = lib.removeSuffix ".nix" fileName;
          pkl = pkgs.writeText "hk-${name}.pkl" (
            builtins.unsafeDiscardStringContext (renderHkPkl {
              settings = desugarBuiltins { inherit basePath; } (settingsOf (../examples + "/${fileName}"));
              schemaPath = "${bundle}/Config.pkl";
              imports = [ "${bundle}/Builtins.pkl" ];
            })
          );
        in
        lib.nameValuePair "example-${name}" (
          pkgs.runCommand "example-${name}"
            {
              nativeBuildInputs = [
                hk
                pkgs.cacert
              ];
              # The amends and import above carry no context any more, so name the bundle here to
              # keep it in the closure.
              inherit bundle;
              # Same reason as in run.nix: hk builds an HTTPS client while loading config, and the
              # sandbox's default SSL_CERT_FILE is a nonexistent sentinel. No request is made.
              SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
            }
            ''
              export HOME="$PWD"
              export NO_COLOR=1
              export HK_FILE=${pkl}

              # A warning exits 0, and the thing it warns about is a property hk drops on the
              # floor -- which is exactly the mistake an example must not teach. So they fail here.
              hk validate >log 2>&1 || { cat log >&2; exit 1; }
              cat log
              if grep -q 'WARN' log; then
                echo "examples/${fileName}: hk validate reported warnings" >&2
                exit 1
              fi

              touch $out
            ''
        );
    in
    {
      checks = lib.mapAttrs' (fileName: _: mkCheck fileName) exampleFiles;
    };
}
