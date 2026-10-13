# Prebuilt hk from the jdx/hk GitHub releases, exposed as `flake.lib.mkHkBin` and, on the
# systems upstream publishes for, as `packages.hk-bin`. nixpkgs' hk trails upstream by
# several releases, so this is the way to a newer hk without a Rust build.
#
# ```nix
# hk-nix.package = inputs.hk-nix.lib.mkHkBin { inherit pkgs; };
# ```
#
# Bumping to a new upstream release means editing `release` below: raise `version`, set
# the four hashes to `lib.fakeHash`, and build once per system to collect the real ones.
{ ... }:

let
  defaultRelease = {
    version = "2.6.0";

    # The source tree, for the Pkl schema only (see `src` below).
    srcHash = "sha256-deNbbrB98B0H3laHFD3eng7LdtYyyuYty86JZ2yygUM=";

    # Rust target triple per Nix system, plus the hash of the unpacked release tarball.
    # Linux takes the musl assets because they are static-pie: nothing to patchelf.
    assets = {
      x86_64-linux = {
        target = "x86_64-unknown-linux-musl";
        hash = "sha256-0AUJfRoQgwrIulzhb94PBxp247DEf4ahsLLYBNNMRp4=";
      };
      aarch64-linux = {
        target = "aarch64-unknown-linux-musl";
        hash = "sha256-vXg59SNQNCB6vZIMN5ur6O6aAaDJ/6u+Rcpq5uHS5J8=";
      };
      aarch64-darwin = {
        target = "aarch64-apple-darwin";
        hash = "sha256-9ZHHhczKikgpzylwGLr5MH/KT7R8jjNweQLrbcy6wwU=";
      };
    };
  };

  inherit (import ./_wrapper.nix) withHkConfig;

  mkHkBin =
    {
      pkgs,
      release ? defaultRelease,
    }:
    let
      inherit (pkgs) lib stdenvNoCC;
      inherit (stdenvNoCC) hostPlatform buildPlatform;

      asset =
        release.assets.${hostPlatform.system} or (throw (
          "hk-nix: upstream publishes no hk binary for ${hostPlatform.system}; "
          + "known systems are ${lib.concatStringsSep ", " (lib.attrNames release.assets)}"
        ));
    in
    stdenvNoCC.mkDerivation (finalAttrs: {
      pname = "hk";
      inherit (release) version;

      # The hk SOURCE tree, not the binary: hk-nix reads `package.src` for the Pkl
      # schema and the builtin definitions, so it has to be the tree carrying `pkl/`.
      # Both fetches are pinned to the same tag, so schema and binary cannot disagree.
      src = pkgs.fetchzip {
        url = "https://github.com/jdx/hk/archive/refs/tags/v${release.version}.tar.gz";
        hash = release.srcHash;
      };

      dist = pkgs.fetchzip {
        url = "https://github.com/jdx/hk/releases/download/v${release.version}/hk-${asset.target}.tar.gz";
        # The archive holds `hk` beside `skills/`, so there is no single root to strip.
        stripRoot = false;
        hash = asset.hash;
      };

      dontUnpack = true;
      dontConfigure = true;
      dontBuild = true;

      nativeBuildInputs = [ pkgs.installShellFiles ];

      installPhase = ''
        runHook preInstall
        install -Dm755 ${finalAttrs.dist}/hk $out/bin/hk
        runHook postInstall
      '';

      postInstall = lib.optionalString (buildPlatform.canExecute hostPlatform) ''
        installShellCompletion --cmd hk \
          --bash <($out/bin/hk completion bash) \
          --fish <($out/bin/hk completion fish) \
          --zsh <($out/bin/hk completion zsh)
      '';

      doInstallCheck = true;
      nativeInstallCheckInputs = [ pkgs.versionCheckHook ];

      # Same contract as the overlaid `pkgs.hk`, so hk-bin drops into `hk-nix.package`
      # and into a system configuration the same way.
      passthru.withConfig =
        configFile:
        withHkConfig {
          inherit pkgs configFile;
          package = finalAttrs.finalPackage;
        };

      meta = {
        description = "Tool for managing git hooks, from the upstream release build";
        homepage = "https://hk.jdx.dev";
        changelog = "https://github.com/jdx/hk/blob/v${release.version}/CHANGELOG.md";
        license = lib.licenses.mit;
        mainProgram = "hk";
        platforms = lib.attrNames release.assets;
        sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      };
    });
in
{
  flake.lib.mkHkBin = mkHkBin;
  flake.lib.hkRelease = defaultRelease;

  perSystem =
    { pkgs, system, ... }:
    {
      packages = pkgs.lib.optionalAttrs (defaultRelease.assets ? ${system}) {
        hk-bin = mkHkBin { inherit pkgs; };
      };
    };
}
