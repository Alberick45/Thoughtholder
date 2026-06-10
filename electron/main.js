import { app, BrowserWindow, ipcMain, screen } from 'electron';
import path from 'path';
import { fileURLToPath } from 'url';
import { spawn } from 'child_process';
import fs from 'fs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

let mainWindow;
let ollamaProcess = null;

console.log('──────────────────────────────────────────────────');
console.log('🚀 STRATEGIST ARSENAL BOOTING...');
console.log('📂 SYSTEM DATA PATH:', app.getPath('userData'));
console.log('──────────────────────────────────────────────────');


// ─── Single Instance Lock ────────────────────────────────────────────────────
const gotTheLock = app.requestSingleInstanceLock();

if (!gotTheLock) {
  app.quit();
} else {
  app.on('second-instance', (event, commandLine, workingDirectory) => {
    // If someone tried to run a second instance, focus our window.
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.focus();
    }
  });
}


// ─── Persist Window Bounds ───────────────────────────────────────────────────
function getWindowBounds() {
  const settingsPath = path.join(app.getPath('userData'), 'window-state.json');
  try {
    if (fs.existsSync(settingsPath)) {
      return JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
    }
  } catch {}
  // Default: 80% of primary display
  const { width: sw, height: sh } = screen.getPrimaryDisplay().workAreaSize;
  return { width: Math.round(sw * 0.85), height: Math.round(sh * 0.9), x: undefined, y: undefined, maximized: false };
}

function saveWindowBounds(win) {
  const settingsPath = path.join(app.getPath('userData'), 'window-state.json');
  const bounds = win.getBounds();
  const state = { ...bounds, maximized: win.isMaximized() };
  try { fs.writeFileSync(settingsPath, JSON.stringify(state), 'utf8'); } catch {}
}

function getOllamaPath() {
  const isPackaged = app.isPackaged;
  const binDir = isPackaged 
    ? path.join(process.resourcesPath, 'bin')
    : path.join(__dirname, '../bin');
  
  const exeName = process.platform === 'win32' ? 'ollama.exe' : 'ollama';
  const fullPath = path.join(binDir, exeName);
  
  if (fs.existsSync(fullPath)) {
     return fullPath;
  }
  
  // Fallback to global Ollama if bundled binary doesn't exist
  return 'ollama';
}

function startOllama() {
  const exePath = getOllamaPath();
  console.log('Starting Ollama daemon from:', exePath);
  
  try {
    ollamaProcess = spawn(exePath, ['serve'], {
      stdio: 'ignore', // Run silently
      detached: false
    });
    
    ollamaProcess.on('error', (err) => {
      console.error('Failed to start Ollama:', err);
    });
  } catch(e) {
    console.error('Ollama spawn exception:', e);
  }
}

function createWindow() {
  const saved = getWindowBounds();

  mainWindow = new BrowserWindow({
    width: saved.width,
    height: saved.height,
    x: saved.x,
    y: saved.y,
    minWidth: 900,
    minHeight: 600,
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      nodeIntegration: false,
      contextIsolation: true,
    },
    titleBarStyle: 'hidden',
    titleBarOverlay: {
      color: '#0a0a0c',
      symbolColor: '#8b5cf6',
      height: 32,
    },
    backgroundColor: '#0a0a0c',
    show: false, // reveal after ready to prevent white flash
  });

  if (saved.maximized) mainWindow.maximize();

  mainWindow.once('ready-to-show', () => mainWindow.show());

  // Persist bounds on close / move / resize
  ['close', 'resize', 'move'].forEach(ev => {
    mainWindow.on(ev, () => saveWindowBounds(mainWindow));
  });

  // Notify renderer when maximize state changes
  mainWindow.on('maximize',   () => mainWindow.webContents.send('window-maximized'));
  mainWindow.on('unmaximize', () => mainWindow.webContents.send('window-unmaximized'));

  if (process.env.VITE_DEV_SERVER_URL) {
    mainWindow.loadURL(process.env.VITE_DEV_SERVER_URL);
    mainWindow.webContents.openDevTools({ mode: 'detach' }); // dev-only
  } else {
    mainWindow.loadFile(path.join(__dirname, '../dist/index.html'));
  }
}

app.whenReady().then(() => {
  ipcMain.handle('save-backup', async (event, content) => {
    const backupDir = path.join(app.getPath('userData'), 'backups');
    if (!fs.existsSync(backupDir)) {
      fs.mkdirSync(backupDir, { recursive: true });
    }
    const dt = new Date().toISOString().split('T')[0];
    const filePath = path.join(backupDir, `auto_backup_${dt}.json`);
    fs.writeFileSync(filePath, content, 'utf8');
    return filePath;
  });

  // Window control IPC (used by custom titlebar in React)
  ipcMain.handle('window-minimize', () => mainWindow?.minimize());
  ipcMain.handle('window-maximize', () => {
    if (mainWindow?.isMaximized()) mainWindow.unmaximize();
    else mainWindow?.maximize();
  });
  ipcMain.handle('window-close', () => mainWindow?.close());
  ipcMain.handle('window-is-maximized', () => mainWindow?.isMaximized() ?? false);

  // Handle Model Change Command
  ipcMain.handle('run-model', async (event, modelName) => {
     const exePath = getOllamaPath();
     console.log(`Triggering model pull/run: ${modelName}`);
     return new Promise((resolve, reject) => {
        const pullProcess = spawn(exePath, ['run', modelName], { detached: true, stdio: 'ignore' });
        pullProcess.unref(); // Let it run independently
        resolve({ status: 'started', model: modelName });
     });
  });

  startOllama();
  createWindow();
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('before-quit', () => {
  if (ollamaProcess) {
    console.log('Terminating Ollama daemon...');
    ollamaProcess.kill();
  }
});
