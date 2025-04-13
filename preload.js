// preload.js
const { contextBridge, ipcRenderer } = require("electron");

let audio = null;

contextBridge.exposeInMainWorld("electronAPI", {
  // Called by the UI "Play" button
  playTone: () => {
    console.log("[PRELOAD] playTone => sending 'play-sound' to main");
    ipcRenderer.send("play-sound");
  },

  // Called by the UI "Stop" button
  stopTone: () => {
    console.log("[PRELOAD] stopTone => sending 'stop-sound' to main");
    ipcRenderer.send("stop-sound");
  },

  // UI can subscribe to "sound-state" changes (main -> renderer)
  onSoundStateChange: (callback) => {
    ipcRenderer.on("sound-state", (event, isPlaying) => {
      callback(isPlaying);
    });
  },
});

/* ------------------------------------------------------------------
   MESSAGES: MAIN => PRELOAD
   ------------------------------------------------------------------ */

// "do-play-audio" => create & start playing if not already
ipcRenderer.on("do-play-audio", () => {
  console.log("[PRELOAD] do-play-audio => create/play audio");
  if (!audio) {
    audio = new Audio("20Hz.mp3");
    audio.loop = true;
    audio.volume = 0;
  }
  audio.play().catch((err) => console.error("Audio play error:", err));
});

// "do-stop-audio" => pause & reset
ipcRenderer.on("do-stop-audio", () => {
  console.log("[PRELOAD] do-stop-audio => stopping audio");
  if (audio) {
    audio.pause();
    audio.currentTime = 0;
  }
});

// "set-volume" => ramp the volume
ipcRenderer.on("set-volume", (event, newVol) => {
  console.log("[PRELOAD] set-volume =>", newVol);
  if (audio) {
    audio.volume = newVol;
  }
});