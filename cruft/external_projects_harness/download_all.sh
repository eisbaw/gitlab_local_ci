#!/usr/bin/env bash
set -e

echo "Downloading external GitLab CI files..."

# GitLab itself - complex multi-stage
mkdir -p gitlab
curl -sSL "https://gitlab.com/gitlab-org/gitlab/-/raw/master/.gitlab-ci.yml" -o "gitlab/.gitlab-ci.yml" 2>/dev/null && echo "✓ gitlab" || echo "✗ gitlab"

# F-Droid - Android builds
mkdir -p fdroid
curl -sSL "https://gitlab.com/fdroid/fdroidserver/-/raw/master/.gitlab-ci.yml" -o "fdroid/.gitlab-ci.yml" 2>/dev/null && echo "✓ fdroid" || echo "✗ fdroid"

# Inkscape - C++ graphics
mkdir -p inkscape
curl -sSL "https://gitlab.com/inkscape/inkscape/-/raw/master/.gitlab-ci.yml" -o "inkscape/.gitlab-ci.yml" 2>/dev/null && echo "✓ inkscape" || echo "✗ inkscape"

# GNOME Builder
mkdir -p gnome-builder
curl -sSL "https://gitlab.gnome.org/GNOME/gnome-builder/-/raw/main/.gitlab-ci.yml" -o "gnome-builder/.gitlab-ci.yml" 2>/dev/null && echo "✓ gnome-builder" || echo "✗ gnome-builder"

# KiCad - EDA tool
mkdir -p kicad
curl -sSL "https://gitlab.com/kicad/code/kicad/-/raw/master/.gitlab-ci.yml" -o "kicad/.gitlab-ci.yml" 2>/dev/null && echo "✓ kicad" || echo "✗ kicad"

# GStreamer - multimedia
mkdir -p gstreamer
curl -sSL "https://gitlab.freedesktop.org/gstreamer/gstreamer/-/raw/main/.gitlab-ci.yml" -o "gstreamer/.gitlab-ci.yml" 2>/dev/null && echo "✓ gstreamer" || echo "✗ gstreamer"

# Mesa 3D
mkdir -p mesa
curl -sSL "https://gitlab.freedesktop.org/mesa/mesa/-/raw/main/.gitlab-ci.yml" -o "mesa/.gitlab-ci.yml" 2>/dev/null && echo "✓ mesa" || echo "✗ mesa"

# QEMU
mkdir -p qemu
curl -sSL "https://gitlab.com/qemu-project/qemu/-/raw/master/.gitlab-ci.yml" -o "qemu/.gitlab-ci.yml" 2>/dev/null && echo "✓ qemu" || echo "✗ qemu"

# VLC
mkdir -p vlc
curl -sSL "https://gitlab.com/videolan/vlc/-/raw/master/.gitlab-ci.yml" -o "vlc/.gitlab-ci.yml" 2>/dev/null && echo "✓ vlc" || echo "✗ vlc"

# Wireshark
mkdir -p wireshark
curl -sSL "https://gitlab.com/wireshark/wireshark/-/raw/master/.gitlab-ci.yml" -o "wireshark/.gitlab-ci.yml" 2>/dev/null && echo "✓ wireshark" || echo "✗ wireshark"

echo ""
echo "Checking downloaded files:"
for dir in */; do
    if [[ -f "${dir}/.gitlab-ci.yml" ]]; then
        size=$(wc -l "${dir}/.gitlab-ci.yml" | awk '{print $1}')
        echo "  ✓ ${dir%/}: ${size} lines"
    fi
done