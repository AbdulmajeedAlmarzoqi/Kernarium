#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The TalkBack and eSpeak NG builder refuses an incomplete toolchain or signing
# key before it builds anything, and stages the packages Andarium recognises.
# It needs no prepared source, SDK or network: every refusal comes first.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
BUILDER="$ROOT_DIR/dependencies/build-andarium-accessibility.sh"
SCREEN_READER="$ROOT_DIR/Andarium/AndariumCore/Sources/AndariumCore/ScreenReader.swift"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/uml-andarium-accessibility.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT HUP INT TERM

TEST_NAME=test-build-andarium-accessibility.sh
. "$(dirname -- "$0")/../support/expect.sh"

"$BUILDER" --help | grep -F -- "--gradle PATH" >/dev/null || fail "--help lacks --gradle"

# A stand-in toolchain: a Gradle, a JDK and an SDK with the pinned NDK and a
# build-tools directory, none of which runs in these checks.
GRADLE="$TEST_ROOT/gradle"
printf '#!/bin/sh\nexit 1\n' >"$GRADLE"
chmod +x "$GRADLE"
JDK="$TEST_ROOT/jdk"
mkdir -p "$JDK/bin"
printf '#!/bin/sh\nexit 1\n' >"$JDK/bin/java"
chmod +x "$JDK/bin/java"
SDK="$TEST_ROOT/sdk"
mkdir -p "$SDK/ndk/29.0.14206865" "$SDK/build-tools/36.1.0"
printf '#!/bin/sh\nexit 1\n' >"$SDK/build-tools/36.1.0/apksigner"
chmod +x "$SDK/build-tools/36.1.0/apksigner"

run()
{
	env JAVA_HOME="$JDK" ANDROID_HOME="$SDK" HOME="$TEST_ROOT/home" "$BUILDER" "$@"
}

expect_diagnostic "--gradle is required" run
expect_diagnostic "is not executable" run --gradle "$TEST_ROOT/missing-gradle"
expect_diagnostic "unknown option" run --gradle "$GRADLE" --sign
expect_diagnostic "JAVA_HOME must name a JDK" \
	env JAVA_HOME="$TEST_ROOT/no-jdk" ANDROID_HOME="$SDK" "$BUILDER" --gradle "$GRADLE"
expect_diagnostic "ANDROID_HOME must name an Android SDK" \
	env JAVA_HOME="$JDK" ANDROID_HOME="$TEST_ROOT/no-sdk" "$BUILDER" --gradle "$GRADLE"
mkdir -p "$TEST_ROOT/old-sdk/build-tools/36.1.0"
expect_diagnostic "the SDK has no NDK 29.0.14206865" \
	env JAVA_HOME="$JDK" ANDROID_HOME="$TEST_ROOT/old-sdk" "$BUILDER" --gradle "$GRADLE"
expect_diagnostic "--keystore requires --key-alias" \
	run --gradle "$GRADLE" --keystore "$TEST_ROOT/release.keystore"
expect_diagnostic "APK_SIGNING_PASSWORD is not set" \
	env -u APK_SIGNING_PASSWORD JAVA_HOME="$JDK" ANDROID_HOME="$SDK" "$BUILDER" \
	--gradle "$GRADLE" --keystore "$TEST_ROOT/release.keystore" --key-alias release
expect_diagnostic "no Android debug keystore" run --gradle "$GRADLE"

# The builder checks each APK is the package Andarium's ScreenReader
# recognises, so the two must name the same packages.
for package in $(sed -n 's/^\([A-Z_]*_PACKAGE\)=\(.*\)$/\2/p' "$BUILDER"); do
	grep -F "\"$package" "$SCREEN_READER" >/dev/null ||
		fail "ScreenReader does not recognise $package, which the builder stages"
done

printf '%s\n' "Andarium accessibility builder tests passed"
