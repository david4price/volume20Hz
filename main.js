const {
  app,
  BrowserWindow,
  Tray,
  Menu,
  nativeImage,
  ipcMain,
  powerMonitor,
} = require("electron");
const path = require("path");

let mainWindow;
let tray;
let isPlaying = false;
let idleCheckInterval;
const INACTIVITY_LIMIT = 30 * 60; // 30 minutes in seconds

// We'll keep track of the current volume globally
let currentVolume = 0.0;
let rampInterval = null; // so we can clear any existing intervals if needed

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 350,
    height: 300,
    show: false,
    resizable: false,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
    },
  });

  mainWindow.loadFile("index.html");


  mainWindow.on("close", (event) => {
    event.preventDefault();
    mainWindow.hide();
  });
}

function updateTrayMenu() {
  const contextMenu = Menu.buildFromTemplate([
    {
      label: isPlaying ? "Stop Sound" : "Play Sound",
      click: () => {
        if (!isPlaying) {
          handlePlaySound(mainWindow.webContents);
        } else {
          handleStopSound(mainWindow.webContents);
        }
      },
    },
    { type: "separator" },
    {
      label: "Show Window",
      click: () => {
        mainWindow.show();
        resetInactivityCheck();
      },
    },
    {
      label: "Quit",
      click: () => {
        app.quit();
        app.exit();
      },
    },
  ]);

  tray.setContextMenu(contextMenu);
}

// RAMP UP: Called when we want to *start* playing
function handlePlaySound(sender) {
  console.log("[MAIN] handlePlaySound");
  isPlaying = true;
  updateTrayMenu();
  resetInactivityCheck();

  // If we were in the middle of a ramp (either up or down), clear it
  if (rampInterval) {
    clearInterval(rampInterval);
    rampInterval = null;
  }

  // Tell renderer to create/play the audio element if not exists
  sender.send("do-play-audio");

  // Start volume from 0
  currentVolume = 0.0;
  const targetVolume = 0.05;
  const step = 0.001

  rampInterval = setInterval(() => {
    // If user hit "Stop" mid-ramp, break out
    if (!isPlaying) {
      clearInterval(rampInterval);
      rampInterval = null;
      return;
    }

    if (currentVolume < targetVolume) {
      currentVolume += step;
      console.log(`[MAIN] Ramping up: ${currentVolume}`);
      sender.send("set-volume", currentVolume);
    } else {
      clearInterval(rampInterval);
      rampInterval = null;
    }
  }, 250);

  sender.send("sound-state", true);
}

// RAMP DOWN: Called when we want to *stop* playing
function handleStopSound(sender) {
  console.log("[MAIN] handleStopSound");
  isPlaying = false;
  updateTrayMenu();
  resetInactivityCheck();

  if (rampInterval) {
    clearInterval(rampInterval);
    rampInterval = null;
  }

  // Ramp from currentVolume down to 0
  const step = 0.001;

  rampInterval = setInterval(() => {
    if (currentVolume > 0) {
      currentVolume -= step;
      if (currentVolume < 0) {
        currentVolume = 0;
      }
      console.log(`[MAIN] Ramping down: ${currentVolume}`);
      sender.send("set-volume", currentVolume);
    } else {
      clearInterval(rampInterval);
      rampInterval = null;
      sender.send("do-stop-audio");
      sender.send("sound-state", false);
    }
  }, 500);
}

// Inactivity checks
function startIdleCheck() {
  if (idleCheckInterval) clearInterval(idleCheckInterval);

  idleCheckInterval = setInterval(() => {
    const idleTime = powerMonitor.getSystemIdleTime();
    const idleState = powerMonitor.getSystemIdleState(INACTIVITY_LIMIT);

    console.log(
      `System idle time: ${idleTime} seconds, Idle state: ${idleState}`
    );

    if (isPlaying && (idleState === "idle" || idleState === "locked")) {
      console.log("30 minutes of inactivity => ramping down to stop");
      handleStopSound(mainWindow.webContents);
    }
  }, 300 * 1000);
}

function resetInactivityCheck() {
  startIdleCheck();
}

app.whenReady().then(() => {
  createWindow();

  const icon = nativeImage.createFromPath(
    path.join(__dirname, "sound-wave_20Hz_tray.png")
  );
  tray = new Tray(icon);
  tray.setToolTip("20Hz Tone Player");

  updateTrayMenu();
  startIdleCheck();
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

/* ------------------------------------------------------------------
   IPC from Renderer
   ------------------------------------------------------------------ */
ipcMain.on("play-sound", (event) => {
  handlePlaySound(event.sender);
});

ipcMain.on("stop-sound", (event) => {
  handleStopSound(event.sender);
});