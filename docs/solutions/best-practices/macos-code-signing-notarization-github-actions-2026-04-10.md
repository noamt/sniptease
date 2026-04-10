---
title: "macOS Code Signing and Notarization in GitHub Actions"
date: 2026-04-10
category: best-practices
module: release-pipeline
problem_type: best_practice
component: development_workflow
severity: high
applies_when:
  - "Building a macOS app with xcodebuild build (not archive + exportArchive) in CI"
  - "Signing with Developer ID Application for distribution outside the Mac App Store"
  - "Notarizing with notarytool and packaging into a DMG"
tags:
  - macos
  - code-signing
  - notarization
  - github-actions
  - xcodebuild
  - developer-id
  - dmg
  - stapler
---

# macOS Code Signing and Notarization in GitHub Actions

## Context

When automating macOS app distribution through GitHub Actions — building with `xcodebuild`, signing with a Developer ID Application certificate, notarizing with Apple's notary service, and publishing a DMG via GitHub Releases — three non-obvious pitfalls cause the workflow to silently produce unsigned or un-notarized artifacts, or to fail in ways that masquerade as transient infrastructure issues.

Each pitfall was encountered while setting up the release pipeline for SnipTease, a native Swift/SwiftUI menu bar app. Together they cost multiple CI iterations to diagnose because each one looked like something else.

## Guidance

### Pitfall 1: The debug entitlement that blocks notarization

Apple's notary service rejects apps containing the `com.apple.security.get-task-allow` entitlement. Xcode injects this by default — even in Release configuration — when using `xcodebuild build`. The `archive` + `exportArchive` path strips it automatically, but plain `build` does not.

The failure is hard to diagnose because `notarytool submit --wait` exits 0 even when the status is "Invalid" (see Pitfall 3). The only visible symptom is that stapling fails with "Record not found", which looks like a CDN propagation delay rather than a rejection.

**Fix:** Add `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`:

```bash
xcodebuild build \
  -project MyApp.xcodeproj \
  -scheme MyApp \
  -configuration Release \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  "OTHER_CODE_SIGN_FLAGS=--timestamp --options runtime" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
```

### Pitfall 2: Stapling a DMG doesn't work — staple the .app instead

Even after successful notarization, `xcrun stapler staple MyApp.dmg` fails with "CloudKit query failed due to Record not found." This is not transient — DMG tickets either never propagate to Apple's CloudKit CDN or take unpredictably long (observed: still failing after 6 retries over 3+ minutes).

**Fix:** Notarize and staple the `.app`, then package the stapled app into the DMG:

```bash
# Zip the .app for submission (notarytool requires zip or dmg)
ditto -c -k --keepParent "build/Release/MyApp.app" MyApp.zip

# Submit and wait
xcrun notarytool submit MyApp.zip --wait \
  --key "$API_KEY_PATH" --key-id "$KEY_ID" --issuer "$ISSUER_ID"

# Staple the .app directly (works on first attempt)
xcrun stapler staple "build/Release/MyApp.app"

# NOW wrap the stapled .app into the DMG
create-dmg --volname "MyApp" ... "MyApp.dmg" "build/Release/MyApp.app"
```

This mirrors Xcode's own "Direct Distribution" flow where notarization targets the `.app`, not the container.

### Pitfall 3: notarytool exits 0 on rejection — check status explicitly

`xcrun notarytool submit --wait` returns exit code 0 for both "Accepted" and "Invalid". It only returns non-zero when it cannot reach Apple's servers. A `set -e` workflow will not catch rejections.

**Fix:** Parse the submission output and check status:

```bash
RESULT=$(xcrun notarytool submit MyApp.zip --wait \
  --key "$KEY_PATH" --key-id "$KEY_ID" --issuer "$ISSUER_ID" 2>&1)

SUBMISSION_ID=$(echo "$RESULT" | grep "  id:" | head -1 | awk '{print $2}')
STATUS=$(echo "$RESULT" | grep "  status:" | head -1 | awk '{print $2}')

if [ "$STATUS" != "Accepted" ]; then
  echo "Notarization failed: $STATUS"
  xcrun notarytool log "$SUBMISSION_ID" \
    --key "$KEY_PATH" --key-id "$KEY_ID" --issuer "$ISSUER_ID"
  exit 1
fi
```

The `notarytool log` output contains Apple's exact rejection reason, which is essential for debugging.

## Why This Matters

- **Pitfall 1** publishes a DMG that Gatekeeper blocks on every user's machine, with no actionable error. The CI workflow exits 0, so the broken artifact gets shipped.
- **Pitfall 2** causes intermittent CI failures on the stapling step. The natural response is more retries and longer delays, wasting CI minutes on a problem that retries cannot solve.
- **Pitfall 3** means the workflow reports success while publishing an un-notarized artifact. This is the most dangerous: silent corruption of the release pipeline.

Each pitfall masquerades as something else — a CDN delay, a transient CI failure, a stapling infrastructure issue — when the root causes are deterministic and fixable.

## When to Apply

- Building a macOS app with `xcodebuild build` (not `archive` + `exportArchive`) in CI
- Signing with Developer ID Application for distribution outside the App Store
- Notarizing with `notarytool` (the modern replacement for `altool`)
- Packaging into a DMG for release
- Running in CI where interactive debugging is expensive

If using `xcodebuild archive` + `exportArchive`, Pitfall 1 does not apply (Xcode strips the entitlement automatically). Pitfalls 2 and 3 still apply.

## Examples

### Required GitHub Secrets (5)

| Secret | Value |
|--------|-------|
| `APPLE_CERTIFICATE_P12_BASE64` | Developer ID Application cert + key as .p12, base64-encoded |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the .p12 export |
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect issuer UUID |
| `APPLE_API_KEY_P8_BASE64` | The .p8 key file, base64-encoded |

### Certificate setup notes

- Must be **Developer ID Application** (not "Apple Development" or "Mac App Distribution")
- Generate the CSR using **Keychain Access.app**, not `openssl` — Apple rejects OpenSSL-generated CSRs
- App Store Connect API key needs **Developer** role minimum
- If the API Keys page shows "Request Access", an Account Holder must enable it first

### Reference implementation

See [`.github/workflows/release.yml`](../../.github/workflows/release.yml) for the complete working workflow.

## Related

- [Apple: Resolving Common Notarization Issues](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution/resolving_common_notarization_issues)
- [Apple: Customizing the Notarization Workflow](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
