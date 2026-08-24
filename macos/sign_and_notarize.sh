#!/bin/bash
#
# Sign and optionally notarize Ghostty macOS application bundle.
# Compatible with local developer workflows, custom signing infra, and CI/CD.
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Colour

APP_PATH=""
ENTITLEMENTS="Ghostty.entitlements"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-${MACOS_CERTIFICATE_NAME:-}}"
NOTARIZE="${NOTARIZE:-auto}" # auto, true, false
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-${NOTARIZE_KEYCHAIN_PROFILE:-}}"
API_KEY_PATH="${ASC_API_KEY_PATH:-${ASC_KEY_FILE:-}}"
API_KEY_ID="${ASC_API_KEY_ID:-}"
API_ISSUER="${ASC_API_ISSUER:-}"
APPLE_ID="${APPLE_ID:-}"
NOTARIZE_PASSWORD="${NOTARIZE_PASSWORD:-}"
TEAM_ID="${SIGNING_TEAM_ID:-${TEAM_ID:-}}"

usage() {
    cat << EOF
Usage: $0 APP_PATH [OPTIONS]

Options:
  --identity NAME            Code sign identity (default: auto-detected Developer ID Application or Apple Development)
  --entitlements PATH        Path to entitlements file (default: Ghostty.entitlements)
  --notarize                 Force notarization
  --no-notarize              Skip notarization
  --keychain-profile NAME    Keychain profile for notarytool
  --api-key PATH             Path to App Store Connect API key .p8 file
  --api-key-id ID            App Store Connect API key ID
  --api-issuer UUID          App Store Connect API issuer UUID
  --apple-id EMAIL           Apple ID for notarization
  --password PASS            App-specific password for notarization
  --team-id ID               Apple Developer Team ID
  -h, --help                 Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --identity)
            SIGNING_IDENTITY="$2"
            shift 2
            ;;
        --entitlements)
            ENTITLEMENTS="$2"
            shift 2
            ;;
        --notarize)
            NOTARIZE=true
            shift
            ;;
        --no-notarize)
            NOTARIZE=false
            shift
            ;;
        --keychain-profile)
            KEYCHAIN_PROFILE="$2"
            shift 2
            ;;
        --api-key)
            API_KEY_PATH="$2"
            shift 2
            ;;
        --api-key-id)
            API_KEY_ID="$2"
            shift 2
            ;;
        --api-issuer)
            API_ISSUER="$2"
            shift 2
            ;;
        --apple-id)
            APPLE_ID="$2"
            shift 2
            ;;
        --password)
            NOTARIZE_PASSWORD="$2"
            shift 2
            ;;
        --team-id)
            TEAM_ID="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo -e "${RED}Error: Unknown option $1${NC}" >&2
            exit 1
            ;;
        *)
            if [[ -z "$APP_PATH" ]]; then
                APP_PATH="$1"
            else
                echo -e "${RED}Error: Unexpected argument $1${NC}" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$APP_PATH" ]]; then
    echo -e "${RED}Error: APP_PATH is required${NC}" >&2
    usage >&2
    exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo -e "${RED}Error: App bundle not found at $APP_PATH${NC}" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"

# Resolve entitlements path if relative
if [[ ! -f "$ENTITLEMENTS" ]]; then
    if [[ -f "${SCRIPT_DIR}/${ENTITLEMENTS}" ]]; then
        ENTITLEMENTS="${SCRIPT_DIR}/${ENTITLEMENTS}"
    elif [[ -f "${PROJECT_ROOT}/macos/${ENTITLEMENTS}" ]]; then
        ENTITLEMENTS="${PROJECT_ROOT}/macos/${ENTITLEMENTS}"
    fi
fi

