# Nix -> Pkl renderer for hk configuration, exposed as `flake.lib.renderHkPkl`.
#
# Turns a Nix attrset describing an hk.pkl into a Pkl source string that
# `amends` a local (store-path) copy of hk's Config.pkl schema, so evaluation
# is fully offline — no `package://` fetch — and works inside the nix build
# sandbox. This is the hk analogue of lefthook.nix's `builtins.toJSON`+jq step,
# except Pkl is not JSON so we need a small, hk-shaped pretty-printer.
{ lib, ... }:

let
  inherit (builtins)
    isBool
    isInt
    isString
    isList
    isAttrs
    ;

  # Pkl string literals use JSON-like backslash escapes. Escape backslash and
  # quote first, then control characters (so their inserted backslashes are not
  # re-escaped). Note: hk template braces like `{{files}}` are literal in Pkl
  # (Pkl interpolation is `\(...)`, not `{{...}}`), so they need no escaping.
  escape =
    s: builtins.replaceStrings [ "\n" "\t" "\r" ] [ "\\n" "\\t" "\\r" ] (lib.escape [ "\\" "\"" ] s);

  indent = n: lib.concatStrings (lib.genList (_: "  ") n);

  # Keys whose values are Pkl `Mapping`s (rendered with `["key"]` entry syntax)
  # rather than plain object properties. This is the entire hk-specific bit of
  # knowledge the renderer needs.
  mappingKeys = [
    "hooks"
    "steps"
    "env"
  ];

  # Escape-hatch markers let a Nix value carry verbatim Pkl instead of a rendered
  # literal. Both are checked before the generic attrs handling, so a marker wins
  # even when its key is a Mapping key:
  #   { __pkl = "<expr>"; }              -> emitted as-is (e.g. `super.argv.drop(1)`)
  #   { __amends = "<expr>"; <body...> } -> `<expr> { <body> }` (Pkl amends), e.g.
  #                                         `(Builtins.gitleaks) { env { ... } }`
  isRaw = v: isAttrs v && v ? __pkl;
  isAmend = v: isAttrs v && v ? __amends;

  renderScalar =
    v:
    if isRaw v then
      v.__pkl
    else if isBool v then
      (if v then "true" else "false")
    else if isInt v then
      toString v
    else if isString v then
      "\"${escape v}\""
    else if isList v then
      "List(${lib.concatMapStringsSep ", " renderScalar v})"
    else
      throw "hk-nix: cannot render value of unsupported type: ${builtins.typeOf v}";

  # `<prefix> { <body> }`, or bare `<prefix>` when the amends body is empty (so a
  # package-less builtin renders as `Builtins.newlines`, not `... { }`).
  renderAmend =
    depth: pad: value:
    let
      body = renderObject (depth + 1) (removeAttrs value [ "__amends" ]);
    in
    if body == "" then value.__amends else "${value.__amends} {\n${body}\n${pad}}";

  # An object body: `name = value` for scalars, `name { ... }` for nested
  # objects, and `name { ["k"] ... }` for the known Mapping-valued keys.
  renderObject =
    depth: attrs:
    let
      pad = indent depth;
      renderEntry =
        name: value:
        if isRaw value then
          "${pad}${name} = ${value.__pkl}"
        else if isAmend value then
          "${pad}${name} = ${renderAmend depth pad value}"
        else if isAttrs value && builtins.elem name mappingKeys then
          "${pad}${name} {\n${renderMapping (depth + 1) value}\n${pad}}"
        else if isAttrs value then
          "${pad}${name} {\n${renderObject (depth + 1) value}\n${pad}}"
        else
          "${pad}${name} = ${renderScalar value}";
    in
    lib.concatStringsSep "\n" (lib.mapAttrsToList renderEntry attrs);

  # A Mapping body: `["key"] { ... }` for object values, `["key"] = value` for
  # scalar values (e.g. `env`), and `["key"] = <expr> { ... }` for amends/raw
  # (e.g. a builtin step: `["gitleaks"] = (Builtins.gitleaks) { ... }`).
  renderMapping =
    depth: attrs:
    let
      pad = indent depth;
      renderEntry =
        name: value:
        if isRaw value then
          "${pad}[\"${escape name}\"] = ${value.__pkl}"
        else if isAmend value then
          "${pad}[\"${escape name}\"] = ${renderAmend depth pad value}"
        else if isAttrs value then
          "${pad}[\"${escape name}\"] {\n${renderObject (depth + 1) value}\n${pad}}"
        else
          "${pad}[\"${escape name}\"] = ${renderScalar value}";
    in
    lib.concatStringsSep "\n" (lib.mapAttrsToList renderEntry attrs);
in
{
  # flake-parts has no built-in `flake.lib` output, so declare it as a mergeable
  # attrset here — otherwise the definitions spread across render-pkl.nix and
  # run.nix collide ("defined multiple times"). Declared once, defined anywhere.
  options.flake.lib = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = { };
    description = "Reusable Nix functions hk-nix exports as `hk-nix.lib.*`.";
  };

  # renderHkPkl { schemaPath, settings, imports ? [] } -> Pkl source string.
  #   schemaPath: absolute path to hk's Config.pkl (a /nix/store path).
  #   settings:   the hk.pkl top-level as a Nix attrset, e.g. { hooks = { ... }; }.
  #   imports:    extra modules to `import` (e.g. the overlay's Builtins.pkl), so
  #               builtin amends resolve `Builtins.*`.
  config.flake.lib.renderHkPkl =
    {
      schemaPath,
      settings,
      imports ? [ ],
    }:
    ''
      // This file is generated by hk-nix. Manual changes will be overwritten.
      amends "${toString schemaPath}"
    ''
    + lib.concatMapStrings (p: "import \"${toString p}\"\n") imports
    + "\n"
    + (renderObject 0 settings)
    + "\n";
}
