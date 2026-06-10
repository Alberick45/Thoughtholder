import React, { useState } from 'react';
import { Shield, Lock, Plus, Trash2, RotateCcw, AlertTriangle, Layers } from 'lucide-react';

export default function Arsenal({ forcedLayer, vaultedThoughts, vaultedTrash = [], onLockDown, onStoreIntel, onConfig, onRestore, onEradicate, onWipe, onPermanentEradicate, onRestoreFromTrash }) {
  const [intelText, setIntelText] = useState('');
  const [intelLayer, setIntelLayer] = useState('');
  const [isAddingMode, setIsAddingMode] = useState(false);
  const [viewState, setViewState] = useState('intel'); // 'intel' | 'trash'
  const [activeLayer, setActiveLayer] = useState(forcedLayer || ''); // '' means Base Payload

  return (
    <div style={{ background: '#050505', backgroundImage: 'radial-gradient(circle at 50% 50%, rgba(139, 92, 246, 0.05) 0%, transparent 50%)', height: '100vh', display: 'flex', flexDirection: 'column' }}>
      <main style={{ padding: '1rem', flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column', width: '100%' }}>
        <header style={{ marginBottom: '1.5rem', display: 'flex', flexDirection: 'column', gap: '1rem' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div>
              <h1 style={{ fontWeight: '900', fontSize: '1.2rem', color: 'var(--neon-purple)', margin: 0, letterSpacing: '2px', textTransform: 'uppercase' }}>Arsenal</h1>
              <p style={{ color: 'var(--text-muted)', fontSize: '0.6rem', letterSpacing: '1px' }}>LVL 4 ACTIVE {forcedLayer ? `[${forcedLayer}]` : ''}</p>
            </div>
            <button onClick={onLockDown} style={{ background: 'rgba(239, 68, 68, 0.2)', color: '#ef4444', border: '1px solid #ef4444', padding: '0.5rem 0.8rem', fontWeight: 'bold', borderRadius: '8px', display: 'flex', alignItems: 'center', gap: '0.4rem', fontSize: '0.8rem' }}>
              <Lock size={14} /> LOCK
            </button>
          </div>
          <div style={{ display: 'flex', gap: '0.5rem' }}>
            <button onClick={onConfig} style={{ flex: 1, background: 'transparent', color: 'var(--text-muted)', border: '1px solid #333', padding: '0.6rem', borderRadius: '8px', fontSize: '0.8rem' }}>CONFIG</button>
            <button onClick={() => setIsAddingMode(!isAddingMode)} style={{ flex: 2, background: 'transparent', color: 'var(--neon-purple)', border: '1px solid var(--neon-purple)', padding: '0.6rem', borderRadius: '8px', fontWeight: 'bold', fontSize: '0.8rem', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '0.4rem' }}>
              <Plus size={14} /> STORE INTEL
            </button>
          </div>
        </header>

        {isAddingMode && (
          <div style={{ padding: '1rem', background: '#000', border: '1px solid var(--neon-purple)', borderRadius: '12px', marginBottom: '1.5rem', display: 'flex', flexDirection: 'column', gap: '0.8rem' }}>
            <input 
               type="text" 
               placeholder="Target Sub-Layer (e.g. Delta)" 
               value={intelLayer} 
               onChange={(e) => setIntelLayer(e.target.value)} 
               style={{ background: '#111', color: 'white', border: '1px solid #333', padding: '0.8rem', borderRadius: '8px', fontSize: '0.9rem' }}
            />
            <textarea 
               placeholder="Raw classified payload..." 
               value={intelText} 
               onChange={(e) => setIntelText(e.target.value)} 
               style={{ width: '100%', minHeight: '80px', background: '#111', color: 'white', padding: '0.8rem', border: 'none', borderRadius: '8px', fontSize: '0.9rem' }}
            />
            <button 
              onClick={() => { 
                if(intelText.trim() || intelLayer.trim()) { 
                  const text = intelText.trim() || `[Sub-Layer "${intelLayer.trim()}" Initialized]`;
                  const tags = intelLayer.trim() ? [`Layer: ${intelLayer.trim()}`] : (forcedLayer ? [`Layer: ${forcedLayer}`] : []);
                  onStoreIntel(text, tags); 
                  setIntelText(''); setIntelLayer(''); setIsAddingMode(false); 
                } 
              }} 
              style={{ background: 'var(--neon-purple)', color: 'white', border: 'none', padding: '0.8rem', fontWeight: 'bold', borderRadius: '8px' }}
            >
              Encrypt & Store
            </button>
          </div>
        )}

        <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem', flex: 1, overflow: 'hidden' }}>
          <div style={{ border: '1px solid var(--border-subtle)', background: 'rgba(0,0,0,0.5)', padding: '1rem', borderRadius: '12px', flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
            
            {/* Horizontal Sub-Layer Tray */}
            {!forcedLayer && (
            <div style={{ display: 'flex', gap: '0.5rem', marginBottom: '1rem', overflowX: 'auto', paddingBottom: '0.5rem', whiteSpace: 'nowrap' }}>
              <button 
                onClick={() => setActiveLayer('')} 
                style={{ background: activeLayer === '' ? 'var(--neon-purple)' : '#111', color: 'white', border: 'none', padding: '0.4rem 1rem', borderRadius: '20px', fontSize: '0.7rem' }}>
                BASE
              </button>
              {Array.from(new Set(vaultedThoughts.flatMap(t => t.tags || []).filter(tag => tag.startsWith('Layer: ')))).map(layerTag => {
                const pureLayerName = layerTag.replace('Layer: ', '');
                return (
                  <button 
                    key={layerTag}
                    onClick={() => setActiveLayer(pureLayerName)} 
                    style={{ background: activeLayer === pureLayerName ? 'var(--neon-purple)' : '#111', color: 'white', border: 'none', padding: '0.4rem 1rem', borderRadius: '20px', fontSize: '0.7rem' }}>
                    {pureLayerName}
                  </button>
                )
              })}
            </div>
            )}

            <div style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px solid #222', paddingBottom: '0.5rem', marginBottom: '1rem' }}>
              <div style={{ display: 'flex', gap: '1rem' }}>
                <button onClick={() => setViewState('intel')} style={{ background: 'transparent', border: 'none', color: viewState === 'intel' ? 'var(--neon-purple)' : 'var(--text-muted)', fontSize: '0.8rem', fontWeight: 'bold' }}>PAYLOADS</button>
                <button onClick={() => setViewState('trash')} style={{ background: 'transparent', border: 'none', color: viewState === 'trash' ? '#ef4444' : 'var(--text-muted)', fontSize: '0.8rem', fontWeight: 'bold' }}>TRASH ({vaultedTrash.length})</button>
              </div>
            </div>
            
            <div style={{ flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: '0.8rem' }}>
            {viewState === 'intel' ? (
              (activeLayer === '' 
                ? vaultedThoughts.filter(t => !t.tags || !t.tags.some(tag => tag.startsWith('Layer: '))) 
                : vaultedThoughts.filter(t => t.tags && t.tags.includes('Layer: ' + activeLayer))
              ).map(t => (
                <div key={t.id} style={{ background: '#111', padding: '1rem', border: '1px solid #222', borderRadius: '8px' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.5rem' }}>
                    <strong style={{ color: 'var(--neon-purple)', fontSize: '0.8rem' }}>{t.thought_id}</strong>
                    <div style={{ display: 'flex', gap: '0.6rem' }}>
                      <button onClick={() => onRestore(t.id)} style={{ background: 'transparent', color: '#10b981', border: 'none' }}><RotateCcw size={16} /></button>
                      <button onClick={() => onEradicate(t.id)} style={{ background: 'transparent', color: '#ef4444', border: 'none' }}><Trash2 size={16} /></button>
                    </div>
                  </div>
                  <p style={{ color: '#ccc', margin: 0, fontSize: '0.85rem', whiteSpace: 'pre-wrap' }}>{t.content}</p>
                </div>
              ))
            ) : (
              vaultedTrash.map(t => (
                <div key={t.id} style={{ opacity: 0.7, background: '#000', padding: '1rem', border: '1px dashed #ef4444', borderRadius: '8px' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.5rem' }}>
                    <strong style={{ color: '#ef4444', fontSize: '0.8rem' }}>DESTROYED: {t.thought_id}</strong>
                    <div style={{ display: 'flex', gap: '0.6rem' }}>
                      <button onClick={() => onRestoreFromTrash(t.id)} style={{ background: 'transparent', color: '#10b981', border: 'none' }}><RotateCcw size={16} /></button>
                      <button onClick={() => onPermanentEradicate(t.id)} style={{ background: 'transparent', color: '#ef4444', border: 'none' }}><AlertTriangle size={16} /></button>
                    </div>
                  </div>
                  <p style={{ color: '#666', margin: 0, fontSize: '0.85rem', whiteSpace: 'pre-wrap' }}>{t.content}</p>
                </div>
              ))
            )}
            </div>
          </div>
        </div>
        
        <button onClick={onWipe} style={{ marginTop: '1rem', background: 'transparent', border: 'none', color: '#ef4444', fontSize: '0.6rem', letterSpacing: '2px', opacity: 0.6, width: '100%' }}>
          INITIATE SELF-DESTRUCT WIPE
        </button>
      </main>
    </div>
  );
}
