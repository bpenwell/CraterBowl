#!/usr/bin/env bash
# Install the software renderer from the Ubuntu 24.04 Actions image's own archives.
set -euo pipefail

ubuntu_sources="${1:-/etc/apt/sources.list.d/ubuntu.sources}"
if [[ ! -r "$ubuntu_sources" ]]; then
  echo "Ubuntu APT sources not found: $ubuntu_sources" >&2
  exit 2
fi

# Scope both operations to the Ubuntu archive definitions for this job.
apt_sources=(-o "Dir::Etc::SourceList=$ubuntu_sources" -o Dir::Etc::SourceParts=-)
sudo apt-get "${apt_sources[@]}" update --error-on=any
sudo apt-get "${apt_sources[@]}" install -y xvfb xauth libgl1-mesa-dri libgl1
