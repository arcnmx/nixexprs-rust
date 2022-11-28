self: super: let
  inherit (super)
    isAttrs filterAttrs mapAttrsToList listToAttrs nameValuePair
    optionals any toList isList findFirst filter concatLists
    optionalString hasPrefix removePrefix escape
    flip makeExtensible
  ;
  inherit (self)
    drvRec extendDerivation inputOffset
    crateName cratesRegistryUrl rustdocExtern
  ;
  inherit (builtins)
    isPath
  ;
in {
  makeOrExtend = attrs: attr: overlay: let
    overlay' = if isAttrs overlay then (_: _: overlay) else overlay;
  in if attrs ? ${attr}.extend then attrs.${attr}.extend overlay'
    else makeExtensible (flip overlay' attrs.${attr} or { });

  drvRec = fn: let
    drv = fn drv;
    passthru = {
      override = f: drvRec (drv: (fn drv).override f);
      overrideDerivation = f: drvRec (drv: (fn drv).overrideDerivation f);
      overrideAttrs = f: drvRec (drv: (fn drv).overrideAttrs f);
    };
  in extendDerivation true passthru drv;

  inputOffset = offset: input: input.__spliced.${offset} or input;
  buildInput = inputOffset "hostTarget";
  nativeInput = inputOffset "buildHost";

  retainAttrs = attrs: whitelist:
    filterAttrs (k: _: any (w: w == k) whitelist) attrs;

  srcName = prefix: src: let
    pname = src.pname or (builtins.parseDrvName src.name).name;
  in prefix + optionalString (pname != "source") "-${pname}";

  stripDot = path: let
    name = baseNameOf path;
  in if isPath path && hasPrefix "." name then builtins.path {
    name = removePrefix "." name;
    inherit path;
    recursive = false;
  } else path;

  escapePattern = escape (["." "*" "[" "]" "(" ")" "^" "$"]);

  rustdocExtern = let
  in crate: listToAttrs (map (pkg: nameValuePair pkg.name
    "https://docs.rs/${pkg.name}/${pkg.version}/"
  ) (filter (p: p.source.type == "registry" && p.source.url == cratesRegistryUrl) crate.lock.externalPackages));

  rustdocFlags = {
    zUnstableOptions ? enableUnstableRustdoc
  , enableUnstableRustdoc ? extern != { } || externDocsRs != { }
  , externDocsRs ? if crate == null then { } else rustdocExtern crate
  , extern ? { }
  , manual ? [ ]
  , crate ? null
  }: optionals zUnstableOptions [ "-Z" "unstable-options" ]
  ++ optionals enableUnstableRustdoc (concatLists (mapAttrsToList (crate: url:
    [ "--extern-html-root-url" "${crateName crate}=${url}" ]
  ) (removeAttrs externDocsRs manual // extern)));

  inherit (import ./files.nix self super)
    filterFiles filterFilesRecursive
    flattenFiles;

  inherit (import ./cargo.nix self super)
    crateName ghPages cratesRegistryUrl
    importCargo importCargo';
}
