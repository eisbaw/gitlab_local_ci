{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    # Ruby environment
    ruby_3_3
    bundler

    # Required tools
    git
    graphviz
    just

    # Native build dependencies for GitLab gems
    cmake
    pkg-config
    libgit2
    krb5
    openssl
    icu
    postgresql
    zlib

    # Optional development tools
    gnumake
  ];

  shellHook = ''
    export GEM_HOME="$PWD/.gems"
    export PATH="$GEM_HOME/bin:$PATH"
  '';
}
