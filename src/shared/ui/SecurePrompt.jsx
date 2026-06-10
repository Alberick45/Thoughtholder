import React, { useState, useEffect, useRef } from 'react';
import { Shield, Lock, X, Check } from 'lucide-react';

/**
 * JAOS Secure Prompt Modal
 * Replaces window.prompt() for Electron compatibility and consistent aesthetics.
 */
export default function SecurePrompt({ 
  show, 
  title = "Authentication Required", 
  message = "Enter your secondary decryption key to proceed.",
  onConfirm, 
  onCancel,
  placeholder = "Enter key..."
}) {
  const [value, setValue] = useState('');
  const inputRef = useRef(null);

  useEffect(() => {
    if (show) {
      setValue('');
      setTimeout(() => inputRef.current?.focus(), 100);
    }
  }, [show]);

  if (!show) return null;

  const handleKeyDown = (e) => {
    if (e.key === 'Enter') onConfirm(value);
    if (e.key === 'Escape') onCancel();
  };

  return (
    <div style={{
      position: 'fixed',
      top: 0,
      left: 0,
      right: 0,
      bottom: 0,
      background: 'rgba(0, 0, 0, 0.8)',
      backdropFilter: 'blur(8px)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      zIndex: 10000,
      animation: 'fadeIn 0.2s ease-out'
    }}>
      <div className="glass-panel" style={{
        width: '100%',
        maxWidth: '400px',
        padding: '2rem',
        background: 'rgba(20, 20, 25, 0.95)',
        border: '1px solid var(--border-focus)',
        borderRadius: '16px',
        boxShadow: '0 20px 50px rgba(0,0,0,0.5)',
        display: 'flex',
        flexDirection: 'column',
        gap: '1.5rem'
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '1rem' }}>
          <div style={{ padding: '0.8rem', background: 'rgba(139, 92, 246, 0.1)', borderRadius: '12px', color: 'var(--neon-purple)' }}>
            <Shield size={24} />
          </div>
          <div>
            <h3 style={{ margin: 0, fontSize: '1.1rem', fontWeight: '800', color: 'white' }}>{title}</h3>
            <p style={{ margin: '0.2rem 0 0 0', fontSize: '0.8rem', color: 'var(--text-muted)' }}>{message}</p>
          </div>
        </div>

        <div style={{ position: 'relative' }}>
          <Lock size={16} style={{ position: 'absolute', left: '12px', top: '50%', transform: 'translateY(-50%)', color: 'rgba(255,255,255,0.3)' }} />
          <input
            ref={inputRef}
            type="password"
            value={value}
            onChange={(e) => setValue(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder={placeholder}
            style={{
              width: '100%',
              background: 'rgba(0,0,0,0.3)',
              border: '1px solid rgba(255,255,255,0.1)',
              borderRadius: '8px',
              padding: '0.8rem 1rem 0.8rem 2.5rem',
              color: 'white',
              fontSize: '1rem',
              outline: 'none',
              transition: 'border-color 0.2s'
            }}
            onFocus={(e) => e.target.style.borderColor = 'var(--neon-purple)'}
            onBlur={(e) => e.target.style.borderColor = 'rgba(255,255,255,0.1)'}
          />
        </div>

        <div style={{ display: 'flex', gap: '1rem' }}>
          <button
            onClick={onCancel}
            style={{
              flex: 1,
              background: 'rgba(255,255,255,0.05)',
              border: '1px solid rgba(255,255,255,0.1)',
              color: 'var(--text-muted)',
              padding: '0.8rem',
              borderRadius: '8px',
              cursor: 'pointer',
              fontWeight: 'bold',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: '8px'
            }}
          >
            <X size={16} /> Cancel
          </button>
          <button
            onClick={() => onConfirm(value)}
            style={{
              flex: 1,
              background: 'var(--neon-purple)',
              border: 'none',
              color: 'white',
              padding: '0.8rem',
              borderRadius: '8px',
              cursor: 'pointer',
              fontWeight: 'bold',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: '8px',
              boxShadow: '0 4px 15px rgba(139, 92, 246, 0.3)'
            }}
          >
            <Check size={16} /> Confirm
          </button>
        </div>
      </div>

      <style>{`
        @keyframes fadeIn {
          from { opacity: 0; transform: scale(0.95); }
          to { opacity: 1; transform: scale(1); }
        }
      `}</style>
    </div>
  );
}
