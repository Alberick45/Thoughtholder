const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  saveBackup:      (content)   => ipcRenderer.invoke('save-backup', content),
  runModel:        (modelName) => ipcRenderer.invoke('run-model', modelName),
  // Window controls (used by custom title bar)
  windowMinimize:  ()          => ipcRenderer.invoke('window-minimize'),
  windowMaximize:  ()          => ipcRenderer.invoke('window-maximize'),
  windowClose:     ()          => ipcRenderer.invoke('window-close'),
  windowIsMaximized: ()        => ipcRenderer.invoke('window-is-maximized'),
  onMaximizeChange: (cb)       => {
    ipcRenderer.on('window-maximized',   () => cb(true));
    ipcRenderer.on('window-unmaximized', () => cb(false));
  },
});
