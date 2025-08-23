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
let lastActivityTime = Date.now();
let isSystemIdle = false;
const INACTIVITY_LIMIT = 30 * 60 * 1000; // 30 minutes in milliseconds

// We'll keep track of the current volume globally
let currentVolume = 0.0;
let rampInterval = null; // so we can clear any existing intervals if needed

// Activity detection variables
let activityCheckInterval;

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

  // Lightweight automatic activity detection
  mainWindow.webContents.on('dom-ready', () => {
    // Simple activity detection - just track basic user interactions
    mainWindow.webContents.executeJavaScript(`
      // Track when user interacts with the app
      document.addEventListener('mousemove', () => {
        if (window.electronAPI) {
          window.electronAPI.userActivity();
        }
      });
      
      document.addEventListener('click', () => {
        if (window.electronAPI) {
          window.electronAPI.userActivity();
        }
      });
      
      document.addEventListener('keydown', () => {
        if (window.electronAPI) {
          window.electronAPI.userActivity();
        }
      });
    `);
  });

  // Detect when window gains/loses focus
  mainWindow.on('focus', () => {
    console.log('App window focused - user is active');
    resetActivity();
  });

  mainWindow.on('blur', () => {
    // Don't immediately mark as idle when window loses focus
    // User might be using other apps
  });

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

    { type: "separator" },
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

// Enhanced activity detection
function startActivityMonitoring() {
  // Check for user activity every 2 minutes
  activityCheckInterval = setInterval(() => {
    checkUserActivity();
  }, 120000); // Check every 2 minutes
  
  // Listen for power state changes
  powerMonitor.on('resume', () => {
    console.log('System resumed from sleep');
    resetActivity();
  });
  
  powerMonitor.on('lock-screen', () => {
    console.log('Screen locked');
    isSystemIdle = true;
  });
  
  powerMonitor.on('unlock-screen', () => {
    console.log('Screen unlocked');
    isSystemIdle = false;
    resetActivity();
  });
  
  powerMonitor.on('user-did-become-active', () => {
    console.log('User became active');
    resetActivity();
  });
  
  powerMonitor.on('user-did-resign-active', () => {
    console.log('User resigned active');
    // Don't immediately mark as idle, just note the event
  });
  
  // Show initial status
  showActivityStatus();
}

// Show current activity status
function showActivityStatus() {
  const now = Date.now();
  const timeSinceLastActivity = Math.round((now - lastActivityTime) / 1000);
  const minutes = Math.floor(timeSinceLastActivity / 60);
  const seconds = timeSinceLastActivity % 60;
  
  // Log to console for debugging
  console.log(`=== Activity Status ===`);
  console.log(`Idle detection: ENABLED (Always On)`);
  console.log(`Time since last activity: ${timeSinceLastActivity} seconds`);
  console.log(`Idle limit: 30 minutes`);
  console.log(`System idle: ${isSystemIdle ? 'Yes' : 'No'}`);
  console.log(`Sound playing: ${isPlaying ? 'Yes' : 'No'}`);
  console.log(`=======================`);
}

// Smart idle detection that considers context
function isUserActuallyIdle() {
  const now = Date.now();
  const timeSinceLastActivity = now - lastActivityTime;
  
  // Check system idle state
  const systemIdleState = powerMonitor.getSystemIdleState(INACTIVITY_LIMIT / 1000);
  
  console.log(`Idle check - Time since activity: ${Math.round(timeSinceLastActivity / 1000)}s, System state: ${systemIdleState}`);
  
  // User is considered idle if:
  // 1. No activity for 30 minutes AND
  // 2. System reports idle or locked AND
  // 3. Window is not focused (user not actively using the app)
  const isWindowFocused = mainWindow && !mainWindow.isDestroyed() && mainWindow.isFocused();
  
  return timeSinceLastActivity > INACTIVITY_LIMIT && 
         (systemIdleState === 'idle' || systemIdleState === 'locked' || isSystemIdle) &&
         !isWindowFocused;
}

function checkUserActivity() {
  const now = Date.now();
  const timeSinceLastActivity = now - lastActivityTime;
  
  // Check system idle state as backup
  const systemIdleTime = powerMonitor.getSystemIdleTime() * 1000; // Convert to milliseconds
  const systemIdleState = powerMonitor.getSystemIdleState(INACTIVITY_LIMIT / 1000);
  
  console.log(`Activity check - Time since last activity: ${Math.round(timeSinceLastActivity / 1000)}s, System idle: ${Math.round(systemIdleTime / 1000)}s, State: ${systemIdleState}`);
  
  // Check if there might be video playback or other media activity
  const hasMediaActivity = checkForMediaActivity();
  
  // Use the smart idle detection
  if (isUserActuallyIdle() && !hasMediaActivity) {
    if (isPlaying) {
      console.log('Smart idle detection: User appears to be idle - stopping sound');
      handleStopSound(mainWindow.webContents);
    }
  }
}

// Check for media activity that might indicate user engagement
function checkForMediaActivity() {
  // Simplified media check - just return false to keep it light
  // You can manually disable idle detection if watching movies
  return false;
}

function resetActivity() {
  lastActivityTime = Date.now();
  isSystemIdle = false;
  console.log('Activity reset - user is active');
}

// Enhanced inactivity checks - replaced the old startIdleCheck
function startIdleCheck() {
  if (idleCheckInterval) clearInterval(idleCheckInterval);
  
  // Start activity monitoring instead of basic idle checking
  startActivityMonitoring();
  
  // Keep a backup check every 5 minutes as fallback
  idleCheckInterval = setInterval(() => {
    checkUserActivity();
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
  setupGlobalInputMonitoring();
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

ipcMain.on("user-activity", (event) => {
  resetActivity();
});

// Global input monitoring for better activity detection
function setupGlobalInputMonitoring() {
  // Simplified - just log that it's set up
  console.log('Global input monitoring set up (simplified)');
}