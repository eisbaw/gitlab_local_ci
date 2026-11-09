#!/usr/bin/env bash
# Script to set up remaining git submodules with shallow clones

echo "Setting up remaining submodules with shallow clones..."

# Array of repositories to add
declare -A repos=(
    ["external_projects/inkscape"]="https://gitlab.com/inkscape/inkscape.git"
    ["external_projects/kicad"]="https://gitlab.com/kicad/code/kicad.git"
    ["external_projects/mastodon"]="https://github.com/mastodon/mastodon.git"
    ["external_projects/mattermost"]="https://github.com/mattermost/mattermost.git"
    ["external_projects/nextcloud"]="https://github.com/nextcloud/server.git"
    ["external_projects/wireguard"]="https://git.zx2c4.com/wireguard-tools"
    ["external_projects/grafana"]="https://github.com/grafana/grafana.git"
)

for path in "${!repos[@]}"; do
    url="${repos[$path]}"
    echo "Adding submodule: $path from $url"

    # Clean up any existing failed attempts
    rm -rf "$path" ".git/modules/$path"
    git config --remove-section "submodule.$path" 2>/dev/null || true

    # Add submodule with depth=1 for faster cloning
    if ! git submodule add --depth 1 "$url" "$path"; then
        echo "Warning: Failed to add $path, trying alternative..."
        # Try without depth limit if shallow clone fails
        git submodule add "$url" "$path" || echo "Error: Could not add $path"
    fi
done

echo "Initializing and updating submodules..."
git submodule update --init --recursive --depth 1

echo "Submodule setup complete!"
echo ""
echo "Current submodules:"
git submodule status