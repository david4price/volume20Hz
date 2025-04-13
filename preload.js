const { contextBridge, ipcRenderer } = require("electron");

let audio = null;

contextBridge.exposeInMainWorld("electronAPI", {
  playTone: () => {
    console.log("[PRELOAD] playTone => sending 'play-sound' to main");
    ipcRenderer.send("play-sound");
  },

  stopTone: () => {
    console.log("[PRELOAD] stopTone => sending 'stop-sound' to main");
    ipcRenderer.send("stop-sound");
  },

  onSoundStateChange: (callback) => {
    ipcRenderer.on("sound-state", (event, isPlaying) => {
      callback(isPlaying);
    });
  },
});

/* MAIN => PRELOAD commands */
ipcRenderer.on("do-play-audio", () => {
  console.log("[PRELOAD] do-play-audio => create/play audio");
  if (!audio) {
    audio = new Audio("20Hz.mp3");
    audio.loop = true;
    audio.volume = 0;
  }
  audio.play().catch((err) => console.error("Audio play error:", err));
});

ipcRenderer.on("do-stop-audio", () => {
  console.log("[PRELOAD] do-stop-audio => pausing audio");
  if (audio) {
    audio.pause();
    audio.currentTime = 0;
  }
});

ipcRenderer.on("set-volume", (event, newVol) => {
  console.log("[PRELOAD] set-volume =>", newVol);
  if (audio) {
    audio.volume = newVol;
  }
});