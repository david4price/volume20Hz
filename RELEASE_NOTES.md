# 20HzPlayer 2.0.0

20HzPlayer is now a native Apple Silicon macOS app, with tone generation and playback control written in Rust.

- Play or stop a continuous 20 Hz tone from the menu bar or the black-and-lime control window.
- Choose a gain from 0.5% to 5%. The default is 5%, with a 12.5-second fade-in and up to a 25-second fade-out.
- Follow the Mac’s default audio output or select the output that feeds your soundbar. The app shows **Waiting for soundbar** if the selected device disconnects and resumes playback when it returns.
- Choose a 15-, 30-, or 60-minute screen-lock timeout. **Stop Sound** and the timeout both cancel a pending reconnect. The app shows **Stopped after screen lock** when the timer ends playback.
- The original waveform icon stays in the menu bar, with a small dot beside it while the tone plays. Open the menu to see the playback state and audio output.
- Your output, gain, and timeout preferences are saved between launches.

## Install

Open `20HzPlayer.dmg`, drag `20HzPlayer.app` to Applications, and open it from Finder. This build is ad hoc signed. Live playback on the Polk soundbar is pending verification.
