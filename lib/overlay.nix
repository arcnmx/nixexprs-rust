self: super: let
  inherit (super)
    isAttrs filterAttrs
    any toList isList findFirst filter
    optionalString hasPrefix removePrefix escape
    flip makeExtensible
  ;
  inherit (self)
    drvRec extendDerivation inputOffset
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

  findInput = inputs: package: let
    parseDrvName = drv: (builtins.parseDrvName (drv.name or "")).name;
    compare = lhs: rhs: parseDrvName lhs == parseDrvName rhs;
    find = pkg: any (compare pkg) (toList package);
  in
    if package == null then null
    else if isList package then filter find inputs
    else findFirst find (throw "cannot find ${package.name} in ${toString (map parseDrvName inputs)}") inputs;

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

  inherit (import ./files.nix self super)
    filterFiles filterFilesRecursive
    flattenFiles;

  inherit (import ./cargo.nix self super)
    crateName ghPages
    importCargo importCargo';
}
