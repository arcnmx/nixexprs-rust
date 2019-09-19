self: super: {
  makeOrExtend = attrs: attr: overlay: let
    overlay' = if super.isAttrs overlay then (_: _: overlay) else overlay;
  in if attrs ? ${attr}.extend then attrs.${attr}.extend overlay'
    else super.makeExtensible (super.flip overlay' attrs.${attr} or { });

  fromTOML = builtins.fromTOML or (import ./lib/parseTOML.nix).fromTOML;

  drvRec = fn: let
    drv = fn drv;
    passthru = {
      override = f: self.drvRec (drv: (fn drv).override f);
      overrideDerivation = f: self.drvRec (drv: (fn drv).overrideDerivation f);
      overrideAttrs = f: self.drvRec (drv: (fn drv).overrideAttrs f);
    };
  in self.extendDerivation true passthru drv;

  findInput = inputs: package: with self; let
    parseDrvName = drv: (builtins.parseDrvName (drv.name or "")).name;
    compare = lhs: rhs: parseDrvName lhs == parseDrvName rhs;
    find = pkg: any (compare pkg) (toList package);
  in
    if package == null then null
    else if isList package then builtins.filter find inputs
    else findFirst find (throw "cannot find ${package.name} in ${toString (map parseDrvName inputs)}") inputs;

  retainAttrs = attrs: whitelist: with self;
    filterAttrs (k: _: any (w: w == k) whitelist) attrs;
}
