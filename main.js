const { app, BrowserWindow, Tray, Menu, nativeImage, ipcMain, powerMonitor } = require('electron');
const path = require('path');
let mainWindow;
let tray;
let isPlaying = false;
let idleCheckInterval;
const INACTIVITY_LIMIT = 30 * 60; // 30 minutes in seconds

function createWindow() {
    mainWindow = new BrowserWindow({
        width: 350,
        height: 300,
        show: false,
        resizable: false,
        webPreferences: {
            preload: path.join(__dirname, 'preload.js'),
            contextIsolation: true,
        },
    });

    mainWindow.loadFile('index.html');

    // Hide the window when it's closed
    mainWindow.on('close', (event) => {
        event.preventDefault();
        mainWindow.hide();
    });
}

function updateTrayMenu() {
    const contextMenu = Menu.buildFromTemplate([
        {
            label: isPlaying ? 'Stop Sound' : 'Play Sound',
            click: () => {
                isPlaying = !isPlaying;
                mainWindow.webContents.send('sound-state', isPlaying); // Sync UI with tray
                tray.setToolTip(isPlaying ? '20Hz Tone Player - Playing' : '20Hz Tone Player - Stopped');
                updateTrayMenu();
                resetInactivityCheck(); // Reset idle timer on manual play
            },
        },
        { type: 'separator' },
        {
            label: 'Show',
            click: () => {
                mainWindow.show();
                resetInactivityCheck(); // Reset inactivity when UI is interacted with
            },
        },
        {
            label: 'Quit',
            click: () => {
                app.quit();
                app.exit();
            },
        },
    ]);
    tray.setContextMenu(contextMenu);
}

// Function to monitor system idle time
function startIdleCheck() {
    if (idleCheckInterval) clearInterval(idleCheckInterval);

    idleCheckInterval = setInterval(() => {
        const idleTime = powerMonitor.getSystemIdleTime(); // Get idle time in seconds
        const idleState = powerMonitor.getSystemIdleState(INACTIVITY_LIMIT); // Get idle state

        console.log(`System idle time: ${idleTime} seconds, Idle state: ${idleState}`);

        // Only stop sound if system is truly idle or locked
        if (isPlaying && (idleState === 'idle' || idleState === 'locked')) {
            console.log('30 minutes of inactivity detected. Stopping sound.');
            isPlaying = false;
            mainWindow.webContents.send('stop-sound'); // Stop sound playback
            updateTrayMenu();
        }
    }, 300 * 1000); // Check every 5 minutes
}

// Reset idle check timer (when user interacts)
function resetInactivityCheck() {
    startIdleCheck();
}

app.whenReady().then(() => {
    createWindow();

    if (process.platform === 'darwin') {
        app.dock.setIcon(path.join(__dirname, 'sound-wave_20Hz_dock.png'));
    }

    const icon = nativeImage.createFromPath(path.join(__dirname, 'sound-wave_20Hz_tray.png'));
    icon.setTemplateImage(true);

    tray = new Tray(icon);
    tray.setToolTip('20Hz Tone Player');

    updateTrayMenu();
    startIdleCheck(); // Start checking for system inactivity

    app.on('activate', () => {
        if (BrowserWindow.getAllWindows().length === 0) createWindow();
    });
});

app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') app.quit();
});

// Handle updates from the UI to sync tray
ipcMain.on('update-sound-state', (event, state) => {
    isPlaying = state;
    tray.setToolTip(isPlaying ? '20Hz Tone Player - Playing' : '20Hz Tone Player - Stopped');
    updateTrayMenu();
    resetInactivityCheck();
    mainWindow.webContents.send('sound-state', isPlaying); // Ensure UI updates back
});

// Handle gradual volume increase
ipcMain.on('play-sound', (event) => {
    isPlaying = true;
    event.sender.send('start-sound'); // Signal renderer to start sound
    event.sender.send('sound-state', true); // Sync UI state
    updateTrayMenu();
    resetInactivityCheck();
});

ipcMain.on('stop-sound', (event) => {
    isPlaying = false;
    event.sender.send('sound-state', false); // Sync UI state
    updateTrayMenu();
    resetInactivityCheck();
});

ipcMain.on('start-sound', (event) => {
    let volume = 0; // Start at 0% volume
    const interval = setInterval(() => {
        if (volume < 0.25) {
            volume += 0.01;
            event.sender.send('set-volume', volume); // Send volume update to renderer
        } else {
            clearInterval(interval);
        }
    }, 500); // Increase volume every 500ms
});