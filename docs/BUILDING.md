# Building Gevun

## GitHub Actions

Maintainer builds run in the private `Gevun-Build` repository. Actions are disabled on the public repository.

Push the release commit to both repositories, then open **Gevun-Build → Actions → Build IPA → Run workflow**. The workflow uses GitHub's standard Xcode 27 Mac runner, runs the core tests, and builds an unsigned device app.

Download the **Gevun** artifact from the completed run and extract `Gevun.ipa`. Sign it with your sideloading tool before installing. Artifacts expire after seven days.

The **Gevun-icon-previews** artifact contains the default, dark, clear light/dark, and tinted light/dark icon previews rendered by Apple's Icon Composer.

## Xcode

Use Xcode 27 with Swift 6.4 or later. Open `Gevun.xcodeproj`, select your signing team and run the Gevun scheme.

The app version and build number live in `Gevun/Info.plist`. The About screen reads the bundle version. Regenerate the Xcode project after changing the version or adding Swift files:

```sh
swift Scripts/GenerateXcodeProject.swift
```

For an unsigned IPA on a Mac, run `bash Scripts/BuildIPA.sh`. It writes `dist/Gevun.ipa`.

Xcode builds use `GevunIcon.icon`, with the existing headphone artwork adapted for native clear and tinted appearances. The PNG icon remains available for Linux builds.

## Linux

Install xtool and a compatible Darwin SDK, then build:

```sh
xtool dev build -c release --triple arm64-apple-ios27.0 --ipa
```

The unsigned IPA is written to `xtool/Gevun.ipa`.

Keep the filename `Gevun.ipa` when uploading releases. Version numbers belong in the app and release tag, not the IPA filename.

## Releases

Update the version and build number in `Gevun/Info.plist`, regenerate the project, and commit the source. Build that commit in `Gevun-Build`, download the IPA artifact, and verify it with `python3 Scripts/VerifyIPA.py path/to/Gevun.ipa` from the source directory. Tag the same commit in the public repository and upload that verified IPA to its release.

## Checks

```sh
swift test --package-path Core
swift format lint --strict --recursive Gevun Core/Sources Core/Tests Scripts Package.swift Core/Package.swift
```

To format the source:

```sh
swift format format --in-place --recursive Gevun Core/Sources Core/Tests Scripts Package.swift Core/Package.swift
```
