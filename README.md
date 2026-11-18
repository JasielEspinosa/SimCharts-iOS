# SimCharts for iPhone

Native SwiftUI iPhone/iPad version of SimCharts (iOS 17+). It downloads airport PDF charts for flight-simulation use and
lists them as country > airport > file, with the same chart sources as the Android and Windows apps (FAA, Philippines,
Hong Kong/Macao, Taiwan, Korea, Viet Nam, Japan mirror, custom resources) and the same chart search box.

Charts are saved in the app's Documents folder, which the Files app shows as **On My iPhone > SimCharts**.

Built on a GitHub macOS runner (no Mac needed): pushing to `main` runs `.github/workflows/build-ios.yml`, which generates
the Xcode project with XcodeGen from `project.yml`, builds unsigned and attaches `SimCharts-vX.Y.Z.ipa` to the release
`vX.Y.Z` (version from `version.txt`).

The `.ipa` is unsigned: sign and install it with Sideloadly or AltStore using your Apple ID
(a free Apple ID works but the app has to be re-signed every 7 days).

Created by 97Espi. For flight simulation only, not for real-world navigation.
