#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo ""
    echo -e "${YELLOW}  Requesting administrator access...${NC}"
    exec sudo "$0" "$@"
fi

INSTALL_PATH="/Applications/Zenith.app"
GITHUB_REPO="Boldmoon/zenith-release"
TEMP_DIR=$(mktemp -d)

cleanup() {
    if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
        hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
    fi
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

echo ""
echo -e "${CYAN}${BOLD}"
echo "  +---------------------------------------+"
echo "  |         ZENITH INSTALLER              |"
echo "  |   Hardware Development Assistant      |"
echo "  +---------------------------------------+"
echo -e "${NC}"

ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    ASSET_PATTERN="arm64.dmg"
    ARCH_NAME="Apple Silicon"
else
    ASSET_PATTERN="x64.dmg"
    ARCH_NAME="Intel"
fi

echo -e "  ${BOLD}System:${NC} macOS ($ARCH_NAME)"
echo ""

if [ "$ARCH" = "arm64" ]; then
    if ! arch -x86_64 /usr/bin/true 2>/dev/null; then
        echo -e "  ${YELLOW}Rosetta 2 is required but not installed.${NC}"
        echo ""
        echo -n "  Press ENTER to install Rosetta 2, or Ctrl+C to cancel: "
        read -r
        echo ""
        echo -e "  Installing Rosetta 2..."
        softwareupdate --install-rosetta --agree-to-license
        echo ""
    fi
fi

echo -e "  [1/5] Fetching latest release..."

MAX_RETRIES=3
RETRY_DELAY=2
RELEASE_JSON=""

for i in $(seq 1 $MAX_RETRIES); do
    RELEASE_JSON=$(curl -s --connect-timeout 10 --max-time 30 "https://api.github.com/repos/$GITHUB_REPO/releases/latest" 2>/dev/null)
    if [ -n "$RELEASE_JSON" ] && ! echo "$RELEASE_JSON" | grep -q "rate limit" && echo "$RELEASE_JSON" | grep -q "tag_name"; then
        break
    fi
    if [ $i -eq $MAX_RETRIES ]; then
        echo -e "  ${RED}ERROR: Failed to fetch release information after $MAX_RETRIES attempts${NC}"
        echo -e "  ${DIM}Please check your internet connection and try again.${NC}"
        echo -e "  ${DIM}Or visit: https://github.com/$GITHUB_REPO/releases${NC}"
        exit 1
    fi
    echo -e "        ${DIM}Attempt $i failed, retrying in ${RETRY_DELAY}s...${NC}"
    sleep $RETRY_DELAY
    RETRY_DELAY=$((RETRY_DELAY * 2))
done

VERSION=$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | cut -d '"' -f 4)
DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep "browser_download_url.*$ASSET_PATTERN" | head -1 | cut -d '"' -f 4)

if [ -z "$DOWNLOAD_URL" ]; then
    echo -e "  ${RED}ERROR: Failed to find download URL for $ARCH_NAME${NC}"
    echo -e "  ${DIM}Please check https://github.com/$GITHUB_REPO/releases${NC}"
    exit 1
fi

echo -e "        ${GREEN}Found version: $VERSION${NC}"
echo ""

DMG_PATH="$TEMP_DIR/Zenith.dmg"
echo -e "  [2/5] Downloading Zenith..."
echo -e "        ${DIM}This may take a few minutes...${NC}"
if ! curl -L --connect-timeout 10 --max-time 600 -o "$DMG_PATH" "$DOWNLOAD_URL" --progress-bar; then
    echo -e "  ${RED}ERROR: Download failed${NC}"
    exit 1
fi
echo ""

echo -e "  [3/5] Mounting disk image..."
MOUNT_OUTPUT=$(hdiutil attach "$DMG_PATH" -nobrowse -plist 2>&1)
MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | grep -A1 '<key>mount-point</key>' | grep '<string>' | sed 's/.*<string>\(.*\)<\/string>.*/\1/' | head -1)

if [ -z "$MOUNT_POINT" ]; then
    MOUNT_OUTPUT=$(hdiutil attach "$DMG_PATH" -nobrowse 2>&1)
    MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | grep -o '/Volumes/[^"]*' | head -1)
fi

if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
    echo -e "  ${RED}ERROR: Failed to mount disk image${NC}"
    echo -e "  ${DIM}$MOUNT_OUTPUT${NC}"
    exit 1
fi

APP_SOURCE="$MOUNT_POINT/Zenith.app"
if [ ! -d "$APP_SOURCE" ]; then
    APP_SOURCE=$(find "$MOUNT_POINT" -maxdepth 1 -name "*.app" | head -1)
fi

if [ -z "$APP_SOURCE" ] || [ ! -d "$APP_SOURCE" ]; then
    echo -e "  ${RED}ERROR: Could not find Zenith.app in disk image${NC}"
    exit 1
fi

if [ -d "$INSTALL_PATH" ]; then
    echo -e "        Removing previous version..."
    rm -rf "$INSTALL_PATH"
fi

echo -e "  [4/5] Installing to /Applications..."
if ! cp -R "$APP_SOURCE" "/Applications/"; then
    echo -e "  ${RED}ERROR: Failed to copy to /Applications${NC}"
    echo -e "  ${DIM}You may need to run this with sudo or check permissions${NC}"
    exit 1
fi

xattr -dr com.apple.quarantine "$INSTALL_PATH" 2>/dev/null || true

echo -e "  [5/5] Cleaning up..."
hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
MOUNT_POINT=""
rm -rf "$TEMP_DIR"

echo ""
echo -e "${GREEN}${BOLD}"
echo "  +---------------------------------------+"
echo "  |      Installation complete!          |"
echo "  +---------------------------------------+"
echo -e "${NC}"
echo -e "  ${BOLD}Zenith $VERSION${NC} has been installed to /Applications"
echo ""
echo -e "  Launching Zenith..."
echo ""

open "$INSTALL_PATH"
