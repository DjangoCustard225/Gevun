# Building Gevun

## Xcode

Use Xcode 27 with Swift 6.4 or later. Open `Gevun.xcodeproj`, select your signing team and run the Gevun scheme.

The app version and build number live in `Gevun/Info.plist`. The About screen reads the bundle version. Regenerate the Xcode project after changing the version or adding Swift files:

```sh
swift Scripts/GenerateXcodeProject.swift
```

## Linux

Install xtool and a compatible Darwin SDK, then build:

```sh
xtool dev build -c release --triple arm64-apple-ios27.0 --ipa
```

The unsigned IPA is written to `xtool/Gevun.ipa`.

## Checks

```sh
swift test --package-path Core
swift format lint --strict --recursive Gevun Core/Sources Core/Tests Scripts Package.swift Core/Package.swift
```

To format the source:

```sh
swift format format --in-place --recursive Gevun Core/Sources Core/Tests Scripts Package.swift Core/Package.swift
```
