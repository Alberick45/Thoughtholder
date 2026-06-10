import React, { useState, useEffect } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { db } from '../infrastructure/db';

export default function SettingsModal({ onClose, jarvisNotify }) {
  const [userName, setUserName] = useState(localStorage.getItem('jaos_user_name') || '');
  const [settingsKey, setSettingsKey] = useState(localStorage.getItem('jaos_settings_key') || 'i');
  const [stealthKey, setStealthKey] = useState(localStorage.getItem('jaos_stealth_key') || 'l');
  const [vaultKey, setVaultKey] = useState(localStorage.getItem('jaos_vault_key') || 'v');

  // Forensic Scan: Fetch all active security configurations
  const configsStore = useLiveQuery(() => db.settings.get('hydraConfigs'));
  const configs = configsStore ? configsStore.value : {};
  const layers = Object.keys(configs);

  const handleSave = () => {
    localStorage.setItem('jaos_user_name', userName);
    localStorage.setItem('jaos_settings_key', settingsKey.toLowerCase());
    localStorage.setItem('jaos_stealth_key', stealthKey.toLowerCase());
    localStorage.setItem('jaos_vault_key', vaultKey.toLowerCase());
    
    if (userName) {
       jarvisNotify(`Identity updated: Greetings, ${userName}. Protocol parameters saved.`);
    } else {
       jarvisNotify("System preferences synchronized.");
    }
    
    onClose();
    window.location.reload(); 
  };

  const deleteConfig = async (layer) => {
    if (window.confirm(`ERADICATE security lock for [${layer || 'Base Arsenal'}]? Payloads will persist but the vault will be UNPROTECTED.`)) {
      const newConfigs = { ...configs };
      delete newConfigs[layer];
      await db.settings.put({ key: 'hydraConfigs', value: newConfigs });
      jarvisNotify(`Security lock for ${layer || 'Base Arsenal'} has been neutralized.`);
    }
  };

  return (
    <div style={{ position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, background: 'rgba(0,0,0,0.85)', backdropFilter: 'blur(15px)', zIndex: 20000, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <div className="glass-panel" style={{ padding: '2.5rem', width: '95vw', maxWidth: '600px', border: '1px solid var(--accent-blue)', boxShadow: '0 0 40px rgba(59, 130, 246, 0.2)', maxHeight: '90vh', overflowY: 'auto' }}>
        <h2 style={{ color: 'var(--accent-blue)', marginBottom: '1.5rem', letterSpacing: '3px', textTransform: 'uppercase', fontSize: '1.5rem' }}>System Preferences</h2>
        
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1.5rem' }}>
          {/* Identity Section */}
          <section>
            <label style={{ display: 'block', color: 'var(--text-muted)', fontSize: '0.7rem', marginBottom: '0.5rem', letterSpacing: '1px' }}>OPERATOR IDENTITY</label>
            <input 
              type="text" 
              value={userName} 
              onChange={e => setUserName(e.target.value)} 
              placeholder="Enter your name..." 
              style={{ width: '100%', background: '#0a0a0a', border: '1px solid #333', color: 'white', padding: '0.8rem', borderRadius: '4px' }}
            />
          </section>

          {/* Keybindings Section */}
          <section style={{ background: 'rgba(255,255,255,0.03)', padding: '1rem', borderRadius: '8px' }}>
            <label style={{ display: 'block', color: 'var(--accent-blue)', fontSize: '0.75rem', marginBottom: '1rem', fontWeight: 'bold' }}>COMMAND SHORTCUTS (Ctrl + Shift + ...)</label>
            
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 80px', gap: '1rem', alignItems: 'center' }}>
              <span style={{ fontSize: '0.8rem', color: '#ccc' }}>System Settings</span>
              <input maxLength="1" value={settingsKey} onChange={e => setSettingsKey(e.target.value)} style={{ textAlign: 'center', background: '#000', border: '1px solid #444', color: 'white', padding: '0.4rem' }} />
              
              <span style={{ fontSize: '0.8rem', color: '#ccc' }}>Stealth Cloak (Unhide)</span>
              <input maxLength="1" value={stealthKey} onChange={e => setStealthKey(e.target.value)} style={{ textAlign: 'center', background: '#000', border: '1px solid #444', color: 'white', padding: '0.4rem' }} />
              
              <span style={{ fontSize: '0.8rem', color: '#ccc' }}>Vault WineCellar Access</span>
              <input maxLength="1" value={vaultKey} onChange={e => setVaultKey(e.target.value)} style={{ textAlign: 'center', background: '#000', border: '1px solid #444', color: 'white', padding: '0.4rem' }} />
            </div>
          </section>

          {/* Security Management Section */}
          <section style={{ background: 'rgba(239, 68, 68, 0.05)', padding: '1rem', borderRadius: '8px', border: '1px solid rgba(239, 68, 68, 0.1)' }}>
            <label style={{ display: 'block', color: '#f87171', fontSize: '0.75rem', marginBottom: '1rem', fontWeight: 'bold' }}>SECURITY MANAGEMENT (FORCED RESET)</label>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
              {layers.length === 0 ? (
                <p style={{ fontSize: '0.75rem', color: '#4b5563' }}>No active security configurations found.</p>
              ) : (
                layers.map(l => (
                  <div key={l} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', background: '#050505', padding: '0.5rem 0.8rem', borderRadius: '4px' }}>
                    <span style={{ fontSize: '0.85rem', color: '#eee' }}>{l || 'Base Arsenal'}</span>
                    <button onClick={() => deleteConfig(l)} style={{ background: 'transparent', border: '1px solid #ef4444', color: '#ef4444', fontSize: '0.65rem', padding: '2px 8px', borderRadius: '4px', cursor: 'pointer' }}>ERADICATE LOCK</button>
                  </div>
                ))
              )}
            </div>
          </section>

          <div style={{ display: 'flex', gap: '1rem', marginTop: '1rem' }}>
            <button onClick={handleSave} style={{ flex: 1, background: 'var(--accent-blue)', color: 'white', border: 'none', padding: '1rem', borderRadius: '4px', fontWeight: 'bold', cursor: 'pointer' }}>SAVE & SYNC</button>
            <button onClick={onClose} style={{ background: 'transparent', color: 'var(--text-muted)', border: '1px solid #333', padding: '1rem', borderRadius: '4px', cursor: 'pointer' }}>CANCEL</button>
          </div>
        </div>
      </div>
    </div>
  );
}
