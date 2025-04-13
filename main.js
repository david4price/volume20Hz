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
  
  /* ------------------------------------------------------------------
     1) CREATE BROWSER WINDOW
     ------------------------------------------------------------------ */
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
  
    // Hide instead of truly closing
    mainWindow.on("close", (event) => {
      event.preventDefault();
      mainWindow.hide();
    });
  }
  
  /* ------------------------------------------------------------------
     2) TRAY MENU
     ------------------------------------------------------------------ */
  function updateTrayMenu() {
    const contextMenu = Menu.buildFromTemplate([
      {
        label: isPlaying ? "Stop Sound" : "Play Sound",
        click: () => {
          console.log("[TRAY] User clicked tray menu, isPlaying:", isPlaying);
          if (!isPlaying) {
            // Call our main logic to play sound
            handlePlaySound(mainWindow.webContents);
          } else {
            // Call our main logic to stop sound
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
  
  /* ------------------------------------------------------------------
     3) HELPER FUNCTIONS: PLAY / STOP LOGIC
     ------------------------------------------------------------------ */
  function handlePlaySound(sender) {
    console.log("[MAIN] handlePlaySound called");
    isPlaying = true;
    updateTrayMenu();
    resetInactivityCheck();
  
    // 1) Tell the renderer/preload to create/play the audio object
    sender.send("do-play-audio");
  
    // 2) Start a volume ramp
    let volume = 0.0;
    const targetVolume = 0.5;
    const step = 0.1;
  
    const interval = setInterval(() => {
      if (!isPlaying) {
        // If user stopped mid-ramp
        clearInterval(interval);
        return;
      }
      if (volume < targetVolume) {
        volume += step;
        console.log(`[MAIN] Ramping volume: ${volume}`);
        sender.send("set-volume", volume);
      } else {
        clearInterval(interval);
      }
    }, 500);
  
    // 3) Tell the UI to update status to "playing"
    sender.send("sound-state", true);
  }
  
  function handleStopSound(sender) {
    console.log("[MAIN] handleStopSound called");
    isPlaying = false;
    updateTrayMenu();
    resetInactivityCheck();
  
    // Pause/stop the audio in the renderer
    sender.send("do-stop-audio");
  
    // Update the UI to "stopped"
    sender.send("sound-state", false);
  }
  
  /* ------------------------------------------------------------------
     4) SYSTEM INACTIVITY CHECK
     ------------------------------------------------------------------ */
  function startIdleCheck() {
    if (idleCheckInterval) clearInterval(idleCheckInterval);
  
    idleCheckInterval = setInterval(() => {
      const idleTime = powerMonitor.getSystemIdleTime();
      const idleState = powerMonitor.getSystemIdleState(INACTIVITY_LIMIT);
  
      console.log(
        `System idle time: ${idleTime} seconds, Idle state: ${idleState}`
      );
  
      if (isPlaying && (idleState === "idle" || idleState === "locked")) {
        console.log("30 minutes of inactivity detected. Stopping sound.");
        handleStopSound(mainWindow.webContents);
      }
    }, 300 * 1000); // check every 5 min
  }
  
  function resetInactivityCheck() {
    startIdleCheck();
  }
  
  /* ------------------------------------------------------------------
     5) APP READY
     ------------------------------------------------------------------ */
  app.whenReady().then(() => {
    createWindow();
  
    // Optionally set a doc icon on macOS
    if (process.platform === "darwin") {
      app.dock.setIcon(path.join(__dirname, "sound-wave_20Hz_dock.png"));
    }
  
    // Setup tray icon
    const icon = nativeImage.createFromPath(
      path.join(__dirname, "sound-wave_20Hz_tray.png")
    );
    tray = new Tray(icon);
    tray.setToolTip("20Hz Tone Player");
  
    updateTrayMenu();
    startIdleCheck();
  
    app.on("activate", () => {
      if (BrowserWindow.getAllWindows().length === 0) {
        createWindow();
      }
    });
  });
  
  app.on("window-all-closed", () => {
    if (process.platform !== "darwin") {
      app.quit();
    }
  });
  
  /* ------------------------------------------------------------------
     6) IPC HANDLERS: FROM RENDERER => MAIN
     ------------------------------------------------------------------ */
  
  // Renderer wants to play
  ipcMain.on("play-sound", (event) => {
    console.log("[MAIN] Received IPC: play-sound");
    handlePlaySound(event.sender);
  });
  
  // Renderer wants to stop
  ipcMain.on("stop-sound", (event) => {
    console.log("[MAIN] Received IPC: stop-sound");
    handleStopSound(event.sender);
  });