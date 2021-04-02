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
      "1.44.0" = "17m0lyjx20wlgfp6szsnm17q96jfl0d1iv9pqmxlad5r2msnybyc";
      "1.44.1" = "0qp2gc5dm92wzrh6b2mqajdd1lplpl16l5f7km7d6hyx82brm3ij";
      "1.45.0" = "1nbalj41d74bqkhwd506fsqrv4iyrwi2as39ymy7aixsgl6sy18l";
      "1.45.1" = "0v9hcdlrzccydx6ly1niac5scnkzpm9ppqgyljpbv0zviazry558";
      "1.45.2" = "0yvh2ck2vqas164yh01ggj4ckznx04blz3jgbkickfgjm18y269j";
      "1.46.0" = "1sm9g2vkzm8a6w35rrwngnzac28ryszbzwl5y5wrj4qxlmjxw8n5";
      "1.47.0" = "1hkisci4as93hx8ybf13bmxkj9jsvd4a9ilvjmw6n64w4jkc1nk9";
      "1.48.0" = "0b56h3gh577wv143ayp46fv832rlk8yrvm7zw1dfiivifsn7wfzg";
      "1.49.0" = "0swxyj65fkc5g9kpsc7vzdwk5msjf6csj3l5zx4m0xmd2587ca18";
      "1.50.0" = "0l6np7qpx6237ihqz0xdqhainx1pc6x6vfmmffz0hi3p2jggyi9y";
      "1.51.0" = "14qhjdqr2b4z7aasrcn6kxzj3l7fygx4mpa5d4s5d56l62sllhgq";
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
