import { pipeline, env } from '@xenova/transformers';

env.allowLocalModels = false;
env.useBrowserCache = true;

let transcriber = null;
let isInitializing = false;

export async function initLocalVoice(progressCallback) {
  if (transcriber) {
    if (progressCallback) progressCallback({ status: 'ready' });
    return transcriber;
  }
  if (isInitializing) {
    // Wait for it to finish if currently initializing
    while (isInitializing) {
      await new Promise(resolve => setTimeout(resolve, 300));
    }
    if (progressCallback) progressCallback({ status: 'ready' });
    return transcriber;
  }
  
  isInitializing = true;
  console.log('[LOCAL VOICE] Initializing WASM Whisper Engine...');
  try {
    transcriber = await pipeline('automatic-speech-recognition', 'Xenova/whisper-tiny.en', {
      device: 'wasm',
      progress_callback: (data) => {
        if (progressCallback) {
          progressCallback(data);
        }
      }
    });
    console.log('[LOCAL VOICE] Engine Ready.');
    isInitializing = false;
    if (progressCallback) progressCallback({ status: 'ready' });
    return transcriber;
  } catch (err) {
    const isNetworkError = err.message?.includes('fetch') || !navigator.onLine;
    if (isNetworkError) {
      console.warn('[LOCAL VOICE] Setup required: Whisper model is not cached yet. Connect to the internet once to download the 75MB model files.');
    } else {
      console.error('[LOCAL VOICE] Initialization Failed:', err);
    }
    isInitializing = false;
    if (progressCallback) progressCallback({ status: 'error', error: err });
    throw err;
  }
}

export async function transcribeOffline(audioFloat32Array) {
  const model = await initLocalVoice();
  try {
    const result = await model(audioFloat32Array, {
      chunk_length_s: 10,
      stride_length_s: 2,
    });
    console.log('[LOCAL VOICE] TRANSCRIPT SUCCESS:', result);
    return result.text.trim();
  } catch (err) {
    console.error('[LOCAL VOICE] Transcription failed:', err);
    throw err;
  }
}

// The old interval-based streaming functions have been removed
// as they conflict with Electron's MediaRecorder blob constraints.

// ─────────────────────────────────────────────────────────────────────────────
// ELECTRON ISOLATED PIPELINE
// ─────────────────────────────────────────────────────────────────────────────
// The standard WebM interval decoding fails in Electron due to missing headers.
// We must record a complete blob and decode once at the end.

let electronOnFinalCallback = null;
let electronResolveStop = null;

export async function startElectronRecording(onInterim, onFinal) {
  await initLocalVoice();

  const stream = await navigator.mediaDevices.getUserMedia({ 
    audio: {
      echoCancellation: true,
      noiseSuppression: true,
      autoGainControl: true,
      channelCount: 1,
      sampleRate: 16000
    } 
  });
  
  const mediaRecorder = new MediaRecorder(stream, {
    mimeType: 'audio/webm;codecs=opus'
  });

  let chunks = [];
  electronOnFinalCallback = onFinal;

  mediaRecorder.ondataavailable = (e) => {
    if (e.data.size > 0) {
      chunks.push(e.data);
    }
  };

  mediaRecorder.onstop = async () => {
    const blob = new Blob(chunks, { type: 'audio/webm' });
    const buffer = await blob.arrayBuffer();

    const audioContext = new AudioContext();
    try {
      const audioBuffer = await audioContext.decodeAudioData(buffer);
      const float32Array = audioBuffer.getChannelData(0);
      
      const text = await transcribeOffline(float32Array);
      if (electronOnFinalCallback && text) electronOnFinalCallback(text);
      if (electronResolveStop) electronResolveStop(text);
    } catch (err) {
      console.error('[LOCAL VOICE] decode failed', err);
      if (electronResolveStop) electronResolveStop('');
    } finally {
      stream.getTracks().forEach(track => track.stop());
      window._electronRecorder = null;
      window._electronStream = null;
      electronResolveStop = null;
    }
  };

  mediaRecorder.start();
  
  window._electronRecorder = mediaRecorder;
  window._electronStream = stream;
}

export async function stopElectronRecording() {
  if (window._electronRecorder && window._electronRecorder.state !== 'inactive') {
    return new Promise((resolve) => {
      electronResolveStop = resolve;
      window._electronRecorder.stop();
    });
  }
}
