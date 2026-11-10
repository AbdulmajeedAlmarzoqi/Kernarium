#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build the TalkBack and eSpeak NG APKs that Andarium installs into a guest
# whose system has no screen reader, from the sources dependencies/prepare.sh
# authenticated for the andarium-accessibility product, and stage them where
# the Andarium target's "Bundle TalkBack" phase takes them.
#
# Gradle builds both applications, so unlike the other builders this one is
# not offline: Gradle fetches eSpeak NG's wrapper distribution and both
# applications' Maven dependencies, and eSpeak NG's CMake fetches libsonic.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE_ROOT=${UML_DEPENDENCY_SOURCE_ROOT:-"$ROOT_DIR/external/sources"}
OUTPUT="$ROOT_DIR/.build/andarium-accessibility"
WORK_ROOT="$ROOT_DIR/.build/dependency-build/andarium-accessibility"
GRADLE=
KEYSTORE=
KEY_ALIAS=
# The packages Andarium's ScreenReader recognises.
TALKBACK_PACKAGE=com.android.talkback
SPEECH_PACKAGE=com.reecedunn.espeak
NDK_VERSION=29.0.14206865

fail()
{
	printf '%s\n' "dependencies/build-andarium-accessibility.sh: $*" >&2
	exit 1
}

usage()
{
	cat <<'EOF'
Usage: dependencies/build-andarium-accessibility.sh --gradle PATH [options]

Builds TalkBack and eSpeak NG from the prepared andarium-accessibility sources
and stages TalkBack.apk and eSpeakNG.apk in .build/andarium-accessibility.

Options:
  --gradle PATH       Gradle 8.13 or a later 8.x, for TalkBack, which has no
                      wrapper; eSpeak NG runs its own wrapper
  --keystore PATH     Keystore that signs both APKs; Android's debug keystore
                      (~/.android/debug.keystore) when absent. A guest takes an
                      update only from the key that signed its copy, so builds
                      that ship keep one key. The password is read from
                      APK_SIGNING_PASSWORD.
  --key-alias NAME    Key in --keystore (required with it)
  --output PATH       Staging directory (default: .build/andarium-accessibility)
  -h, --help          Show this help

Requires JAVA_HOME (JDK 17 or later) and ANDROID_HOME, an Android SDK with
platform 36, build-tools, CMake 3.22.1 and NDK 29.0.14206865.
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
	--gradle)
		[ "$#" -ge 2 ] || fail "--gradle requires a path"
		GRADLE=$2
		shift 2
		;;
	--keystore)
		[ "$#" -ge 2 ] || fail "--keystore requires a path"
		KEYSTORE=$2
		shift 2
		;;
	--key-alias)
		[ "$#" -ge 2 ] || fail "--key-alias requires a name"
		KEY_ALIAS=$2
		shift 2
		;;
	--output)
		[ "$#" -ge 2 ] || fail "--output requires a path"
		OUTPUT=$2
		shift 2
		;;
	-h|--help)
		usage
		exit 0
		;;
	*) fail "unknown option: $1" ;;
	esac
done

[ -n "$GRADLE" ] || fail "--gradle is required"
[ -x "$GRADLE" ] || fail "$GRADLE is not executable"
[ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ] || fail "JAVA_HOME must name a JDK"
[ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME" ] || fail "ANDROID_HOME must name an Android SDK"
[ -d "$ANDROID_HOME/ndk/$NDK_VERSION" ] || fail "the SDK has no NDK $NDK_VERSION"
BUILD_TOOLS=$(ls -d "$ANDROID_HOME"/build-tools/*/ 2>/dev/null | sort -V | tail -n 1)
[ -n "$BUILD_TOOLS" ] && [ -x "$BUILD_TOOLS/apksigner" ] || fail "the SDK has no build-tools"
if [ -n "$KEYSTORE" ]; then
	[ -n "$KEY_ALIAS" ] || fail "--keystore requires --key-alias"
	[ -n "${APK_SIGNING_PASSWORD:-}" ] || fail "APK_SIGNING_PASSWORD is not set"
	SIGN_KEY="--ks $KEYSTORE --ks-key-alias $KEY_ALIAS --ks-pass env:APK_SIGNING_PASSWORD"
else
	KEYSTORE=$HOME/.android/debug.keystore
	[ -f "$KEYSTORE" ] || fail "no --keystore and no Android debug keystore at $KEYSTORE"
	SIGN_KEY="--ks $KEYSTORE --ks-key-alias androiddebugkey --ks-pass pass:android"
	printf '%s\n' "signing with the Android debug keystore; a build that ships needs --keystore" >&2
fi

"$ROOT_DIR/dependencies/prepare.sh" --product andarium-accessibility --verify >/dev/null ||
	fail "the andarium-accessibility sources are not prepared; run dependencies/prepare.sh --product andarium-accessibility"

# Each source is built from a clean export of its prepared commit, so the
# prepared checkout stays as prepare.sh verifies it.
export_source()
{
	rm -rf "$WORK_ROOT/$1"
	mkdir -p "$WORK_ROOT/$1"
	git -C "$SOURCE_ROOT/$1" archive HEAD | tar -x -C "$WORK_ROOT/$1"
	printf 'sdk.dir=%s\n' "$ANDROID_HOME" >"$WORK_ROOT/$1/$2/local.properties"
}

# Signs $1 as $2 and checks the package it names is $3.
stage_apk()
{
	[ -f "$1" ] || fail "$1 was not built"
	# shellcheck disable=SC2086
	"$BUILD_TOOLS/apksigner" sign $SIGN_KEY --v4-signing-enabled false --out "$OUTPUT.partial/$2" "$1"
	"$BUILD_TOOLS/apksigner" verify "$OUTPUT.partial/$2" >/dev/null
	package=$("$BUILD_TOOLS/aapt2" dump packagename "$OUTPUT.partial/$2")
	[ "$package" = "$3" ] || fail "$2 is package $package, not $3"
}

export_source talkback .
export_source espeak-ng android
rm -rf "$OUTPUT.partial"
mkdir -p "$OUTPUT.partial"

(cd "$WORK_ROOT/espeak-ng/android" && ./gradlew --no-daemon assembleRelease)
stage_apk "$WORK_ROOT/espeak-ng/android/build/outputs/apk/release/espeak-release-unsigned.apk" \
	eSpeakNG.apk "$SPEECH_PACKAGE"

(cd "$WORK_ROOT/talkback" && "$GRADLE" --no-daemon assemblePhoneRelease)
stage_apk "$WORK_ROOT/talkback/build/outputs/apk/phone/release/talkback-phone-release-unsigned.apk" \
	TalkBack.apk "$TALKBACK_PACKAGE"

rm -rf "$OUTPUT"
mv "$OUTPUT.partial" "$OUTPUT"
printf '%s\n' "staged TalkBack.apk and eSpeakNG.apk in $OUTPUT"
