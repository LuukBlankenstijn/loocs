{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  packages = with pkgs; [
    git
    rustc
    cargo
    rustfmt
    go
    autoconf
    automake
    libtool
    zlib
    openssl
  ];
}
