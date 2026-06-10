import React, { useState, useRef } from 'react';

export default function VisionDrop({ onExtracted }) {
  const [isProcessing, setIsProcessing] = useState(false);
  const [progress, setProgress] = useState(0);
  const fileInputRef = useRef(null);

  const processImage = async (file) => {
    setIsProcessing(true);
    setProgress(0);
    try {
      // Dynamic import utilizing esm.sh CDN so it works seamlessly without npm installing
      const { createWorker } = await import('https://esm.sh/tesseract.js@5.0.3');
      const worker = await createWorker('eng', 1, {
        logger: m => {
          if (m.status === 'recognizing text') setProgress(Math.floor(m.progress * 100));
        }
      });
      const { data: { text } } = await worker.recognize(file);
      await worker.terminate();
      setIsProcessing(false);
      if (onExtracted) onExtracted(text);
    } catch (e) {
      console.error(e);
      alert('OCR Engine offline or failed initializing.');
      setIsProcessing(false);
    }
  };

  return (
    <div 
      style={{
        border: '1px dashed var(--neon-purple)',
        padding: '1rem',
        textAlign: 'center',
        background: 'rgba(139, 92, 246, 0.05)',
        borderRadius: '8px',
        marginBottom: '1rem',
        cursor: 'pointer',
        transition: 'all 0.2s'
      }}
      onClick={() => fileInputRef.current?.click()}
    >
      <input 
        type="file" 
        accept="image/*" 
        style={{ display: 'none' }} 
        ref={fileInputRef}
        onChange={e => e.target.files[0] && processImage(e.target.files[0])}
      />
      {isProcessing ? (
        <p style={{ color: 'var(--accent-blue)', margin: 0, fontSize: '0.9rem' }}>Extracting Intelligence... {progress}%</p>
      ) : (
        <p style={{ color: 'var(--text-muted)', margin: 0, fontSize: '0.9rem' }}>Deploy Computer Vision (Drop Image or Click to OCR text payload)</p>
      )}
    </div>
  );
}
