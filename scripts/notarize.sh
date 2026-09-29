#!/bin/bash
#
# Submit artifacts to Apple's notary service and wait for the verdict.
#
# Usage: scripts/notarize.sh <file>...
#
# Credentials, first match wins:
#   NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER
#       An App Store Connect API key (.p8). This is what CI uses, where no
#       keychain outlives the run.
#   NOTARY_PROFILE
#       A notarytool keychain profile, default "AC_PASSWORD":
#         xcrun notarytool store-credentials AC_PASSWORD \
#             --apple-id your@email.com --team-id ADVP2P7SJK
#
# Submitting only registers the artifacts with Apple. Stapling the ticket is
# the caller's job, because it changes what a later step packages.

set -euo pipefail

NOTARY_PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"
NOTARY_TIMEOUT="${NOTARY_TIMEOUT:-30m}"

run_notarytool() {
    if [ -n "${NOTARY_KEY_PATH:-}" ]; then
        xcrun notarytool "$@" \
            --key "$NOTARY_KEY_PATH" \
            --key-id "${NOTARY_KEY_ID:?NOTARY_KEY_ID is not set}" \
            --issuer "${NOTARY_ISSUER:?NOTARY_ISSUER is not set}"
    else
        xcrun notarytool "$@" --keychain-profile "$NOTARY_PROFILE"
    fi
}

for artifact in "$@"; do
    name=$(basename "$artifact")
    echo "==> Notarizing $name..."
    log=$(mktemp)
    # notarytool exits 0 even for a rejected submission, so the verdict in its
    # output is what decides. It stays in the log either way.
    if run_notarytool submit "$artifact" --wait --timeout "$NOTARY_TIMEOUT" 2>&1 | tee "$log" | grep -q "status: Accepted"; then
        rm -f "$log"
        continue
    fi
    echo "Error: $name was not notarized." >&2
    submission=$(awk '/^[[:space:]]*id: /{print $2; exit}' "$log")
    if [ -n "$submission" ]; then
        echo "--- Notarization log for $submission ---" >&2
        run_notarytool log "$submission" >&2 || true
    fi
    rm -f "$log"
    exit 1
done
