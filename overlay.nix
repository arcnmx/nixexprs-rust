self: super: with super.lib; let
  lib = super.lib.extend (import ./lib/overlay.nix);
  impure = builtins ? currentSystem;
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

    ${if impure then "nightly" else null} = rself.distChannel { channel = "nightly"; };
    ${if impure then "beta" else null} = rself.distChannel { channel = "beta"; };
    stable = if impure
      then rself.distChannel { channel = "stable"; }
      else rself.latest;

    unstable = rself.distChannel {
      # pinned from https://rust-lang.github.io/rustup-components-history/
      channel = "nightly";
      date = "2025-07-16";
      sha256 = "sha256-3ZSJYswbGJ/c8dSUEuDPJD1D1SCgGjHlg97gF8LtbAU=";
    };

    latest = let
      isStable = name: ch: let
        channel = ch.channel or name;
      in ! lib.hasInfix "-beta" channel;
    in rself.releases.${lib.last (lib.attrNames (lib.filterAttrs isStable rself.releases))};

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
      "1.52.0" = "0qzaq3hsxh7skxjix4d4k38rv0cxwwnvi32arg08p11cxvpsmikx";
      "1.52.1" = "157iggldvb9lcr45zsld6af63yp370f3hyswcb0zwjranrg69r79";
      "1.53.0" = "1p4vxwv28v7qmrblnvp6qv8dgcrj8ka5c7dw2g2cr3vis7xhflaa";
      "1.54.0" = "1b866r7slk1sy55sfq3c5zfxi5r17vzlbram8zn4xhpp44kc5myq";
      "1.55.0" = "16lskw8z89v4m5dwc7qhfy414a616glcwz7p0nn4xgn9x88jblhw";
      "1.56.0" = "0swglfa63i14fpgg98agx4b5sz0nckn6phacfy3k6imknsiv8mrg";
      "1.57.0" = "0rqgx90k9lhfwaf63ccnm5qskzahmr4q18i18y6kdx48y26w3xz8";
      "1.58.0" = "16g8i6in0q8kas83xdhsy9z78mhrpr3d1v13azgq3ymxdi56j03r";
      "1.59.0" = "0dbar9p8spldj16zy7vahg9dq31vlkbrp40vq5f1q167cmjik1g0";
      "1.60.0" = "1j7bpwykirbgn40ng83gblfnrrmias44szph3c4xx5y4p7xjdn52";
      "1.61.0" = "0s03ranld2mv8a03sdlzlybhzy6dfhbz6ylwp50b8v1cr8g39fm2";
      "1.62.0" = "sha256-AoqjoLifz8XrZWP7piauFfWCvhzPMLKxfv57h6Ng1oM=";
      "1.62.1" = "sha256-Et8XFyXhlf5OyVqJkxrmkxv44NRN54uU2CLUTZKUjtM=";
      "1.63.0" = "sha256-KXx+ID0y4mg2B3LHp7IyaiMrdexF6octADnAtFIOjrY=";
      "1.64.0" = "sha256-8len3i8oTwJSOJZMosGGXHBL5BVuGQnWOT2St5YAUFU=";
      "1.65.0" = "sha256-DzNEaW724O8/B8844tt5AVHmSjSQ3cmzlU4BP90oRlY=";
      "1.66.0" = "sha256-S7epLlflwt0d1GZP44u5Xosgf6dRrmr8xxC+Ml2Pq7c=";
      "1.67.0" = "sha256-riZUc+R9V35c/9e8KJUE+8pzpXyl0lRXt3ZkKlxoY0g=";
      "1.67.1" = "sha256-S4dA7ne2IpFHG+EnjXfogmqwGyDFSRWFnJ8cy4KZr1k=";
      "1.68.0" = "sha256-JvgrOEGMM0N+6Vsws8nUq0W/PJPxkf5suZjgEtAzG6I=";
      "1.68.1" = "sha256-0eo5Tq1ZOs7l/SISF8Fegrvvq9dZ1lZzy0yUZVlu2VQ=";
      "1.68.2" = "sha256-4vetmUhTUsew5FODnjlnQYInzyLNyDwocGa4IvMk3DM=";
      "1.69.0" = "sha256-eMJethw5ZLrJHmoN2/l0bIyQjoTX1NsvalWSscTixpI=";
      "1.70.0" = "sha256-gdYqng0y9iHYzYPAdkC/ka3DRny3La/S5G8ASj0Ayyc=";
      "1.71.0" = "sha256-ks0nMEGGXKrHnfv4Fku+vhQ7gx76ruv6Ij4fKZR3l78=";
      "1.71.1" = "sha256-R0F0Risbr74xg9mEYydyebx/z0Wu6HI0/KWwrV30vZo=";
      "1.72.0" = "sha256-Q9UgzzvxLi4x9aWUJTn+/5EXekC98ODRU1TwhUs9RnY=";
      "1.72.1" = "sha256-dxE7lmCFWlq0nl/wKcmYvpP9zqQbBitAQgZ1zx9Ooik=";
      "1.73.0" = "sha256-rLP8+fTxnPHoR96ZJiCa/5Ans1OojI7MLsmSqR2ip8o=";
      "1.74.0" = "sha256-U2yfueFohJHjif7anmJB5vZbpP7G6bICH4ZsjtufRoU=";
      "1.74.1" = "sha256-PjvuouwTsYfNKW5Vi5Ye7y+lL7SsWGBxCtBOOm2z14c=";
      "1.75.0" = "sha256-SXRtAuO4IqNOQq+nLbrsDFbVk+3aVA8NNpSZsKlVH/8=";
      "1.76.0" = "sha256-e4mlaJehWBymYxJGgnbuCObVlqMlQSilZ8FljG9zPHY=";
      "1.77.0" = "sha256-+syqAd2kX8KVa8/U2gz3blIQTTsYYt3U63xBWaGOSc8=";
      "1.77.1" = "sha256-3St/9/UKo/6lz2Kfq2VmlzHyufduALpiIKaaKX4Pq0g=";
      "1.77.2" = "sha256-7QfkHty6hSrgNM0fspycYkRcB82eEqYa4CoAJ9qA3tU=";
      "1.78.0" = "sha256-opUgs6ckUQCyDxcB9Wy51pqhd0MPGHUVbwRKKPGiwZU=";
      "1.79.0" = "sha256-Ngiz76YP4HTY75GGdH2P+APE/DEIx2R/Dn+BwwOyzZU=";
      "1.80.0" = "sha256-6eN/GKzjVSjEhGO9FhWObkRFaE1Jf+uqMSdQnb8lcB4=";
      "1.80.1" = "sha256-3jVIIf5XPnUU1CRaTyAiO0XHVbJl12MSx3eucTXCjtE=";
      "1.81.0" = "sha256-VZZnlyP69+Y3crrLHQyJirqlHrTtGTsyiSnZB8jEvVo=";
      "1.82.0" = "sha256-yMuSb5eQPO/bHv+Bcf/US8LVMbf/G/0MSfiPwBhiPpk=";
      "1.83.0" = "sha256-s1RPtyvDGJaX/BisLT+ifVfuhDT1nZkZ1NcK8sbwELM=";
      "1.84.0" = "sha256-lMLAupxng4Fd9F1oDw8gx+qA0RuF7ou7xhNU8wgs0PU=";
      "1.84.1" = "sha256-vMlz0zHduoXtrlu0Kj1jEp71tYFXyymACW8L4jzrzNA=";
      "1.85.0" = "sha256-AJ6LX/Q/Er9kS15bn9iflkUwcgYqRQxiOIL2ToVAXaU=";
      "1.85.1" = "sha256-Hn2uaQzRLidAWpfmRwSRdImifGUCAb9HeAqTYFXWeQk=";
      "1.86.0" = "sha256-X/4ZBHO3iW0fOenQ3foEvscgAPJYl2abspaBThDOukI=";
      "1.87.0" = "sha256-KUm16pHj+cRedf8vxs/Hd2YWxpOrWZ7UOrwhILdSJBU=";
      "1.88.0" = "sha256-Qxt8XAuaUR2OMdKbN4u8dBJOhSHxS+uS06Wl9+flVEk=";
      "1.89.0" = {
        channel = "1.89.0-beta.4";
        sha256 = "sha256-RGzp/3F8wpYf/kKl6O8ZZfVn97ma83ZiEaXeObaHJoA=";
      };
    };

    releases = lib.mapAttrs (name: ch: let
      channel = ch.channel or name;
      sha256 = ch.sha256 or (toString ch);
    in rself.distChannel {
      inherit channel sha256;
      manifestPath = ./releases + "/channel-rust-${channel}.toml";
    }) rself.releaseHashes;
  });
in {
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
}
