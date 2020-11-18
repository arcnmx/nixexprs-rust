# nixexprs-rust

An alternative to the [Mozilla nixpkgs overlay](https://github.com/mozilla/nixpkgs-mozilla) for
working with the binary Rust releases on Nix{,OS}.

```bash
export NIX_PATH=$NIX_PATH:rust=https://github.com/arcnmx/nixexprs-rust/archive/master.tar.gz
nix-shell '<rust>' -A nightly.cargo --run "cargo --version"
```

Currently everything is undocumented, so [dig through the source](https://github.com/arcnmx/nixexprs-rust/blob/master/build-support/channel.nix)
or check out the [cross-compiling example](https://github.com/arcnmx/nixexprs-rust/blob/master/ci.nix#L74).
