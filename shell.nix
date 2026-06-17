# shell.nix - thin compat shim that re-uses the pinned nixpkgs from flake.lock
# so `nix-shell` and `nix develop` resolve to the same store path.
let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  locked = lock.nodes.nixpkgs.locked;
  src = fetchTarball {
    url = "https://github.com/${locked.owner}/${locked.repo}/archive/${locked.rev}.tar.gz";
    sha256 = locked.narHash;
  };
  pkgs = import src { };
in
pkgs.mkShell {
  buildInputs = with pkgs; [
    # Ruby environment (ruby_3_3 ships its own vendor bundler; do NOT add
    # pkgs.bundler — in nixos-26.05 it targets Ruby 3.4 gems/3.4.0 paths
    # and crashes against ruby_3_3 gems/3.3.0).
    ruby_3_3

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
