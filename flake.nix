{
  description = "gitlab_ci_local - Local GitLab CI pipeline simulator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              # Ruby environment (ruby_3_3 ships its own vendor bundler;
              # do NOT add pkgs.bundler — in nixos-26.05 it targets Ruby 3.4
              # gems/3.4.0 paths and crashes against ruby_3_3 gems/3.3.0).
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
          };
        });
    };
}
