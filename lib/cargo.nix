self: super: let
  inherit (builtins)
    replaceStrings match
    dirOf baseNameOf pathExists readFile
    mapAttrs removeAttrs attrNames attrValues
    isPath isString isAttrs
  ;
  inherit (super)
    isStringLike hasPrefix removePrefix concatStringsSep splitString
    singleton head tail last init elem elemAt findFirst filter partition any concatLists concatMap
    genAttrs optionalAttrs mapAttrsToList listToAttrs nameValuePair
    optional optionalString mapNullable
    makeOverridable makeExtensible
    cleanSourceWith importTOML
    fakeHash warn
  ;
  inherit (self)
    importCargo' cratesRegistryUrl
    flattenFiles filterFilesRecursive
    nix-gitignore
    crateName
  ;
in {
  crateName = replaceStrings [ "-" ] [ "_" ];

  ghPages = { owner, repo, path ? null }: "https://${owner}.github.io/${repo}"
    + optionalString (path != null) "/${path}";

  cratesRegistryUrl = "https://github.com/rust-lang/crates.io-index";

  importCargo' = let
    negateRule = rule: if hasPrefix "!" rule then removePrefix "!" rule else "!${rule}";
    superrule = root: rule: let
      negated = if hasPrefix "!" rule then "!" else "";
      rule' = removePrefix "!" rule;
    in if elem rule' [ "/" "." root ] then [ ]
      else singleton rule ++ superrule root (negated + (dirOf rule'));
    negateInclude = root: rules: let
      rules' = concatMap (superrule root) rules;
    in concatStringsSep "\n" (singleton "/**" ++ map negateRule rules');
    isSubpackage = path: pathExists (path + "/Cargo.toml");
    detectLockVersion = lock:
      if any (p: p ? checksum) lock.package or [] then 2
      else if any (hasPrefix "checksum ") (attrNames lock.metadata or {}) then 1
      else null;
    mapChecksum = checksum: let
      checksum'obj = {
        __toString = checksum: checksum.hash;
      } // optionalAttrs (isAttrs checksum) checksum;
    in optionalAttrs (isStringLike checksum) {
      hash = checksum;
    } // checksum'obj;
    fetchSource = pkg: { fetchurl ? builtins.fetchurl, fetchGit ? builtins.fetchGit, fetchgit ? null, src ? null }: let
      inherit (pkg) source;
    in {
      local = src;
      registry = if source.srcInfo != null then fetchurl {
        inherit (source.srcInfo) name url;
        ${if source.srcInfo.sha256 or null != null then "sha256" else null} = source.srcInfo.sha256;
      } else null;
      git = if fetchgit != null then fetchgit {
        url = source.srcInfo.url;
        rev = source.git.hash;
        ${if pkg.checksum.hash or null != null then "sha256" else null} = pkg.checksum.hash;
        ${if pkg.checksum ? submodules then "fetchSubmodules" else null} = pkg.checksum.submodules;
        ${if pkg.checksum ? shallow then "deepClone" else null} = !pkg.checksum.shallow;
        ${if source.git ? branch || hasPrefix "refs/heads/" source.git.ref or "" then "branchName" else null} =
          if source.git ? branch then "refs/heads/${source.git.branch}"
          else removePrefix "refs/heads/" source.git.rev;
      } else fetchGit {
        url = source.srcInfo.url;
        rev = source.git.hash;
        ${if source.git ? rev then "allRefs" else null} =
          ! source.git ? tag &&
          ! source.git ? branch &&
          ! hasPrefix "refs/" source.git.rev;
        ${if source.git ? tag || source.git ? branch || hasPrefix "refs/" source.git.ref or "" then "ref" else null} =
          if source.git ? tag then "refs/tags/${source.git.tag}"
          else if source.git ? branch then "refs/heads/${source.git.branch}"
          else source.git.rev;
        submodules = pkg.checksum.submodules or true;
        ${if pkg.checksum ? shallow then "shallow" else null} = pkg.checksum.shallow;
      };
      path = warn "TODO: path+ source" null;
      directory = warn "TODO: directory+ source" { };
    }.${source.type} or null;
    matchSource = match ''([^+]*)\+(.*)'';
    matchGitUrl = match ''([^?]+)(([?&][^=]*=[^&]*)*)#(.*)'';
    parseSource = { source, ... }@pkg: let
      match = matchSource source;
      type = elemAt match 0;
      url = elemAt match 1;
      parsed = {
        inherit type url source;
        __toString = self: self.source;
      } // {
        registry.srcInfo = if parsed.url == cratesRegistryUrl then {
          name = "crate-${pkg.name}-${pkg.version}.tar.gz";
          url = "https://crates.io/api/v1/crates/${pkg.name}/${pkg.version}/download";
          sha256 = pkg.checksum.hash or null;
        } else warn "unknown registry ${url}" null;
        git = let
          parsed = matchGitUrl url;
          args = splitString "&" (removePrefix "?" (elemAt parsed 1));
        in {
          srcInfo = {
            url = elemAt parsed 0;
            sha256 = pkg.checksum.hash or null;
          };
          git = {
            hash = elemAt parsed 3;
          } // listToAttrs (map (p: let
            kv = splitString "=" (removePrefix "&" p);
          in nameValuePair (head kv) (last kv)) args);
        };
        path = { };
        directory = { };
      }.${type} or (warn "unknown source type for ${source}" { });
    in if match == null
      then throw "cannot parse source ${source}"
      else parsed;
    mapDep = lock: name: {
      name = parsePackageDescriptor name;
      pkg = lock.pkg.${name};
      __toString = self: self.name;
    };
    mapPackage4 = mapPackage3;
    mapPackage3 = crate: lock: pkg: let
      crateIsPkg = crate: crate.package.name or null == pkg.name;
      checksum = lock.gitOutputHashes.explicit.${p.pname} or pkg.checksum or null;
      p = pkg // {
        pname = "${pkg.name}-${pkg.version}";
        descriptor = packageDescriptor pkg;
        checksum = mapChecksum checksum;
        source = if pkg ? source
          then parseSource pkg
          else {
            type = "local";
            inherit (pkg) name version;
            __toString = self: "local+${self.name}/${self.version}";
          };
        deps = map (mapDep lock) p.dependencies;
        dependencies = pkg.dependencies or [ ];
        data = pkg;
        src = makeOverridable (fetchSource p) {
          inherit (crate) src;
        };
        crate =
          if crateIsPkg crate then crate
          else findFirst crateIsPkg null (attrValues crate.members);
      };
    in p;
    mapPackage2 = crate: lock: pkg: mapPackage3 crate lock (if pkg ? branch then removeBranch pkg else pkg);
    mapPackage1 = crate: lock: pkg: let
      hash = lock.metadata."checksum ${packageDescriptor pkg}" or null;
    in mapPackage2 crate lock (pkg // {
      checksum = mapChecksum hash;
    });
    removeBranch = pkg: let
      source = parseSource pkg;
      args = removeAttrs source.git [ "hash" ] // {
        inherit (pkg) branch;
      };
    in assert source.type == "git"; removeAttrs pkg [ "branch" ] // {
      source = "git+${source.srcInfo.url}"
        + optionalString (args != { }) "?${concatStringsSep "&" (mapAttrsToList (k: v: "${k}=${v}") args)}"
        + optionalString (source.git.hash != null) "#${source.git.hash}";
    };
    packageDescriptor = pkg: "${pkg.name} ${pkg.version}" + optionalString (pkg.source or null != null) " (${pkg.source})";
    matchPackageDescriptor = match ''([^ ]*) ([^ ]*)( \(([^)]*)\))?'';
    parsePackageDescriptor = name: let
      match = matchPackageDescriptor name;
    in if match == null then {
      inherit name;
      __toString = self: self.name;
    } else {
      name = elemAt match 0;
      version = elemAt match 1;
      source = mapNullable head (elemAt match 2);
      descriptor = name;
      __toString = self: self.descriptor;
    };
  in {
    path
  , cargoToml ? null
  , parent ? null
  , self ? null
  , sourceInfo ? self.sourceInfo or null
  , globalIgnore ? [ "/.cargo/" "/.github/" ".direnv" ".envrc" "*.nix" "flake.lock" ]
  , cargoLock ? null
  , outputHashes ? { }
  , name ? "crate"
  , version ? "0.0.0"
  }@args: let
    paths = if baseNameOf path == "Cargo.toml" then {
      cargoTomlFile = path;
      root = dirOf path;
    } else {
      cargoTomlFile = path + "/Cargo.toml";
      root = path;
    };
    gitignore = paths.root + "/.gitignore";
    globalGitignoreString = concatStringsSep "\n" globalIgnore;
    cargoLockArgs =
      if cargoLock != null then cargoLock
      else if parent != null then parent.cargoLock
      else { lockFile = paths.root + "/Cargo.lock"; };
    cargoToml =
      if args.cargoToml or null != null
      then args.cargoToml
      else importTOML paths.cargoTomlFile;
    crate = makeExtensible (crate: cargoToml // {
      name = crate.cargoToml.package.name or name;
      version = crate.cargoToml.package.version or version;
      inherit (paths) root cargoTomlFile;
      inherit parent sourceInfo cargoToml;
      lock = makeExtensible (lock: let
        local = partition (p: p.source.type == "local") lock.packages;
      in {
        version = lock.data.version or (detectLockVersion lock.data);
        contents = cargoLockArgs.lockFileContents or (readFile cargoLockArgs.lockFile);
        data = fromTOML lock.contents;
        pkg = listToAttrs (concatMap (p: [
          (nameValuePair p.name p)
          (nameValuePair p.pname p)
          (nameValuePair p.descriptor p)
        ] ++ optional (p.source != null)
          (nameValuePair "${p.name} ${p.version}" p)
        ) lock.packages);
        packages = map ({
          "4" = mapPackage4;
          "3" = mapPackage3;
          "2" = mapPackage2;
          "1" = mapPackage1;
        }.${toString lock.version} or (throw "unsupported Cargo.lock version ${toString lock.version}") crate lock) lock.data.package;
        localPackages = local.right;
        externalPackages = local.wrong;
        gitPackages = filter (p: p.source.type == "git") lock.externalPackages;
        gitOutputHashes = let
          gitPackages = filter (p: p.data.checksum or null == null) lock.gitPackages;
          checksumPair = p: checksum: nameValuePair p.pname (mapChecksum checksum);
        in {
          default = listToAttrs (map (p: checksumPair p p.src.narHash or p.src.sha256 or fakeHash) lock.gitPackages);
          missing = listToAttrs (map (p: checksumPair p lock.gitOutputHashes.default.${p.pname}) gitPackages);
          explicit = cargoLockArgs.outputHashes or { } // outputHashes;
        };
        outputHashes = mapAttrs (_: mapChecksum) (lock.gitOutputHashes.missing // cargoLockArgs.outputHashes or lock.gitOutputHashes.default // lock.gitOutputHashes.explicit);
      });
      cargoLock = cargoLockArgs // {
        inherit (crate.lock) outputHashes;
      };
      cargoVendorDir = { importCargoLock }: importCargoLock crate.cargoLock;
      members = mapAttrs (_: path: importCargo' {
        inherit path globalIgnore outputHashes self sourceInfo;
        parent = crate;
      }) crate.workspaceFiles;
      workspaceFiles = genAttrs crate.cargoToml.workspace.members or [ ] (w: crate.root + "/${w}");
      filter = let
        noopFilter = _: _: true;
        defaultFilter = if pathExists (crate.root + "/.git")
          then noopFilter
          else path: type: ! hasPrefix "." (baseNameOf path);
        baseExcludes = [ "${toString crate.root}/target" "${toString crate.root}/.git" ];
        baseExclude = path: type: type != "directory" || ! (
          elem path baseExcludes || isSubpackage path
        );
        baseIncludes = [ "${toString crate.root}/Cargo.toml" "${toString crate.root}/Cargo.lock" ]
          ++ optional (crate ? package.license-file) crate.package.license-file
          ++ optional (crate ? package.readme) crate.package.readme;
        baseInclude = path: type: type == "regular" && (
          elem path baseIncludes
        );
        dirIncludes = map (r: toString (crate.root + "/${r}")) (concatMap (rule: superrule crate.root (dirOf rule)) crate.package.include or [ ]);
        dirInclude = path: type: type == "directory" && elem path dirIncludes;
        include =
          if crate ? package.include || ! crate ? package then nix-gitignore.gitignoreFilterPure noopFilter (
            negateInclude crate.root crate.package.include or [ ]
          ) crate.root else if pathExists gitignore then nix-gitignore.gitignoreFilterPure noopFilter (
            globalGitignoreString + "\n" + readFile gitignore
          ) crate.root else nix-gitignore.gitignoreFilterPure defaultFilter (
            globalGitignoreString
          ) crate.root;
        exclude =
          if crate ? package.exclude then
            nix-gitignore.gitignoreFilterPure baseExclude crate.package.exclude crate.root
          else baseExclude;
        crates = singleton crate ++ attrValues crate.members;
      in {
        include = path: type: baseInclude path type || include path type;
        inherit exclude dirInclude;
        workspace = path: type: any (w: hasPrefix (toString w.root) path && (
          path == toString w.root || w.filter path type
        )) crates;
        __functor = self: path: type: (self.exclude path type || self.dirInclude path type) && self.include path type;
      };
      pkgSrcs = flattenFiles crate.root (filterFilesRecursive crate.root crate.filter);
      srcs = crate.pkgSrcs ++ concatLists (mapAttrsToList (_: c: c.pkgSrcs) crate.members);
      workspaceSrcs = flattenFiles crate.root (filterFilesRecursive crate.root crate.filter.workspace);
      pkgSrc = let
        pname = crate.name or name + "-pkgsource";
      in cleanSourceWith {
        src = crate.root;
        inherit (crate) filter;
        name = "${pname}-${crate.version}";
      } // {
        inherit pname sourceInfo;
        inherit (crate) version;
      };
      src = let
        pname = crate.name + "-source";
      in cleanSourceWith {
        src = crate.root;
        filter = crate.filter.workspace;
        name = "${pname}-${crate.version}";
      } // {
        inherit pname sourceInfo;
        inherit (crate) version;
      };
      outPath = paths.cargoTomlFile;
    });
  in crate;

  importCargo = args: if isPath args || isString args then importCargo' {
    path = args;
  } else importCargo' args;
}
