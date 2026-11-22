# 20HzPlayer

20HzPlayer is a macOS menu bar utility for keeping a Polk soundbar awake during silence. It generates a 20 Hz sine wave when you choose **Play Sound**. The tone fades up over 12.5 seconds and fades down over 25 seconds from its selected gain.

The menu bar shows playback status and the audio output. Choose **Show Window** to see the same status and use the Play and Stop controls. Closing the window returns the app to the menu bar.

- **Soundbar Output** defaults to **Follow System Output**. Select the device that feeds your soundbar, such as an HDMI display or USB audio adapter, to keep the tone on that output even when the Mac’s default changes. If the device disconnects, the app shows **Waiting for soundbar** and resumes when it returns. **Stop Sound** also cancels a pending reconnect.
- **Tone Gain** offers 0.5%, 1%, 2%, 3%, 4%, and 5%. It defaults to 5%. Use the lowest setting that keeps your soundbar awake at your usual listening volume.
- **Stop After Screen Lock** offers 15, 30, and 60 minutes and defaults to 60. Unlocking clears the timer, and waking while still locked restarts it. After a timeout, choose **Play Sound** to start again.

The app remembers your output, gain, and timeout settings. Choose **Quit** to end playback and exit.

## Build on Apple Silicon

Install stable Rust with Cargo and the Xcode Command Line Tools. From the repository root, run the following.

```sh
cargo fmt --check
cargo clippy --locked --all-targets
cargo test --locked
./scripts/package-macos.sh
```

The script writes `20HzPlayer.app` and `20HzPlayer.dmg` to `dist/`. To install, open the disk image and drag the app to Applications. The local build is ad hoc signed and can be installed alongside the Electron build.

For a shortened lock test, run the debug executable from Terminal.

```sh
cargo build --locked
VOLUME20HZ_LOCK_SECONDS=15 ./target/debug/volume20hz
```

## Verify on your soundbar

1. At your usual system and soundbar volume, select the soundbar’s output and play the tone. Leave other audio silent longer than the soundbar’s normal standby interval. Then play a spoken clip and check that you can hear the first words.
2. While the tone plays, switch the Mac’s default output. Confirm 20HzPlayer still shows the selected soundbar output. Disconnect that device and check for **Waiting for soundbar**, then reconnect it and check that playback resumes. Repeat with **Stop Sound** during the wait and confirm playback stays stopped after reconnecting.
3. With the debug timer above, lock the screen for at least 15 seconds during playback and check that the app reports **Stopped after screen lock** after the fade completes. Repeat while waiting for the soundbar and check that the app stays stopped when the device returns.