# -----------------------------------------------------------------------------
# 1. Discover or validate Signing Identity
# -----------------------------------------------------------------------------
if [[ -z "$SIGNING_IDENTITY" ]]; then
    # Try finding Developer ID Application first
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application:" | head -n 1 | sed -E 's/^[[:space:]]*[0-9]+\)[[:space:]]+[0-9A-Fa-f]+[[:space:]]+"([^"]+)".*/\1/' || true)
    if [[ -z "$SIGNING_IDENTITY" ]]; then
        # Fallback to Apple Development identity if Developer ID not found
        SIGNING_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development:" | head -n 1 | sed -E 's/^[[:space:]]*[0-9]+\)[[:space:]]+[0-9A-Fa-f]+[[:space:]]+"([^"]+)".*/\1/' || true)
    fi
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo -e "${YELLOW}Warning: No valid code signing identity found. Using ad-hoc signature (-).${NC}"
    SIGNING_IDENTITY="-"
fi

echo -e "${BLUE}Code signing identity:${NC} ${SIGNING_IDENTITY}"

# -----------------------------------------------------------------------------
# 2. Codesign embedded frameworks, plugins, and helper binaries
# -----------------------------------------------------------------------------
echo -e "${YELLOW}Code signing bundle contents...${NC}"

sign_item() {
    local item="$1"
    local extra_flags="${2:-}"
    if [[ -e "$item" ]]; then
        echo "  Signing $(basename "$item")..."
        /usr/bin/codesign --force --options runtime --timestamp \
            -s "$SIGNING_IDENTITY" ${extra_flags} "$item" 2>&1
    fi
}

# Sign Sparkle framework components if present
SPARKLE_FRAMEWORK="${APP_PATH}/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
    sign_item "${SPARKLE_FRAMEWORK}/Versions/B/XPCServices/Downloader.xpc"
    sign_item "${SPARKLE_FRAMEWORK}/Versions/B/XPCServices/Installer.xpc"
    sign_item "${SPARKLE_FRAMEWORK}/Versions/B/Autoupdate"
    sign_item "${SPARKLE_FRAMEWORK}/Versions/B/Updater.app"
    sign_item "${SPARKLE_FRAMEWORK}"
fi

# Sign GhosttyKit framework if present
GHOSTTYKIT_FRAMEWORK="${APP_PATH}/Contents/Frameworks/GhosttyKit.framework"
if [[ -d "$GHOSTTYKIT_FRAMEWORK" ]]; then
    sign_item "${GHOSTTYKIT_FRAMEWORK}"
fi

# Sign any additional dynamic libraries or frameworks
if [[ -d "${APP_PATH}/Contents/Frameworks" ]]; then
    for fw in "${APP_PATH}/Contents/Frameworks"/*; do
        if [[ -d "$fw" && "$fw" != "$SPARKLE_FRAMEWORK" && "$fw" != "$GHOSTTYKIT_FRAMEWORK" ]]; then
            sign_item "$fw"
        fi
    done
fi

# Sign Plugins if present
if [[ -d "${APP_PATH}/Contents/PlugIns" ]]; then
    for plugin in "${APP_PATH}/Contents/PlugIns"/*; do
        if [[ -d "$plugin" ]]; then
            sign_item "$plugin"
        fi
    done
fi

# -----------------------------------------------------------------------------
# 3. Codesign the main application bundle
# -----------------------------------------------------------------------------
echo -e "${YELLOW}Code signing main application bundle...${NC}"
ENTITLEMENTS_FLAG=""
if [[ -f "$ENTITLEMENTS" ]]; then
    ENTITLEMENTS_FLAG="--entitlements ${ENTITLEMENTS}"
fi

/usr/bin/codesign --force --options runtime --timestamp \
    -s "$SIGNING_IDENTITY" ${ENTITLEMENTS_FLAG} "$APP_PATH" 2>&1

echo -e "${GREEN}✓ Code signing complete${NC}"

# Verify code signature
codesign --verify --deep --strict "$APP_PATH" 2>&1 || true

# -----------------------------------------------------------------------------
# 4. Notarization
# -----------------------------------------------------------------------------
# If identity is ad-hoc or Apple Development, notarization is not supported by Apple
if [[ "$SIGNING_IDENTITY" == "-" || "$SIGNING_IDENTITY" == Apple\ Development* ]]; then
    if [[ "$NOTARIZE" == "true" ]]; then
        echo -e "${RED}Error: Notarization requires a 'Developer ID Application' certificate.${NC}" >&2
        exit 1
    else
        echo -e "${BLUE}Skipping notarization (identity is not Developer ID Application).${NC}"
        exit 0
    fi
fi

# Auto-discover AuthKey if not set
if [[ -z "$API_KEY_PATH" && -z "$KEYCHAIN_PROFILE" && -z "$APPLE_ID" ]]; then
    for search_dir in "$HOME/.appstoreconnect/private_keys" "$HOME/.private_keys" "$HOME/Downloads" "./private_keys"; do
        if [[ -d "$search_dir" ]]; then
            found_key=$(find "$search_dir" -maxdepth 1 -name "AuthKey_*.p8" 2>/dev/null | head -n 1 || true)
            if [[ -n "$found_key" && -f "$found_key" ]]; then
                API_KEY_PATH="$found_key"
                filename=$(basename "$found_key")
                if [[ -z "$API_KEY_ID" && "$filename" =~ AuthKey_([A-Za-z0-9]+)\.p8 ]]; then
                    API_KEY_ID="${BASH_REMATCH[1]}"
                fi
                break
            fi
        fi
    done
fi

# Build notary authentication arguments
NOTARIZE_AUTH_ARGS=()
if [[ -n "$API_KEY_PATH" && -n "$API_KEY_ID" && -n "$API_ISSUER" ]]; then
    NOTARIZE_AUTH_ARGS=(--key "$API_KEY_PATH" --key-id "$API_KEY_ID" --issuer "$API_ISSUER")
elif [[ -n "$KEYCHAIN_PROFILE" ]]; then
    NOTARIZE_AUTH_ARGS=(--keychain-profile "$KEYCHAIN_PROFILE")
elif [[ -n "$APPLE_ID" && -n "$NOTARIZE_PASSWORD" && -n "$TEAM_ID" ]]; then
    NOTARIZE_AUTH_ARGS=(--apple-id "$APPLE_ID" --password "$NOTARIZE_PASSWORD" --team-id "$TEAM_ID")
fi

if [[ ${#NOTARIZE_AUTH_ARGS[@]} -eq 0 ]]; then
    if [[ "$NOTARIZE" == "true" ]]; then
        echo -e "${RED}Error: Notarization requested but no valid credentials provided.${NC}" >&2
        echo "Provide --keychain-profile, or --api-key / --api-key-id / --api-issuer, or --apple-id / --password / --team-id" >&2
        exit 1
    else
        echo -e "${BLUE}No notarization credentials found. Skipping notarization.${NC}"
        exit 0
    fi
fi

# Package app into zip archive for submission
ZIP_PATH="${APP_PATH%.app}.zip"
rm -f "$ZIP_PATH"
echo -e "${YELLOW}Archiving app for notarization...${NC}"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo -e "${YELLOW}Submitting to Apple Notary Service...${NC}"
echo "  (This may take a minute or two)"

SUBMIT_OUTPUT=$(xcrun notarytool submit "$ZIP_PATH" "${NOTARIZE_AUTH_ARGS[@]}" --wait 2>&1) || true
echo "$SUBMIT_OUTPUT"
rm -f "$ZIP_PATH"

if echo "$SUBMIT_OUTPUT" | grep -q "status: Accepted"; then
    echo -e "${GREEN}✓ Notarization accepted${NC}"
    echo -e "${YELLOW}Stapling ticket to ${APP_PATH}...${NC}"
    xcrun stapler staple "$APP_PATH"
    echo -e "${GREEN}✓ App notarized and stapled successfully!${NC}"
else
    echo -e "${RED}✗ Notarization failed or was rejected${NC}"
    SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep "  id:" | head -n 1 | awk '{print $2}')
    if [[ -n "$SUBMISSION_ID" ]]; then
        echo -e "${YELLOW}Fetching log for submission ${SUBMISSION_ID}...${NC}"
        xcrun notarytool log "$SUBMISSION_ID" "${NOTARIZE_AUTH_ARGS[@]}" || true
    fi
    exit 1
fi
