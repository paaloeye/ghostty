# macOS Code Signing and Notarization Guide (Nushell)

This document provides copy-and-paste commands formatted specifically for **Nushell** (`nu`), using parenthesized multiline command syntax `(...)`.

---

## 1. Quick Start: Set Environment Variables & Build

### Option A: Using App Store Connect API Key (Recommended for CI / Fork)

```nu
load-env {
    ASC_API_KEY_PATH: "/Users/paal/Downloads/AuthKey_U9VB6F2Q4N.p8",
    ASC_API_KEY_ID: "U9VB6F2Q4N",
    ASC_API_ISSUER: "<YOUR-ASC-ISSUER-UUID>",
    SIGNING_IDENTITY: "Developer ID Application: Aandra Labs, Inc. (7GM8GVF5V8)",
}

zig build --release=fast
```

---

### Option B: Using a Stored Keychain Profile

```nu
# 1. Store credentials once into macOS Keychain:
(xcrun notarytool store-credentials "aandra-labs"
    --key "/Users/paal/Downloads/AuthKey_U9VB6F2Q4N.p8"
    --key-id "U9VB6F2Q4N"
    --issuer "<YOUR-ASC-ISSUER-UUID>")

# 2. Set Keychain profile env var:
$env.KEYCHAIN_PROFILE = "aandra-labs"
$env.SIGNING_IDENTITY = "Developer ID Application: Aandra Labs, Inc. (7GM8GVF5V8)"

# 3. Build, sign, and notarize:
zig build --release=fast
```

---

## 2. Building via Direct Zig Options (No Env Vars)

```nu
# Build and notarize passing credentials as flags:
(zig build --release=fast
    -Dmacos-api-key="/Users/paal/Downloads/AuthKey_U9VB6F2Q4N.p8"
    -Dmacos-api-key-id="U9VB6F2Q4N"
    -Dmacos-api-issuer="<YOUR-ASC-ISSUER-UUID>")

# Or using Keychain Profile flag:
zig build --release=fast -Dmacos-keychain-profile="aandra-labs"

# Codesign only (skip remote Apple notarization):
zig build --release=fast -Dmacos-notarize=false
```

---

## 3. Checking Notarization History & Logs

### Check Submission History

```nu
# Using App Store Connect API Key environment variables:
(xcrun notarytool history
    --key $env.ASC_API_KEY_PATH
    --key-id $env.ASC_API_KEY_ID
    --issuer $env.ASC_API_ISSUER)

# Or using Keychain Profile:
xcrun notarytool history --keychain-profile "aandra-labs"
```

### View Submission Details

```nu
(xcrun notarytool info <SUBMISSION_ID>
    --key $env.ASC_API_KEY_PATH
    --key-id $env.ASC_API_KEY_ID
    --issuer $env.ASC_API_ISSUER)
```

### View Diagnostic JSON Logs (on failure or reject)

```nu
(xcrun notarytool log <SUBMISSION_ID>
    --key $env.ASC_API_KEY_PATH
    --key-id $env.ASC_API_KEY_ID
    --issuer $env.ASC_API_ISSUER)
```

---

## 4. Verification Commands

Run these to verify the built bundle in [`zig-out/Ghostty.app`](file:///Users/paal/Documents/GitHub/workspace/oss/ghostty/zig-out/Ghostty.app):

```nu
# 1. Inspect authority, team ID, and entitlements
codesign -dvvv --entitlements - zig-out/Ghostty.app

# 2. Strict deep code signature validation
codesign --verify --deep --strict zig-out/Ghostty.app

# 3. Validate stapled ticket
xcrun stapler validate zig-out/Ghostty.app

# 4. Gatekeeper assessment
spctl --assess --type exec --verbose=2 zig-out/Ghostty.app
```

---

## 5. Direct Helper Script Execution

```nu
# Sign and notarize an existing build with env vars:
./macos/sign_and_notarize.sh macos/build/Release/Ghostty.app --notarize

# Sign and notarize with explicit Keychain profile:
(./macos/sign_and_notarize.sh macos/build/Release/Ghostty.app
    --notarize
    --keychain-profile "aandra-labs")

# Codesign only:
./macos/sign_and_notarize.sh macos/build/Release/Ghostty.app --no-notarize
```
