import React, { useState, useEffect } from "react";
import { db } from "../infrastructure/db";
import { Settings, Shield, Trash2, Key, RefreshCcw, X, Info } from "lucide-react";

export default function SettingsModal({ isOpen, onClose }) {
  const [leash, setLeash] = useState(localStorage.getItem('jarvis_leash') || '1');
  const [debug, setDebug] = useState(localStorage.getItem('jaos_debug') === 'true');
  const [activeTab, setActiveTab] = useState('general');

  if (!isOpen) return null;

  const handleLeashChange = (val) => {
    setLeash(val);
    localStorage.setItem('jarvis_leash', val);
  };

  const handleDebugToggle = () => {
    const newVal = !debug;
    setDebug(newVal);
    localStorage.setItem('jaos_debug', newVal);
  };

  const handleEradicateLock = async () => {
    if (window.confirm("CRITICAL: Eradicate all vault access patterns? Intel will remain encrypted but locked until reconfigured.")) {
       await db.settings.delete('hydraConfigs');
       await db.settings.delete('hydraTriggers');
       alert("Security credentials purged.");
       window.location.reload();
    }
  };

  const renderTab = () => {
    switch(activeTab) {
      case 'general':
        return (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '1.5rem' }}>
            <section>
              <h4 style={{ color: 'var(--accent-blue)', fontSize: '0.8rem', marginBottom: '0.8rem', letterSpacing: '1px' }}>COGNITIVE CONTROL</h4>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                <label style={{ fontSize: '0.9rem', color: 'white' }}>Jarvis Autonomy Leash</label>
                <select 
                  value={leash} 
                  onChange={(e) => handleLeashChange(e.target.value)}
                  style={{ width: '100%', background: '#000', border: '1px solid #333', color: 'white', padding: '0.8rem', borderRadius: '8px' }}
                >
                  <option value="0">Sleeping (Manual Only)</option>
                  <option value="1">Reactive (Prompt Based)</option>
                  <option value="2">Proactive (Ambient Intelligence)</option>
                  <option value="3">Unleashed (High Frequency)</option>
                </select>
              </div>

              <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', marginTop: '1rem' }}>
                <label style={{ fontSize: '0.9rem', color: 'white' }}>Remote Jarvis IP</label>
                <input 
                  type="text" 
                  placeholder="e.g. 192.168.1.50"
                  defaultValue={localStorage.getItem('remote_jarvis_ip') || ''}
                  onBlur={(e) => localStorage.setItem('remote_jarvis_ip', e.target.value)}
                  style={{ width: '100%', background: '#000', border: '1px solid #333', color: 'white', padding: '0.8rem', borderRadius: '8px' }}
                />
                <p style={{ fontSize: '0.65rem', color: '#6B7280' }}>Connect mobile app to a PC running Ollama on the same network.</p>
              </div>
            </section>

            <section>
              <h4 style={{ color: 'var(--neon-purple)', fontSize: '0.8rem', marginBottom: '0.8rem', letterSpacing: '1px' }}>SYSTEM FORENSICS</h4>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0.8rem', background: '#000', borderRadius: '8px', border: '1px solid #222' }}>
                <span style={{ fontSize: '0.9rem', color: 'white' }}>Diagnostic Overlays</span>
                <button onClick={handleDebugToggle} style={{ background: debug ? 'var(--neon-purple)' : '#333', border: 'none', width: '40px', height: '20px', borderRadius: '10px', position: 'relative' }}>
                   <div style={{ position: 'absolute', left: debug ? '22px' : '2px', top: '2px', width: '16px', height: '16px', background: 'white', borderRadius: '50%', transition: 'all 0.2s' }} />
                </button>
              </div>
            </section>
          </div>
        );
      case 'security':
        return (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '1.5rem' }}>
            <section>
              <h4 style={{ color: '#ef4444', fontSize: '0.8rem', marginBottom: '0.8rem', letterSpacing: '1px' }}>NUCLEAR PROTOCOLS</h4>
              <button 
                onClick={handleEradicateLock}
                style={{ width: '100%', padding: '1rem', background: 'rgba(239, 68, 68, 0.1)', color: '#ef4444', border: '1px solid #ef4444', borderRadius: '12px', fontWeight: 'bold', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '0.8rem' }}
              >
                <Key size={18} /> Eradicate All Locks
              </button>
              <p style={{ fontSize: '0.7rem', color: '#6B7280', marginTop: '0.5rem', textAlign: 'center' }}>Purges password/picture sequences without deleting data.</p>
            </section>

            <section>
              <h4 style={{ color: 'var(--accent-blue)', fontSize: '0.8rem', marginBottom: '0.8rem', letterSpacing: '1px' }}>DATA INTEGRITY</h4>
              <button 
                onClick={() => window.location.reload()}
                style={{ width: '100%', padding: '1rem', background: 'transparent', color: 'white', border: '1px solid #333', borderRadius: '12px', fontWeight: 'bold', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '0.8rem' }}
              >
                <RefreshCcw size={18} /> Refresh DB Connection
              </button>
            </section>
          </div>
        );
      default: return null;
    }
  };

  return (
    <div style={{ position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, background: 'rgba(0,0,0,0.9)', zIndex: 10000, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '1rem' }}>
      <div className="glass-panel" style={{ width: '100%', maxWidth: '400px', maxHeight: '80vh', background: '#0a0a0c', borderRadius: '20px', border: '1px solid var(--border-focus)', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        
        <header style={{ padding: '1.2rem', display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid #222' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '0.8rem' }}>
            <Settings size={20} color="var(--neon-purple)" />
            <h3 style={{ margin: 0, color: 'white', fontSize: '1.1rem' }}>Tactical Control</h3>
          </div>
          <button onClick={onClose} style={{ background: 'transparent', border: 'none' }}><X size={24} color="white" /></button>
        </header>

        <nav style={{ display: 'flex', background: '#000', borderBottom: '1px solid #222' }}>
           <button onClick={() => setActiveTab('general')} style={{ flex: 1, padding: '1rem', background: activeTab === 'general' ? 'rgba(139, 92, 246, 0.1)' : 'transparent', color: activeTab === 'general' ? 'var(--neon-purple)' : '#6B7280', border: 'none', borderBottom: activeTab === 'general' ? '2px solid var(--neon-purple)' : 'none', fontWeight: 'bold' }}>CORE</button>
           <button onClick={() => setActiveTab('security')} style={{ flex: 1, padding: '1rem', background: activeTab === 'security' ? 'rgba(239, 68, 68, 0.1)' : 'transparent', color: activeTab === 'security' ? '#ef4444' : '#6B7280', border: 'none', borderBottom: activeTab === 'security' ? '2px solid #ef4444' : 'none', fontWeight: 'bold' }}>SECURITY</button>
        </nav>

        <div style={{ flex: 1, overflowY: 'auto', padding: '1.5rem' }}>
          {renderTab()}
        </div>
      </div>
    </div>
  );
}
