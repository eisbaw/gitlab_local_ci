{ lib
, stdenv
, ruby
}:

stdenv.mkDerivation rec {
  pname = "gitlab-ci-cli";
  version = "0.1.0";

  src = lib.cleanSourceWith {
    src = ./.;
    filter = path: type:
      let
        baseName = baseNameOf path;
        relPath = lib.removePrefix (toString ./. + "/") (toString path);

        # Include lib/ and bin/ directories and their contents
        isLibOrBin = lib.hasPrefix "lib/" relPath || lib.hasPrefix "bin/" relPath ||
                     relPath == "lib" || relPath == "bin";

        # Exclude specific directories
        isGitlab = lib.hasPrefix "gitlab/" relPath;
        isCoverage = lib.hasPrefix "coverage/" relPath;
        isTestProjects = lib.hasPrefix "test_ci_projects/" relPath;
        isSpec = lib.hasPrefix "spec/" relPath;
        isGitDir = baseName == ".git";
        isDocs = lib.hasPrefix "docs/" relPath;
        isRunners = lib.hasPrefix "runners/" relPath;
      in
        # Include lib/ and bin/, exclude everything else we don't need
        isLibOrBin && !(isGitlab || isCoverage || isTestProjects || isGitDir);
  };

  buildInputs = [ ruby ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # Create directory structure
    mkdir -p $out/bin
    mkdir -p $out/share/gitlab_ci_cli

    # Copy library files preserving structure
    cp -r lib $out/share/gitlab_ci_cli/

    # Create wrapper script that sets up load path correctly
    cat > $out/bin/gitlab_ci_cli <<'EOF'
#!${ruby}/bin/ruby
# frozen_string_literal: true

# Add lib directory to load path
$LOAD_PATH.unshift File.join(__dir__, '..', 'share', 'gitlab_ci_cli', 'lib')

require 'gitlab_ci_cli'

# Start CLI
GitlabCiCli::CLI.start(ARGV)
EOF

    chmod +x $out/bin/gitlab_ci_cli

    runHook postInstall
  '';

  meta = with lib; {
    description = "Standalone CLI tool for simulating GitLab CI/CD pipelines locally";
    longDescription = ''
      gitlab_ci_cli is a zero-dependency command-line tool that validates and
      simulates GitLab CI/CD pipelines without requiring a GitLab instance.

      Features:
      - Lint GitLab CI YAML configurations
      - Generate DAG (Directed Acyclic Graph) visualizations
      - Dry-run pipeline simulations with mock runners
      - Zero external gem dependencies (Ruby stdlib only)
      - Fast startup (~0.3s cold start)

      Architecture follows MPED principles: Minimal dependencies, Pragmatic
      design, Effective development, Data-driven decisions.
    '';
    homepage = "https://github.com/mped/gitlab_ci_cli";
    license = licenses.asl20;
    maintainers = with maintainers; [ ];
    platforms = platforms.unix;
    mainProgram = "gitlab_ci_cli";
  };
}
