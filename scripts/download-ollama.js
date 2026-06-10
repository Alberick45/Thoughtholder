import fs from 'fs';
import path from 'path';
import https from 'https';
import { execSync } from 'child_process';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const BIN_DIR = path.join(__dirname, '../bin');
const OS = process.platform;

if (!fs.existsSync(BIN_DIR)) {
  fs.mkdirSync(BIN_DIR, { recursive: true });
}

async function downloadFile(url, dest) {
  return new Promise((resolve, reject) => {
    console.log(`Downloading ${url} ...`);
    
    const request = https.get(url, (response) => {
      // Handle redirects
      if (response.statusCode === 301 || response.statusCode === 302) {
        return downloadFile(response.headers.location, dest).then(resolve).catch(reject);
      }
      
      if (response.statusCode !== 200) {
        reject(new Error(`Failed to get '${url}' (${response.statusCode})`));
        return;
      }
      
      const file = fs.createWriteStream(dest);
      response.pipe(file);
      file.on('finish', () => {
        file.close();
        console.log(`Downloaded to ${dest}`);
        resolve();
      });
    }).on('error', (err) => {
      fs.unlink(dest, () => reject(err));
    });
  });
}

async function run() {
  let url = '';
  let filename = '';
  let isZip = false;

  if (OS === 'win32') {
    url = 'https://github.com/ollama/ollama/releases/latest/download/ollama-windows-amd64.zip';
    filename = 'ollama.zip';
    isZip = true;
  } else if (OS === 'darwin') {
    // Note: Mac provides a zip as well for the app, but the CLI binary is available too.
    // For simplicity, we assume linux/mac raw binaries, or handle zip if needed.
    url = 'https://github.com/ollama/ollama/releases/latest/download/ollama-darwin';
    filename = 'ollama';
  } else {
    url = 'https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64';
    filename = 'ollama';
  }

  const destPath = path.join(BIN_DIR, filename);

  // Check if executable already exists to save bandwidth
  const exePath = OS === 'win32' ? path.join(BIN_DIR, 'ollama.exe') : path.join(BIN_DIR, 'ollama');
  if (fs.existsSync(exePath)) {
    console.log('Ollama binary already exists. Skipping download.');
    return;
  }

  try {
    await downloadFile(url, destPath);
    
    if (isZip && OS === 'win32') {
      console.log('Extracting ZIP on Windows...');
      execSync(`powershell -command "Expand-Archive -Force -Path '${destPath}' -DestinationPath '${BIN_DIR}'"`);
      fs.unlinkSync(destPath); // Remove zip after extract
    } else {
      // Make executable on Mac/Linux
      fs.chmodSync(destPath, 0o755);
    }
    
    console.log('Ollama binary is ready in ./bin/');
  } catch (err) {
    console.error('Download failed:', err);
    process.exit(1);
  }
}

run();
