/**
 * VoiceEngineManager
 * Manages hybrid routing between online Web Speech API and offline Local Whisper.
 * 
 * DIAGNOSIS LOG (v2):
 * - Web Speech API auto-stops on silence (browser dependent, ~5-15s).
 *   In web mode we now auto-restart on `onend` if still in listening state.
 * - In Electron mode, the offline WASM Whisper pipeline is used (no auto-restart needed).
 * - Engine detection is now logged verbosely to console for debugging.
 */

class VoiceEngineManager {
  constructor() {
    this.state = 'idle'; // idle, listening, processing, error
    this.mode = 'unknown'; // online, offline
    this.recognition = null;
    this._shouldRestart = false; // Controls auto-restart loop
    
    // Callbacks
    this.onInterimResult = null;
    this.onFinalResult = null;
    this.onStateChange = null;
    this.onError = null;

    // Log detected engine at boot
    this._logEngineInfo();
  }

  _logEngineInfo() {
    const isElectron = navigator.userAgent.toLowerCase().includes('electron') || !!window.electronAPI;
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    
    console.group('[VoiceEngineManager] Engine Detection Report');
    console.log('Environment:', isElectron ? '⚡ ELECTRON (Offline Whisper WASM will be used)' : '🌐 WEB BROWSER');
    console.log('SpeechRecognition API:', SpeechRecognition ? `✅ Available (${window.SpeechRecognition ? 'native' : 'webkit prefix'})` : '❌ NOT AVAILABLE in this browser');
    console.log('Browser:', navigator.userAgent);
    console.log('Online:', navigator.onLine);
    console.groupEnd();
  }

  setState(newState, newMode = this.mode) {
    this.state = newState;
    this.mode = newMode;
    if (this.onStateChange) {
      this.onStateChange(this.state, this.mode);
    }
  }

  async start() {
    if (this.state === 'listening' || this.state === 'processing') return;

    const isElectron = navigator.userAgent.toLowerCase().includes('electron') || !!window.electronAPI;

    if (!isElectron) {
      console.log('[VoiceEngineManager] Starting in WEB mode → Web Speech API');
      this._shouldRestart = true;
      return this._startWebMode();
    }

    console.log('[VoiceEngineManager] Starting in ELECTRON mode → Offline Whisper WASM');
    this._shouldRestart = false;
    await this._startElectronMode();
  }

  async _startWebMode() {
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognition) {
      this.setState('error');
      const err = new Error('Web Speech API is not supported in this browser. Try Chrome or Edge.');
      console.error('[VoiceEngineManager]', err.message);
      if (this.onError) this.onError(err);
      return;
    }
    
    console.log('[VoiceEngineManager] Using:', window.SpeechRecognition ? 'window.SpeechRecognition (standard)' : 'window.webkitSpeechRecognition (webkit)');
    
    try {
      await this._startOnline(SpeechRecognition);
    } catch (err) {
      console.warn('[VoiceEngineManager] Web Speech API failed to start:', err);
      this.setState('error');
      if (this.onError) this.onError(err);
    }
  }

  async _startElectronMode() {
    this.setState('listening', 'offline');
    try {
      const { startElectronRecording } = await import('../services/localVoice.js');
      await startElectronRecording(
        (interimText) => {
          if (this.onInterimResult) this.onInterimResult(interimText);
        },
        (finalText) => {
          if (this.onFinalResult) this.onFinalResult(finalText);
        }
      );
    } catch (err) {
      console.error('[VoiceEngineManager] Electron start failed', err);
      this.setState('error');
      if (this.onError) this.onError(err);
    }
  }

  async _startOnline(SpeechRecognitionClass) {
    return new Promise((resolve, reject) => {
      this.recognition = new SpeechRecognitionClass();
      this.recognition.continuous = true;
      this.recognition.interimResults = true;
      this.recognition.lang = 'en-US';

      this.recognition.onstart = () => {
        console.log('[VoiceEngineManager] Web Speech recognition started ✅');
        this.setState('listening', 'online');
        resolve();
      };

      this.recognition.onresult = (event) => {
        let interimTranscript = '';
        let finalTranscript = '';

        for (let i = event.resultIndex; i < event.results.length; ++i) {
          if (event.results[i].isFinal) {
            finalTranscript += event.results[i][0].transcript + ' ';
          } else {
            interimTranscript += event.results[i][0].transcript;
          }
        }

        if (finalTranscript && this.onFinalResult) {
          console.log('[VoiceEngineManager] Final transcript:', finalTranscript.trim());
          this.onFinalResult(finalTranscript);
        }
        if (interimTranscript && this.onInterimResult) {
          this.onInterimResult(interimTranscript);
        }
      };

      this.recognition.onerror = (event) => {
        console.warn('[VoiceEngineManager] Web Speech API error:', event.error);
        
        // "no-speech" and "aborted" are non-fatal — the browser timed out on silence
        // We handle them gracefully: if still supposed to be listening, auto-restart
        if (event.error === 'no-speech' || event.error === 'aborted') {
          console.log('[VoiceEngineManager] Non-fatal error, will attempt restart if still listening...');
          return; // onend will handle restart
        }
        
        // network error can be temporary — still attempt restart
        if (event.error === 'network') {
          console.warn('[VoiceEngineManager] Network error — recognition depends on Google servers. Check connectivity.');
          return;
        }
        
        // Fatal errors: not-allowed (mic permission denied), service-not-allowed
        this._shouldRestart = false;
        if (this.onError) this.onError(new Error(`Speech recognition error: ${event.error}`));
        this.setState('error');
      };

      this.recognition.onend = () => {
        console.log('[VoiceEngineManager] Web Speech recognition ended. shouldRestart:', this._shouldRestart, '| current state:', this.state);
        
        // AUTO-RESTART: Web Speech API stops itself on silence. If the user
        // hasn't explicitly clicked stop, restart immediately.
        if (this._shouldRestart && this.state === 'listening') {
          console.log('[VoiceEngineManager] Auto-restarting recognition...');
          try {
            this.recognition.start();
          } catch (restartErr) {
            console.error('[VoiceEngineManager] Auto-restart failed:', restartErr);
            this.setState('idle');
          }
        } else {
          this.setState('idle');
        }
      };

      try {
        this.recognition.start();
      } catch (err) {
        reject(err);
      }
    });
  }

  async stop() {
    if (this.state === 'idle') return;
    
    console.log('[VoiceEngineManager] Stopping. Mode:', this.mode);
    this._shouldRestart = false; // Prevent auto-restart loop
    
    const isElectron = navigator.userAgent.toLowerCase().includes('electron') || !!window.electronAPI;
    
    if (this.mode === 'online' && this.recognition) {
      this.recognition.stop();
      this.recognition = null;
    } else if (this.mode === 'offline') {
      this.setState('processing', 'offline');
      if (isElectron) {
        const { stopElectronRecording } = await import('../services/localVoice.js');
        await stopElectronRecording();
      }
    }
    
    this.setState('idle');
  }
}

export const voiceEngine = new VoiceEngineManager();
