{ pkgs, lib, self, ... }: let
in {
  parseRustToolchain = file: with builtins; let
    res = match "([a-z]*)-([0-9-]*).*" (readFile file);
  in {
    channel = head res;
    date = head (tail res);
  };

  # See https://github.com/rust-lang-nursery/rustup.rs/blob/master/src/rustup-dist/src/dist.rs
  manifest_v1_url = {
    distRoot ? self.distRoot
  , date ? null
  , staging ? false
    # A channel can be "nightly", "beta", "stable", "\d{1}.\d{1}.\d{1}", or "\d{1}.\d{2\d{1}".
  , channel
  }: if date == null && staging == false
    then "${distRoot}/channel-rust-${channel}"
    else if date != null && staging == false
    then "${distRoot}/${date}/channel-rust-${channel}"
    else if date == null && staging == true
    then "${distRoot}/staging/channel-rust-${channel}"
    else throw "not a real-world case";

  distRoot = "https://static.rust-lang.org/dist";
  distFormat = "xz";

  getFetchUrl = srcInfo:
    self.fetchurl (if self.distFormat == "xz" && srcInfo ? xz_url then {
      url = srcInfo.xz_url;
      sha256 = srcInfo.xz_hash;
    } else {
      url = srcInfo.url;
      sha256 = srcInfo.hash;
    });

  manifestPath = { url, sha256 ? null, path ? null, channel ? null }:
    if path != null && builtins.pathExists path then path /*builtins.path ({
      # TODO: builtins.path doesn't work as well with IFD as a direct path to the original because it generates a store path that needs to be copied/built first :(
      inherit path;
      recursive = false;
    } // lib.optionalAttrs (sha256 != null) {
      inherit sha256;
    } // lib.optionalAttrs (channel != null) {
      # TODO: consider making this "channel-rust-stable" for versioned releases so it shares the same nix store path as impure fetches?
      # also set name when fetchurl'ing too!
      # considering this is IFD'd this doesn't matter much, the resulting rust derivations will be identical regardless
      name = "channel-rust-${channel}.toml";
    })*/ else if sha256 == null then builtins.fetchurl url else self.fetchurl { inherit sha256 url; };

} // lib.mapAttrs (_: lib.flip pkgs.callPackage { }) {
  manifest_v2_url = { lib }: with lib;
    setFunctionArgs (args: (self.manifest_v1_url args) + ".toml") (functionArgs self.manifest_v1_url);

  # TODO: ideally we want to use pkgs.fetchurl here but don't like how it calls out to curl... override this if you need to?
  fetchurl = { fetchurl }: let
    nix-fetchurl = builtins.tryEval (import <nix/fetchurl.nix>);
  in if nix-fetchurl.success then nix-fetchurl.value else fetchurl;

  getPackageTarget = { stdenvNoCC, stdenv, lib, autoPatchelfHook }: { target, buildInputs }: with lib; let
    extensions = filterAttrs (_: v: v.embedded && v.available) target.extensions;
    hasOut = target.components == { };
    outputs = [ "out" ] ++ (mapAttrsToList (_: { name, ... }: name) (target.components // extensions));
    hasCargo = target.name == "cargo" || any (o: o == "cargo") outputs;
    mkDerivation = (if stdenvNoCC.hostPlatform.isLinux then stdenv else stdenvNoCC).mkDerivation;
  in mkDerivation {
    inherit (target) version;
    pname = target.name;
    name = if target.version == null then "${target.name}-bin" else "${target.name}-bin-${target.version}";

    src = self.getFetchUrl target;

    meta = {
      broken = !(target.available or true);
      platforms = stdenvNoCC.lib.platforms.all;
    };

    passthru = {
      rust = {
        target = target;
        components = target.components // optionalAttrs hasOut { ${target.name} = target; };
        extensions = target.extensions;
      };
    };

    preferLocalBuild = true;
    nativeBuildInputs = optionals stdenvNoCC.hostPlatform.isLinux [ autoPatchelfHook ];
    inherit buildInputs;

    dontStrip = true;
    forceShare = " ";

    inherit outputs hasOut;

    pathSubstitutions = [
      "-e" "s=^etc/bash_completion\\.d=share/bash_completion/completions="
      "-e" "s=^etc/bash_completions\\.d=share/bash_completion/completions="
    ];

    ${if hasCargo then "setupHook" else null} = builtins.toFile "cargo-setup-hook.sh" ''
      # see <nixpkgs/pkgs/development/compilers/rust/setup-hook.sh>
      if [[ -z $IN_NIX_SHELL && -z $CARGO_HOME ]]; then
        export CARGO_HOME=$TMPDIR
      fi
    '';

    preConfigure = ''
      safeOutputs=()
      for output in $outputs; do
        safeOutput=''${output//-/_}
        safeOutputs+=($safeOutput)
        export $safeOutput=$(printenv $output)
      done
      export outputs="''${safeOutputs[*]}"
    '';

    installPhase = ''
      outpath() {
        echo "$*" | sed $pathSubstitutions
      }

      install_rust() {
        for component in "$@"; do
          if [[ $component = $pname ]]; then
            cout=$out
          else
            cout=$(printenv $component || true)
            if [[ -z $cout ]]; then
              echo WARNING: $component exists but not available
              continue
            fi
          fi
          echo "Install component $component -> $cout"
          while IFS= read -r line; do
            # TODO: merge etc/ stuff into here?
            if [[ $line = file:* ]]; then
              path=''${line#file:}
              opath=$(outpath $path)
              mkdir -p $cout/$(dirname $opath)
              mv $component/$path $cout/$opath
              if [[ $path = bin/* ]]; then
                chmod +x $cout/$opath
              fi
            elif [[ $line = dir:* ]]; then
              path=''${line#dir:}
              opath=$(outpath $path)
              if [[ ! -d $cout/$opath ]]; then
                mkdir -p $cout/$(dirname $opath)
                mv $component/$path $cout/$opath
              else
                while IFS= read -r -d "" file; do
                  ofile=$(outpath $file)
                  if [[ -d $component/$file ]]; then
                    mkdir -p $cout/$ofile
                  else
                    mkdir -p $cout/$(dirname $ofile)
                    mv $component/$file $cout/$ofile
                    # TODO: chmod bin/?
                  fi
                done < <(cd $component && find $path -print0)
              fi
            else
              echo "unknown command $line"
              exit 1
            fi
            [[ ! -d $cout/etc ]] || (
              echo Installer tries to install to /etc:
              find $cout/etc
              exit 1
            )
          done < $component/manifest.in

          # um?
          rm $component/manifest.in
          find $component -type d -delete
        done
      }

      #CFG_DISABLE_LDCONFIG=1 ./install.sh --prefix=$out --verbose
      install_rust $(cat components)

      if [[ -z $hasOut ]]; then
        mkdir $out
      fi

      # stdenv is very fussy about multiple outputs...
      unset -f moveToOutput
      moveToOutput() { :; }
    '';
  };

  manifestDerivationsFor = { lib }: with lib; { manifest, pkgDescriptions }: let
    pkgDerivations = mapAttrs (_: getPackageTargets) pkgDescriptions;
    getPackageTargets = pkg: builtins.mapAttrs (_: target: self.getPackageTarget {
      inherit target;
      buildInputs = map (dep: pkgDerivations.${dep}.${target.target}) target.dependencies;
    }) pkg.target;
    pkgRenames = pkgDerivations // mapAttrs (_: { to }: pkgDerivations.${to}) manifest.renames;
  in pkgRenames;

  # The packages available usually are:
  #   cargo, rust-analysis, rust-docs, rust-src, rust-std, rustc, and
  #   rust, which aggregates them in one package.
  manifestTargets = { lib }: with lib; manifestPath: let
    manifest = fromTOML (builtins.readFile manifestPath);
    pkgDescriptions = mapAttrs (pname: pkg: pkg // {
      target = mapAttrs (annotateTarget pname pkg) pkg.target;
    }) manifest.pkg;
    pkgDerivations = self.manifestDerivationsFor { inherit manifest pkgDescriptions; };
    targets = concatLists (mapAttrsToList packageTargets pkgDerivations);
    #pkgVersion = self.lib.replaceStrings [" " "(" ")"] ["-" "" ""];
    pkgVersion = version: let
      version' = builtins.match "([^ ]*) [(]([^ ]*) ([^ ]*)[)]" version;
    in if version == "" then null else "${elemAt version' 0}-${elemAt version' 2}-${elemAt version' 1}";
    disambiguatePkg = pname: target: {
      rust-std = "rust-std-${target}";
      rust-analysis = "rust-analysis-${target}";
    }.${pname} or pname;
    annotateTarget = pname: pkg: targetName: target: target // {
      pkg = pname;
      version = pkgVersion pkg.version;
      target = targetName;
      name = disambiguatePkg pname targetName;
      components = pkgRefAttrs (map (ext: annotateComponent (pkgRef ext)) target.components or []);
      extensions = pkgRefAttrs (map (ext: annotateExtension targetName (pkgRef ext)) target.extensions or []);
      dependencies =
        optional (any (p: p == pname) ["llvm-tools-preview" "miri-preview" "clippy-preview" "rls-preview"]) "rustc";
    };
    annotateComponent = comp: comp // {
      output = comp.name;
    };
    annotateExtension = targetName: ext: ext // {
      embedded = ext.name != "rust-src" && (ext.name == ext.pkg || ext.target == target || ext.target == "*");
    };
    pkgRefAttrs = pkgs: listToAttrs (map (pkg: nameValuePair pkg.name pkg) pkgs);
    pkgRef = { pkg, target }: let
      pkgRef = pkgDescriptions.${pkg}.target;
    in pkgRef.${target} or pkgRef."*";
    packageTargets = pname: targets: mapAttrsToList (target: drv: {
      ${target}.${pname} = drv;
    }) targets;
    target = foldl
      (recursiveUpdateUntil (path: l: r: length path > 1))
      {}
      targets;
    targetForPlatform = platform: (
      target.${self.rustTargetFor platform}
      or (builtins.trace "WARN: Rust binary distribution does not support ${platform.config}" {})
      // target."*" or {});
  in {
    inherit targetForPlatform;
    # the below are the inverse of each other, indexed by either target name or package name:
    targets = target; # targets = { target1 = { packageName = <drv>; package2 = <drv>; }; "*" = { packageName = ... }; }
    pkgs = pkgDerivations; # pkgs = { packageName = { target1 = <drv>; "*" = <drv>; etc }; }
  };
}
