let overlay = self: super: with super.lib; let
  lib = super.lib.extend (import ./lib);
  rustChannel = lib.makeOrExtend super "rustChannel" (rself: rsuper: {
    lib = lib.makeOrExtend rsuper "lib" (lself: lsuper: import ./build-support {
      self = lself; super = lsuper;
      buildSelf = (self.buildPackages.rustChannel or (self.buildPackages.extend overlay).rustChannel).lib;
      targetSelf = (self.targetPackages.rustChannel or (self.targetPackages.extend overlay).rustChannel).lib;
      pkgs = self;
      inherit lib;
    });
    pkgs = self;

    distChannel = rself.lib.distChannel.override;

    nightly = rself.distChannel { channel = "nightly"; };
    beta = rself.distChannel { channel = "beta"; };
    stable = rself.distChannel { channel = "stable"; };

    releaseHashes = {
      "1.36.0" = "1w2xs3ys2lxhs8l64npb2hmbd4sl0nh22ivlly5xf84q5q2k2djd";
      "1.37.0" = "15619sgfcy703aj5hk2w9lxvn2ccg99rdlhafi52z8rpbg6z32jp";
      "1.38.0" = "1x22rf6ahb4cniykfz3ml7w0hh226pcig154xbcf5cg7j4k72rig";
      "1.39.0" = "0pyps2gjd42r8js9kjglad7mifax96di0xjjmvbdp3izbiin390r";
    };

    releases = lib.mapAttrs (channel: sha256: rself.distChannel {
      inherit channel sha256;
      manifestPath = ./releases + "/channel-rust-${channel}.toml";
    }) rself.releaseHashes;
  });
in {
  fetchcargo = self.buildPackages.callPackage (self.path + "/pkgs/build-support/rust/fetchcargo.nix") { }; # TODO: override cargo?

  inherit rustChannel lib;

  # For backward compatibility
  rustChannels = self.rustChannel;

  # Set of packages which are automagically updated. Do not rely on these for
  # reproducible builds.
  latest = lib.makeOrExtend super "latest" (lself: lsuper: {
    rustChannels = lib.makeOrExtend lsuper "rustChannels" (_: _: {
      inherit (self.rustChannel) nightly beta stable;
    });
  });

  rustChannelOf = self.rustChannel.distChannel;

  rustChannelOfTargets = channel: date: targets:
    (self.rustChannel.distChannel {
      inherit channel date;
    }).extend (rself: rsuper: {
      sysroot-std = rsuper.sysroot-std ++ map (target:
        rself.manifest.targets.${target}.rust-std
      ) targets;
    });
}; in overlay
