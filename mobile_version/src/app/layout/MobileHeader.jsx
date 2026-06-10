import React from 'react';

export default function MobileHeader({ jarvisLeash, setJarvisLeash, jarvisOfflineAlert, setJarvisOfflineAlert }) {
  return (
    <header style={{ marginBottom: '1.5rem', textAlign: 'center', position: 'relative' }}>
      <h1 style={{ fontWeight: '800', fontSize: '2rem', background: 'linear-gradient(90deg, #3b82f6, #8b5cf6)', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent', margin: '0 0 0.5rem 0' }}>
        Strategist Arsenal
      </h1>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '1rem', marginBottom: '1rem' }}>
        <p style={{ color: 'var(--text-muted)', margin: 0, fontSize: '0.8rem' }}>Classified Brain OS</p>
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: '0.4rem', background: 'var(--bg-secondary)', padding: '0.2rem 0.8rem', borderRadius: '20px', fontSize: '0.7rem', border: '1px solid var(--border-focus)', cursor: 'pointer' }} onClick={() => {
           const levels = ['0', '1', '2'];
           const next = levels[(levels.indexOf(jarvisLeash) + 1) % 3];
           setJarvisLeash(next);
           localStorage.setItem('jarvis_leash', next);
        }}>
           <span style={{ fontWeight: 'bold', color: jarvisLeash === '0' ? '#666' : (jarvisLeash === '1' ? 'var(--accent-blue)' : 'var(--neon-purple)') }}>
             🧠 Leash: {jarvisLeash === '0' ? 'Sleeping' : (jarvisLeash === '1' ? 'Reactive' : 'Proactive')}
           </span>
        </div>
      </div>
      
      {jarvisOfflineAlert && (
        <div style={{ background: 'rgba(239, 68, 68, 0.1)', border: '1px solid #ef4444', color: '#f87171', padding: '0.5rem', borderRadius: '8px', fontSize: '0.8rem', marginBottom: '1rem' }}>
          Jarvis is Offline. Check Ollama.
          <button style={{ marginLeft: '10px', background: 'transparent', border: 'none', color: 'white' }} onClick={() => setJarvisOfflineAlert(false)}>✕</button>
        </div>
      )}
    </header>
  );
}
