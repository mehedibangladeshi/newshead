# Building a release APK

Always build release APKs with `app/scripts/build_release_apk.sh`, not a bare
`flutter build apk --release`. It builds one APK per CPU architecture
(armeabi-v7a, arm64-v8a, x86_64) instead of a single "fat" universal APK.

```bash
cd app
./scripts/build_release_apk.sh
```

Output lands in `app/build/app/outputs/flutter-apk/`:

- `app-arm64-v8a-release.apk` — install this one; it covers virtually all
  real Android phones sold since ~2017.
- `app-armeabi-v7a-release.apk` — older 32-bit ARM devices.
- `app-x86_64-release.apk` — emulators / Chromebooks / Intel tablets.

## Why this matters

A bare `flutter build apk --release` produces one **universal APK** that
bundles the Flutter engine and compiled Dart code for *all three*
architectures at once, even though any given device only ever uses one.
Measured on this app:

| Build | Size |
|---|---|
| Universal (`flutter build apk --release`) | 49.3 MB |
| `armeabi-v7a` only | 14.8 MB |
| `arm64-v8a` only | 17.5 MB |
| `x86_64` only | 19.0 MB |

Inspecting the universal APK's contents shows why: ~97% of its 49.3 MB is
native `.so` libraries duplicated per architecture (`libflutter.so` — the
precompiled engine — and `libapp.so` — the compiled Dart/framework code).
The app's own Dart code compiles to under 40 KB; this is Flutter's fixed
per-architecture engine cost, not app bloat, and splitting by ABI is the
standard fix.

## Why not a Gradle-level `splits.abi` block or a `gradle.properties` flag?

Both were tried and rejected:

- Adding `splits { abi { ... } }` directly to `android/app/build.gradle.kts`
  conflicts with the Flutter Gradle plugin's own ABI handling
  (`ndk.abiFilters`), and the build fails with "Conflicting configuration"
  unless the `split-per-abi` project property is also set — at which point
  the manual block is redundant.
- Setting `split-per-abi=true` in `android/gradle.properties` (to make
  splitting the default without needing a flag) does make Gradle split the
  build correctly, but the `flutter` CLI's own success check doesn't know to
  look for per-ABI output filenames unless `--split-per-abi` was passed on
  the command line. It reports a false "Gradle build failed to produce an
  .apk file" and exits 1 even though the split APKs were built correctly —
  a silent footgun for anyone scripting or CI-checking the build's exit code.

So `--split-per-abi` has to be passed on the command line for the whole
toolchain (Gradle *and* the `flutter` wrapper) to agree on what got built.
`build_release_apk.sh` exists so that flag is never left to memory.

## If distributing through Google Play instead

Use `flutter build appbundle` and upload the `.aab` — Play's dynamic
delivery already serves each device only its matching ABI, so per-ABI
splitting on the APK side is unnecessary for that path. This script and
its instructions are for direct/sideloaded APK distribution.
