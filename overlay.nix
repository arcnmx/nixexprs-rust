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
    path = ./.;

    distChannel = rself.lib.distChannel.override;

    nightly = rself.distChannel { channel = "nightly"; };
    beta = rself.distChannel { channel = "beta"; };
    stable = rself.distChannel { channel = "stable"; };

    releaseHashes = {
      "1.36.0" = "1w2xs3ys2lxhs8l64npb2hmbd4sl0nh22ivlly5xf84q5q2k2djd";
      "1.37.0" = "15619sgfcy703aj5hk2w9lxvn2ccg99rdlhafi52z8rpbg6z32jp";
      "1.38.0" = "1x22rf6ahb4cniykfz3ml7w0hh226pcig154xbcf5cg7j4k72rig";
      "1.39.0" = "0pyps2gjd42r8js9kjglad7mifax96di0xjjmvbdp3izbiin390r";
      "1.40.0" = "151sajlrxj7qdrnpxl7p0r7pwm6vxvd6hq0wa7yy4b5yf8qjrjhb";
      "1.41.0" = "07mp7n4n3cmm37mv152frv7p9q58ahjw5k8gcq48vfczrgm5qgiy";
      "1.41.1" = "0i5bfhn889z8cbg7cj0vq683ka7lq29f2kw9rm1r5ldgzzj59n8a";
      "1.42.0" = "0pddwpkpwnihw37r8s92wamls8v0mgya67g9m8h6p5zwgh4il1z6";
      "1.43.0" = "1y8m8cl4njhmbhichs8hlw6vg91id6asjf180gc6gd41x1a0pypr";
      "1.43.1" = "10srbr109pffvmfnqbqhr5z23wsz021bsy6flbw1pydlwkl3h276";
    };

    releases = lib.mapAttrs (channel: sha256: rself.distChannel {
      inherit channel sha256;
      manifestPath = ./releases + "/channel-rust-${channel}.toml";
    }) rself.releaseHashes;
  });
  fetchcargoPath = super.path + "/pkgs/build-support/rust/fetchcargo.nix";
  fetchCargoTarballPath = super.path + "/pkgs/build-support/rust/fetchCargoTarball.nix";
  fetchcargos = lib.optionalAttrs (builtins.pathExists fetchcargoPath) {
    fetchcargo = self.buildPackages.callPackage fetchcargoPath { }; # TODO: override cargo?
  } // lib.optionalAttrs (builtins.pathExists fetchCargoTarballPath) {
    fetchCargoTarball = self.buildPackages.callPackage fetchCargoTarballPath { }; # TODO: override cargo?
  };
in fetchcargos // {
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
