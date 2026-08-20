# iOS 16 smoke app

Standalone Xcode app with **iOS 16.0** deployment target. It links the local SVGeeKit package and is the visual check that the core renderer runs below iOS 17.

## Run

```sh
open Apps/iOS16Smoke/iOS16Smoke.xcodeproj
```

Pick an iPhone simulator and Run. For a true iOS 16 check, install the iOS 16.4 runtime (Xcode → Settings → Platforms) and choose an iOS 16 simulator. The app also runs on newer simulators; the home screen shows the OS version.

```sh
xcodebuild -project Apps/iOS16Smoke/iOS16Smoke.xcodeproj \
  -scheme iOS16Smoke \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## What to verify

| Screen | Expected on iOS 16 | Expected on iOS 17+ |
| --- | --- | --- |
| Examples | Every `.svg` dropped in `iOS16Smoke/Examples` renders (see that folder’s README) | Same |
| Canvas | Red circle + blue square | Same |
| Rasterizer | Same graphic as a bitmap | Same |
| Animation engine | Green bar grows over 2s | Same |
| Animation view | Lock message (`@available(iOS 17, *)`) | Live `SVGAnimationImageView` player |
| Script | Lock message | Tap red square → green |
