#!/usr/bin/env bash
# Preflight: verify the tools the kit needs (bash, curl, jq) are on PATH.
# On a miss, print the exact install command for this platform and exit non-zero,
# so a build fails loudly here instead of dying mid-run with "jq: command not found".
# Kept to pre-4.0 bash so it runs under macOS's stock bash 3.2.
set -u

missing=""
for tool in bash curl jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    missing="$missing $tool"
  fi
done

if [ -z "$missing" ]; then
  echo "OK: bash, curl, and jq are all installed."
  exit 0
fi

echo "MISSING:$missing"
echo "The build-agent scripts need these. Install them, then re-run this check."
echo

os="$(uname -s 2>/dev/null || echo unknown)"
if [ "$os" = "Darwin" ]; then
  echo "macOS (Homebrew):"
  echo "  brew install${missing}"
  echo "  (no Homebrew? install it from https://brew.sh )"
elif [ "$os" = "Linux" ]; then
  if command -v apt-get >/dev/null 2>&1; then
    echo "Debian/Ubuntu:"
    echo "  sudo apt-get update && sudo apt-get install -y${missing}"
  elif command -v dnf >/dev/null 2>&1; then
    echo "Fedora/RHEL:"
    echo "  sudo dnf install -y${missing}"
  elif command -v yum >/dev/null 2>&1; then
    echo "RHEL/CentOS:"
    echo "  sudo yum install -y${missing}"
  elif command -v apk >/dev/null 2>&1; then
    echo "Alpine:"
    echo "  sudo apk add${missing}"
  elif command -v pacman >/dev/null 2>&1; then
    echo "Arch:"
    echo "  sudo pacman -S${missing}"
  else
    echo "Install${missing} with your system package manager. jq: https://jqlang.org/download/"
  fi
else
  echo "Install${missing} with your system package manager. jq: https://jqlang.org/download/"
fi
exit 1
