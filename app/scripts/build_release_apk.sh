#!/usr/bin/env bash
set -euo pipefail

# Builds one release APK per CPU architecture (armeabi-v7a, arm64-v8a, x86_64)
# instead of a single "fat" universal APK. The universal APK bundles all three
# ABIs' native libraries into one file (~49MB); splitting drops that to
# ~17MB for the arm64-v8a APK, which covers virtually all real Android phones.
#
# `android/app/build.gradle.kts` can't bake --split-per-abi in via Gradle
# properties: setting `split-per-abi=true` in gradle.properties does make
# Gradle split the build, but the `flutter` CLI's own success check doesn't
# know to look for per-ABI filenames unless the flag is passed on the command
# line, so it reports a false "failed to produce an .apk file" and exits 1.
# Always build through this script (or pass --split-per-abi yourself) instead.
#
# See docs/release.md for the full size breakdown.

cd "$(dirname "$0")/.."

flutter build apk --release --split-per-abi "$@"

echo
echo "Release APKs:"
ls -lh build/app/outputs/flutter-apk/*.apk
