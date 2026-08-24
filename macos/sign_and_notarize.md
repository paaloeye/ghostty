# macOS Code Signing and Notarization Guide

This document describes how code signing and Apple notarization are configured and executed for the Ghostty macOS application.

---

## Overview

When building Ghostty for release (`-Doptimize=ReleaseFast`), Ghostty:
1. Builds the native macOS app using the Xcode **`Release`** configuration with hardened runtime enabled.
2. Code signs embedded frameworks and plugins (`Sparkle.framework`, `GhosttyKit.framework`, `DockTilePlugin.plugin`).
3. Code signs the main `Ghostty.app` bundle using `Ghostty.entitlements` with a timestamp and runtime hardening (`--options runtime`).
4. Creates a temporary `.zip` archive with `ditto` and submits it to Apple's Notary service (`xcrun notarytool submit --wait`).
5. Staples the notarization ticket to the app bundle (`xcrun stapler staple`).

---

## Prerequisites

To code sign and notarize Ghostty, you need:

1. **Code Signing Certificate:**
   - **Developer ID Application** certificate installed in your macOS Keychain (e.g. `"Developer ID Application: Your Company (TEAM_ID)"`).
   - For local development without notarization, an `Apple Development` certificate or ad-hoc signature (`-`) can also be used.

2. **Notarization Credentials:**
   Apple supports three methods for authenticating with `notarytool`:
   - **Keychain Profile (Recommended for local dev):** A stored profile in macOS Keychain.
   - **App Store Connect API Key (Recommended for CI):** A `.p8` private key file, Key ID, and Issuer UUID.
   - **Apple ID + App-Specific Password:** An Apple ID email, app-specific password, and Team ID.

---

## Credential Setup

### 1. Store Credentials in Keychain (One-Time Setup)

To create a named keychain profile for `notarytool`:

```bash
# Using App Store Connect API Key:
xcrun notarytool store-credentials "AC_PASSWORD" \
  --key "/path/to/AuthKey_XXXXXXXXXX.p8" \
  --key-id "XXXXXXXXXX" \
  --issuer "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Or using Apple ID + App-Specific Password:
xcrun notarytool store-credentials "AC_PASSWORD" \
  --apple-id "developer@example.com" \
  --team-id "TEAM_ID"
```

---

## Building with `zig build`

### Standard Release Build (Automatic Signing & Notarization)

When you run `ReleaseFast`, signing and notarization run automatically:

```bash
zig build -Doptimize=ReleaseFast
```

### Passing Notarization Options

```bash
# Using a specific Keychain profile
zig build -Doptimize=ReleaseFast -Dmacos-keychain-profile="AC_PASSWORD"

# Using an App Store Connect API Key
zig build -Doptimize=ReleaseFast \
  -Dmacos-api-key="~/.private_keys/AuthKey_XXXXXXXXXX.p8" \
  -Dmacos-api-key-id="XXXXXXXXXX" \
  -Dmacos-api-issuer="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Explicitly specifying signing identity
zig build -Doptimize=ReleaseFast \
  -Dmacos-codesign-identity="Developer ID Application: Aandra Labs, Inc. (7GM8GVF5V8)"
```

### Code Signing Only (Skip Notarization)

To test a release build locally with hardened runtime without waiting on Apple's notarization servers:

```bash
zig build -Doptimize=ReleaseFast -Dmacos-notarize=false
```

---

## Environment Variables

All parameters can also be configured using environment variables without passing `-D` CLI flags:

| Variable | Description |
| :--- | :--- |
| `SIGNING_IDENTITY` / `MACOS_CERTIFICATE_NAME` | Name or SHA-1 hash of the code signing certificate |
| `KEYCHAIN_PROFILE` / `NOTARIZE_KEYCHAIN_PROFILE` | Name of the stored `notarytool` profile |
| `ASC_API_KEY_PATH` / `ASC_KEY_FILE` | Path to App Store Connect `.p8` private key |
| `ASC_API_KEY_ID` | App Store Connect Key ID (e.g. `U9VB6F2Q4N`) |
| `ASC_API_ISSUER` | App Store Connect Issuer ID UUID |
| `APPLE_ID` | Apple ID email address |
| `NOTARIZE_PASSWORD` | App-specific password (or `@keychain:NAME`) |
| `SIGNING_TEAM_ID` / `TEAM_ID` | 10-character Apple Developer Team ID |

### Example 1: Building with App Store Connect API Key Env Vars

```bash
# Set App Store Connect API Key in your shell or .env
export ASC_API_KEY_PATH="/path/to/AuthKey_U9VB6F2Q4N.p8"
export ASC_API_KEY_ID="U9VB6F2Q4N"
export ASC_API_ISSUER="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export SIGNING_IDENTITY="Developer ID Application: Aandra Labs, Inc. (7GM8GVF5V8)"

# Build, sign, notarize, and staple automatically:
zig build --release=fast
```

### Example 2: Building with Keychain Profile Env Var

```bash
export KEYCHAIN_PROFILE="aandra-labs"
export SIGNING_IDENTITY="Developer ID Application: Aandra Labs, Inc. (7GM8GVF5V8)"

# Build, sign, notarize, and staple automatically:
zig build --release=fast
```

---

## Checking Notarization History & Logs

After a build finishes, you can check the submission history or view failure logs using the same environment variables or profile:

### 1. View Submission History (`notarytool history`)

```bash
# Using App Store Connect API Key env vars:
xcrun notarytool history \
  --key "$ASC_API_KEY_PATH" \
  --key-id "$ASC_API_KEY_ID" \
  --issuer "$ASC_API_ISSUER"

# Or using Keychain Profile env var:
xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE"
```

### 2. View Submission Info & Status (`notarytool info`)

```bash
xcrun notarytool info <SUBMISSION_ID> \
  --key "$ASC_API_KEY_PATH" \
  --key-id "$ASC_API_KEY_ID" \
  --issuer "$ASC_API_ISSUER"
```

### 3. View Detailed Diagnostic Logs (`notarytool log`)

If a notarization status is `Invalid` or rejected, fetch the full diagnostic JSON log:

```bash
xcrun notarytool log <SUBMISSION_ID> \
  --key "$ASC_API_KEY_PATH" \
  --key-id "$ASC_API_KEY_ID" \
  --issuer "$ASC_API_ISSUER"
```

---

## Standalone Script Usage

The helper script [`macos/sign_and_notarize.sh`](file:///Users/paal/Documents/GitHub/workspace/oss/ghostty/macos/sign_and_notarize.sh) can also be invoked directly on any built bundle:

```bash
# View all options
macos/sign_and_notarize.sh --help

# Sign and notarize an existing app bundle using environment variables
macos/sign_and_notarize.sh macos/build/Release/Ghostty.app --notarize

# Sign and notarize using a specific Keychain profile
macos/sign_and_notarize.sh macos/build/Release/Ghostty.app --notarize --keychain-profile "aandra-labs"

# Sign without notarizing
macos/sign_and_notarize.sh macos/build/Release/Ghostty.app --no-notarize
```

---

## Verification

After building and signing, verify the bundle:

```bash
# 1. Inspect certificate authority and entitlements
codesign -dvvv --entitlements - zig-out/Ghostty.app

# 2. Strict deep code signature validation
codesign --verify --deep --strict zig-out/Ghostty.app

# 3. Gatekeeper assessment
spctl --assess --type exec --verbose=2 zig-out/Ghostty.app

# 4. Verify stapled notarization ticket
xcrun stapler validate zig-out/Ghostty.app
```
