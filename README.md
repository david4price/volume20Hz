# 20HzPlayer

20HzPlayer is a macOS menu bar utility for keeping a Polk soundbar awake during silence. It generates a 20 Hz sine wave on the Mac’s default audio output. Playback starts only when you choose **Play Sound**. The app fades up to 5% gain over 12.5 seconds and fades down over 25 seconds from full gain.

Choose **Show Window** for playback status and controls. Closing the window returns the app to the menu bar. After 60 minutes with the screen locked, playback fades out. Unlocking clears the timer, waking restarts it if still locked, and playback requires a manual start after auto-stop. Choose **Quit** to end playback and exit.

## Build on Apple Silicon

Install stable Rust with Cargo and the Xcode Command Line Tools. From the repository root, run the following.

```sh
cargo fmt --check
cargo clippy --locked --all-targets
cargo test --locked
./scripts/package-macos.sh
```

The script writes the app and disk image to `dist/`. The local build is ad hoc signed and can be installed alongside the Electron build.

For a shortened lock test, run the debug executable from Terminal.

```sh
cargo build --locked
VOLUME20HZ_LOCK_SECONDS=15 ./target/debug/volume20hz
```

The release build always uses 60 minutes. Test playback and output switching at your usual system volume and compare the Rust and Electron builds on the same soundbar. Check for standby during silence and for the start of dialogue after silence.
