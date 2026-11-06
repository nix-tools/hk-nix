# Build the site on pre-push, into a directory that is thrown away.
#
# No glob: a change to a template, a shortcode or the config can break a page that was not itself
# edited, so there is no file set that means "the render is still fine". Hugo takes a second or
# two, which pre-push can afford and pre-commit cannot.
{ inputs, ... }:
{
  imports = [ inputs.hk-nix.flakeModules.default ];

  perSystem =
    { pkgs, ... }:
    {
      hk-nix.settings.hooks."pre-push".steps.hugo.check = ''
        ${pkgs.hugo}/bin/hugo --minify --quiet --destination "$(mktemp -d)"
      '';
    };
}
