# 20HzPlayer 2.0.0

20HzPlayer is now a native Apple Silicon macOS app, with tone generation and playback control written in Rust.

- Play or stop a continuous 20 Hz tone from the menu bar or the black-and-lime control window.
- Playback fades in to 5% gain over 12.5 seconds. It fades out from full gain over 25 seconds.
- Playback fades out after 60 minutes with the screen locked. Start it again from the menu bar after unlocking.
- Playback follows the Mac’s default audio output. Closing the control window keeps the app in the menu bar.

## Install

Extract `20HzPlayer-2.0.0-macos-arm64.zip`, move `20HzPlayer.app` to Applications, and open it from Finder. This build is ad hoc signed. Live playback on the Polk soundbar is pending verification.
