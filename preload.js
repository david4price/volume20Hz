const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
    playTone: () => {
        const audio = new Audio('20Hz.mp3');
        audio.loop = true;
        audio.volume = 0; // Start at 0% volume
        audio.play();
        ipcRenderer.send('start-sound'); // Notify main process that sound started
        ipcRenderer.send('update-sound-state', true); // Sync tray with UI action
        return audio;
    },
    stopTone: (audio) => {
        if (audio) {
            audio.pause();
            audio.currentTime = 0;
            ipcRenderer.send('update-sound-state', false); // Sync tray with UI action
        }
    },
    onVolumeChange: (callback) => {
        ipcRenderer.on('set-volume', (event, volume) => {
            callback(volume);
        });
    },
    onSoundStateChange: (callback) => {
        ipcRenderer.on('sound-state', (event, state) => {
            callback(state);
        });
    }
});
