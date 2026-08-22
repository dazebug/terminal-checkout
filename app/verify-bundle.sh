#!/bin/bash
set -euo pipefail

# Does the built app carry exactly the resources the sources declare?
#
# This is the one check that closes D1's silent failure. Catalogues are read with `Bundle(path:)`
# instead of SwiftPM's `Bundle.module` because the generated accessor resolves through an absolute
# `.build` path on the machine that compiled it, so a catalogue missing from the bundle still
# answers there and fails only on someone else's Mac. Reading by path moves the failure to runtime
# for everyone equally — which is an improvement only if something notices before a user does.
# That something is this script.
#
# **It is a script and not an XCTest on purpose.** `swift test` runs with no `.app` in existence,
# so a test would have to skip when the bundle is absent, and a gate that greens by not running is
# the same shape as the defect it is here to catch. `app/build.sh` calls it as its last step, so
# "the build succeeded" means "the bundle matches the sources", and CI names it as its own step so
# removing that call from build.sh cannot quietly remove the gate.
#
# Three things are checked, and the third is why the first two are not enough:
#   1. every source resource file exists in the bundle at the same relative path
#   2. byte for byte — an existence check would pass a truncated or stale `InfoPlist.strings`,
#      which is exactly the hole the round-1 review found in our own specification
#   3. the file **sets** match: a `.lproj` file in the bundle with no source is reported too, and a
#      run that compared nothing fails rather than passes

cd "$(dirname "$0")"

APP="${1:-build/Terminal Checkout.app}"
SOURCES="Sources/App/Resources"
BUNDLED="$APP/Contents/Resources"

FAILURES=0
fail() {
    echo "verify-bundle: $1" >&2
    FAILURES=$((FAILURES + 1))
}

if [ ! -d "$APP" ]; then
    echo "verify-bundle: no app bundle at $APP — run app/build.sh first" >&2
    exit 1
fi
if [ ! -d "$SOURCES" ]; then
    echo "verify-bundle: no source resources at $SOURCES — the gate has nothing to compare" >&2
    exit 1
fi

# Every source file, not only the ones under a `.lproj`: `build.sh` copies `*.lproj` directories, so
# anything else added here would be left out silently. Reporting it is the point — a file that
# genuinely belongs in the sources alone has to be excluded here deliberately, in this line, rather
# than by nobody noticing.
# `.DS_Store` is skipped on both sides: the Finder writes it into any directory it displays, and it
# is neither ours nor the build's.
SOURCE_COUNT=0
while IFS= read -r file; do
    rel="${file#"$SOURCES"/}"
    SOURCE_COUNT=$((SOURCE_COUNT + 1))
    if [ ! -f "$BUNDLED/$rel" ]; then
        fail "missing from the bundle: $rel"
    elif ! cmp -s "$file" "$BUNDLED/$rel"; then
        fail "differs from the source: $rel"
    fi
done < <(find "$SOURCES" -type f ! -name '.DS_Store' | sort)

# The other direction, limited to the catalogue directories: everything else under
# `Contents/Resources` (the icon, the embedded extension) is put there by other lines of build.sh
# and has nothing to do with these sources.
while IFS= read -r file; do
    rel="${file#"$BUNDLED"/}"
    if [ ! -f "$SOURCES/$rel" ]; then
        fail "in the bundle with no source: $rel"
    fi
done < <(find "$BUNDLED" -type f -path '*.lproj/*' ! -name '.DS_Store' | sort)

# A gate that compared nothing has to fail. Without this, deleting the source tree would make
# every check above vacuous and the build would go green on an app with no catalogues at all.
if [ "$SOURCE_COUNT" -eq 0 ]; then
    fail "no source resource files found — the comparison was empty"
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "verify-bundle: $FAILURES problem(s) — the bundle does not match $SOURCES" >&2
    exit 1
fi

echo "verify-bundle: $SOURCE_COUNT resource file(s) match the sources"
