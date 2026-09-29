#!/bin/bash
#
# Pick an Xcode toolchain for building Monolingual.
#
# Monolingual needs Xcode 27 or later (the app deploys to macOS 27), while the
# default Xcode is not necessarily the newest installed one and the default
# location is not guaranteed to be the newest. Select by the version each
# bundle reports, never by filename.
#
# Precedence:
#   1. $DEVELOPER_DIR, if it satisfies the minimum (used verbatim)
#   2. newest stable install (Xcode.app, Xcode_*.app, the active xcode-select)
#   3. newest beta install — only if no stable install qualifies
#
# Candidates are resolved through symlinks before they are compared, because
# /Applications/Xcode.app is a symlink to the *default* install on GitHub's
# images — which is not necessarily the newest one.
#
# Prints the Developer directory on stdout; progress goes to stderr, so it
# composes:
#   export DEVELOPER_DIR="$(scripts/select-xcode.sh)"

set -euo pipefail

MIN_MAJOR="${MIN_XCODE_MAJOR:-27}"

# Version reported by an .app bundle, or empty if it can't be run.
xcode_version() {
    local app="$1" out
    [ -x "$app/Contents/Developer/usr/bin/xcodebuild" ] || return 0
    out=$("$app/Contents/Developer/usr/bin/xcodebuild" -version 2>/dev/null | head -1) || true
    printf '%s' "${out##* }"
}

# Version of an .app bundle if it satisfies the minimum, otherwise nothing.
supported_version() {
    local version major
    version=$(xcode_version "$1")
    [ -n "$version" ] || return 0
    major="${version%%.*}"
    case "$major" in
        ''|*[!0-9]*) return 0 ;;
    esac
    if [ "$major" -ge "$MIN_MAJOR" ]; then
        printf '%s' "$version"
    fi
}

# Echo the newest supported .app among the arguments.
newest_supported() {
    local app version best="" best_version=""
    for app in "$@"; do
        version=$(supported_version "$app")
        if [ -z "$version" ]; then
            echo "    skipping $app (not Xcode $MIN_MAJOR+)" >&2
            continue
        fi
        if [ -z "$best_version" ] ||
            [ "$(printf '%s\n%s\n' "$best_version" "$version" | sort -V | tail -1)" = "$version" ]; then
            best="$app"
            best_version="$version"
        fi
    done
    if [ -n "$best" ]; then
        printf '%s' "$best"
    fi
}

# 1. An explicitly set DEVELOPER_DIR wins, as long as it satisfies the minimum.
if [ -n "${DEVELOPER_DIR:-}" ]; then
    app="${DEVELOPER_DIR%/Contents/Developer}"
    version=$(supported_version "$app")
    if [ -n "$version" ]; then
        echo "    using \$DEVELOPER_DIR (Xcode $version)" >&2
        printf '%s\n' "$app/Contents/Developer"
        exit 0
    fi
    echo "    ignoring \$DEVELOPER_DIR=$DEVELOPER_DIR (not Xcode $MIN_MAJOR+)" >&2
fi

# 2. Collect installs, keeping betas aside as a fallback. The active
#    xcode-select path usually duplicates one of the /Applications globs.
stable=()
beta=()
seen=$'\n'

add_candidate() {
    local app="$1" real
    [ -n "$app" ] && [ -d "$app" ] || return 0
    # Resolve symlinks. GitHub's images alias several names onto one bundle
    # (/Applications/Xcode.app and /Applications/Xcode_<v>.app both point at
    # Xcode_<v>.app), and a beta must be classified by its real name rather
    # than whichever alias reached it.
    real=$(cd "$app" && pwd -P) || return 0
    case "$seen" in
        *$'\n'"$real"$'\n'*) return 0 ;;
    esac
    seen="$seen$real"$'\n'
    case "${real##*/}" in
        *[Bb]eta*) beta+=("$real") ;;
        *)         stable+=("$real") ;;
    esac
}

active=$(xcode-select -p 2>/dev/null) || active=""
add_candidate "${active%/Contents/Developer}"
for app in /Applications/Xcode.app /Applications/Xcode_*.app /Applications/Xcode-beta.app; do
    add_candidate "$app"
done

picked=""
if [ "${#stable[@]}" -gt 0 ]; then
    picked=$(newest_supported "${stable[@]}")
fi
if [ -z "$picked" ] && [ "${#beta[@]}" -gt 0 ]; then
    echo "    no stable Xcode $MIN_MAJOR+ installed, falling back to beta" >&2
    picked=$(newest_supported "${beta[@]}")
fi

if [ -z "$picked" ]; then
    echo "Error: no Xcode $MIN_MAJOR or later found." >&2
    echo "Install Xcode $MIN_MAJOR from the App Store, or point \$DEVELOPER_DIR at one." >&2
    exit 1
fi

echo "    using $picked (Xcode $(xcode_version "$picked"))" >&2
printf '%s\n' "$picked/Contents/Developer"
