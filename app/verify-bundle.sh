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
# Five things are checked, and each later one exists because the earlier ones can all pass while
# the app is still broken:
#   1. every source resource file exists in the bundle at the same relative path
#   2. byte for byte — an existence check would pass a truncated or stale `InfoPlist.strings`,
#      which is exactly the hole the round-1 review found in our own specification
#   3. the file **sets** match: a `.lproj` file in the bundle with no source is reported too, and a
#      run that compared nothing fails rather than passes
#   4. the `.lproj` **directory** sets match, and every entry in them is a regular file. `find -type f`
#      cannot see an empty extra `.lproj` (no files to walk) or a symlink standing in for one, and an
#      empty `fr.lproj` is enough for macOS to advertise a localization the app has no strings for
#   5. the built `Info.plist` still says `CFBundleDevelopmentRegion` — measured (D2): with the region
#      at `ko`, a process asking for a language we do not ship resolved to Korean, so a wrong value
#      here puts unshipped languages into the wrong one while every byte above matches
#      Each catalogue is also parsed, not just compared: two files can be byte-identical to each
#      other and unreadable to `Bundle(path:)` alike

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

# The `.lproj` directories as *sets*, which the file walk above cannot see: an extra `.lproj` with
# nothing in it contributes no files, and neither does one that is a symlink.
SOURCE_LPROJ=$(find "$SOURCES" -maxdepth 1 -name '*.lproj' -exec basename {} \; | sort)
BUNDLED_LPROJ=$(find "$BUNDLED" -maxdepth 1 -name '*.lproj' -exec basename {} \; | sort)
if [ "$SOURCE_LPROJ" != "$BUNDLED_LPROJ" ]; then
    fail "the .lproj directories differ — sources [$(echo "$SOURCE_LPROJ" | tr '\n' ' ')] bundle [$(echo "$BUNDLED_LPROJ" | tr '\n' ' ')]"
fi
# ...and every entry inside them is a regular file. A symlink is not what `cp -R` produced, and it
# points somewhere this gate never compared
while IFS= read -r entry; do
    if [ -L "$entry" ] || [ ! -f "$entry" ]; then
        fail "not a regular file in the bundle: ${entry#"$BUNDLED"/}"
    fi
done < <(find "$BUNDLED" -maxdepth 2 -path '*.lproj/*' ! -name '.DS_Store' | sort)

# Every catalogue has to parse. Byte-equality says the two copies agree; it does not say either one
# can be read, and a `.strings` file that `PropertyListSerialization` rejects silently yields no
# keys at runtime. `plutil` answers this without a Swift toolchain in the loop — the full
# `Bundle(path:)` load stays in the test suite (item 6), where the source tree is the subject and no
# build is required to run it.
while IFS= read -r catalogue; do
    if ! plutil -lint "$catalogue" >/dev/null 2>&1; then
        fail "does not parse: ${catalogue#"$BUNDLED"/}"
    fi
done < <(find "$BUNDLED" -maxdepth 2 -path '*.lproj/*' -name '*.strings' | sort)

# **The catalogue set is closed.** Everything above compares the two sides to each other, which is
# silent about a language we do not ship: an `fr.lproj` added to the sources is copied by `build.sh`,
# matches byte for byte, has equal directory sets, and parses — so every check passed while macOS
# advertised a localization nothing resolves to (round 15 review). The list is spelled out because a
# shell script cannot read `supportedLocales`, and `LocalizationBundleTests` fails if the two drift,
# which is the same arrangement `CFBundleDevelopmentRegion` below already has.
SUPPORTED_LPROJ="en ko ja zh-Hans zh-Hant"
while IFS= read -r dir; do
    name="$(basename "$dir" .lproj)"
    case " $SUPPORTED_LPROJ " in
        *" $name "*) ;;
        *) fail "not a language we ship: $(basename "$dir")" ;;
    esac
done < <(find "$SOURCES" "$BUNDLED" -maxdepth 1 -name '*.lproj' | sort)

# The development region is what macOS answers with when it can match nothing else, so a wrong value
# here is a language nobody asked for rather than a missing file. `UninstallScriptSyncTests`-style
# drift between this literal and `fallbackLocale` is covered by a test that reads this script.
REGION=$(plutil -extract CFBundleDevelopmentRegion raw -o - "$APP/Contents/Info.plist" 2>/dev/null || true)
if [ "$REGION" != "en" ]; then
    fail "CFBundleDevelopmentRegion is ${REGION:-missing}, expected en"
fi

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
