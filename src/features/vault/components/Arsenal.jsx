import React, { useState } from 'react';

export default function Arsenal({ forcedLayer, vaultedThoughts, vaultedTrash = [], credentialsList = [], onLockDown, onStoreIntel, onConfig, onRestore, onEradicate, onWipe, onPermanentEradicate, onRestoreFromTrash, onRelocate }) {
  const [intelText, setIntelText] = useState('');
  const [intelLayer, setIntelLayer] = useState('');
  const [isAddingMode, setIsAddingMode] = useState(false);
  const [viewState, setViewState] = useState('intel'); // 'intel' | 'trash'
  const [activeLayer, setActiveLayer] = useState(forcedLayer || ''); // '' means Base Payload
  
  // Dynamic Sync: If forcedLayer changes, update local state
  React.useEffect(() => {
    if (forcedLayer !== undefined) {
      setActiveLayer(forcedLayer);
    }
  }, [forcedLayer]);

  return (
    <div style={{ background: '#050505', backgroundImage: 'radial-gradient(circle at 50% 50%, rgba(139, 92, 246, 0.05) 0%, transparent 50%)', height: '100vh', display: 'flex', flexDirection: 'column' }}>
      <div style={{ height: '30px', width: '100vw', background: 'transparent', position: 'fixed', top: 0, WebkitAppRegion: 'drag', zIndex: 1000 }}></div>
      <main className="arsenal-main" style={{ padding: '2rem', flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column', maxWidth: '1000px', margin: '0 auto', width: '100%' }}>
        <header className="arsenal-header" style={{ marginBottom: '2rem', display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '1rem' }}>
          <div>
            <h1 style={{ fontWeight: '900', fontSize: '2rem', color: 'var(--neon-purple)', margin: 0, letterSpacing: '4px', textTransform: 'uppercase' }}>Strategy Arsenal</h1>
            <p style={{ color: 'var(--text-muted)', fontSize: '0.8rem', letterSpacing: '1px' }}>LEVEL 4 CIPHER: ACTIVE {forcedLayer ? `[SEALED SUB-LAYER: ${forcedLayer}]` : ''}</p>
          </div>
          <div className="arsenal-header-actions" style={{ display: 'flex', gap: '1rem', flexWrap: 'wrap' }}>
            <button 
              onClick={onConfig}
              style={{ background: 'transparent', color: 'var(--text-muted)', border: '1px solid #333', padding: '0.6rem 1.2rem', fontWeight: 'bold', letterSpacing: '1px', borderRadius: '4px', cursor: 'pointer', flex: '1 1 auto' }}
            >
              CONFIG
            </button>
            <button 
              onClick={() => setIsAddingMode(!isAddingMode)}
              style={{ background: 'transparent', color: 'var(--neon-purple)', border: '1px solid var(--neon-purple)', padding: '0.6rem 1.2rem', fontWeight: 'bold', letterSpacing: '1px', borderRadius: '4px', cursor: 'pointer', flex: '1 1 auto' }}
            >
              STORE INTEL
            </button>
            <button 
              onClick={onLockDown}
              style={{ background: 'rgba(239, 68, 68, 0.1)', color: '#ef4444', border: '1px solid #ef4444', padding: '0.6rem 1.2rem', fontWeight: 'bold', letterSpacing: '1px', borderRadius: '4px', cursor: 'pointer', flex: '1 1 auto' }}
            >
              LOCK DOWN
            </button>
          </div>
        </header>

        {isAddingMode && (
          <div style={{ padding: '1rem', background: 'black', border: '1px solid var(--neon-purple)', borderRadius: '8px', marginBottom: '2rem', display: 'flex', gap: '1rem', flexDirection: 'column' }}>
            <div style={{ display: 'flex', gap: '1rem' }}>
              <input 
                 type="text" 
                 placeholder="Custom Sub-Layer (Optional, e.g. 5, 6, Delta)" 
                 value={intelLayer} 
                 onChange={(e) => setIntelLayer(e.target.value)} 
                 style={{ flex: 1, background: '#111', color: 'white', border: '1px solid #333', padding: '0.8rem', borderRadius: '4px' }}
              />
            </div>
            <textarea 
               placeholder="Write raw classified payload..." 
               value={intelText} 
               onChange={(e) => setIntelText(e.target.value)} 
               style={{ width: '100%', minHeight: '100px', background: '#111', color: 'white', padding: '1rem', border: 'none', borderRadius: '4px' }}
            />
            <button 
              onClick={() => { 
                if(intelText.trim() || intelLayer.trim()) { 
                  const text = intelText.trim() || `[Sub-Layer "${intelLayer.trim()}" Initialized]`;
                  const tags = intelLayer.trim() ? [`Layer: ${intelLayer.trim()}`] : (forcedLayer ? [`Layer: ${forcedLayer}`] : []);
                  onStoreIntel(text, tags); 
                  setIntelText(''); 
                  setIntelLayer('');
                  setIsAddingMode(false); 
                } 
              }} 
              style={{ background: 'var(--neon-purple)', color: 'white', border: 'none', padding: '0.8rem', fontWeight: 'bold', borderRadius: '4px', cursor: 'pointer' }}
            >
              Encrypt payload to Database
            </button>
          </div>
        )}

        <div style={{ display: 'grid', gridTemplateColumns: '1fr', gap: '2rem', marginTop: '1rem', flex: 1, overflowY: 'auto' }}>
          <div style={{ border: '1px solid var(--neon-purple)', background: 'black', padding: '2rem', borderRadius: '8px', overflowY: 'auto' }}>
            
            {/* Dynamic Layers Tab System */}
            {!forcedLayer && (
            <div style={{ display: 'flex', gap: '0.5rem', marginBottom: '1.5rem', flexWrap: 'wrap' }}>
              <button 
                onClick={() => setActiveLayer('')} 
                style={{ background: activeLayer === '' ? 'var(--neon-purple)' : '#111', color: activeLayer === '' ? 'white' : 'var(--text-muted)', border: 'none', padding: '0.4rem 1rem', borderRadius: '20px', fontSize: '0.8rem', cursor: 'pointer' }}>
                Base Arsenal
              </button>
              
              {/* Extract all unique sub-layers dynamically */}
              {Array.from(new Set(vaultedThoughts.flatMap(t => t.tags || []).filter(tag => tag.startsWith('Layer: ')))).map(layerTag => {
                const pureLayerName = layerTag.replace('Layer: ', '');
                return (
                  <button 
                    key={layerTag}
                    onClick={() => setActiveLayer(pureLayerName)} 
                    style={{ background: activeLayer === pureLayerName ? 'var(--neon-purple)' : '#111', color: activeLayer === pureLayerName ? 'white' : 'var(--text-muted)', border: 'none', padding: '0.4rem 1rem', borderRadius: '20px', fontSize: '0.8rem', cursor: 'pointer' }}>
                    Layer: {pureLayerName}
                  </button>
                )
              })}
            </div>
            )}

            <div className="arsenal-tabs-header" style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px solid #333', paddingBottom: '0.5rem', marginBottom: '1rem', flexWrap: 'wrap', gap: '1rem' }}>
              <h3 style={{ color: 'white', margin: 0 }}>Active Intel</h3>
              <div style={{ display: 'flex', gap: '1rem', flexWrap: 'wrap' }}>
                <button onClick={() => setViewState('intel')} style={{ background: 'transparent', border: 'none', color: viewState === 'intel' ? 'var(--neon-purple)' : 'var(--text-muted)', cursor: 'pointer', fontWeight: viewState === 'intel' ? 'bold' : 'normal', padding: '0.5rem 0' }}>Payloads</button>
                <button onClick={() => setViewState('credentials')} style={{ background: 'transparent', border: 'none', color: viewState === 'credentials' ? 'var(--accent-blue)' : 'var(--text-muted)', cursor: 'pointer', fontWeight: viewState === 'credentials' ? 'bold' : 'normal', padding: '0.5rem 0' }}>Credentials</button>
                <button onClick={() => setViewState('trash')} style={{ background: 'transparent', border: 'none', color: viewState === 'trash' ? '#ef4444' : 'var(--text-muted)', cursor: 'pointer', fontWeight: viewState === 'trash' ? 'bold' : 'normal', padding: '0.5rem 0' }}>Deep Trash ({vaultedTrash.length})</button>
              </div>
            </div>
            
            {viewState === 'intel' ? (
              (() => {
                const filtered = vaultedThoughts.filter(t => {
                  const tags = Array.isArray(t.tags) ? t.tags : [];
                  const tLayer = tags.find(x => x.startsWith('Layer: '))?.replace('Layer: ', '') || '';
                  return tLayer === activeLayer;
                });
                if (filtered.length === 0) {
                  return <p style={{ color: 'var(--text-muted)', fontSize: '0.9rem', marginBottom: '1rem' }}>No operational blueprints stored in this sub-layer.</p>;
                }
                return (
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
                    {filtered.map(t => (
                      <div key={t.id} style={{ background: '#111', padding: '1rem', border: '1px solid #222', borderRadius: '4px' }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                          <strong style={{ color: 'var(--neon-purple)' }}>{t.thought_id}</strong>
                          <div className="arsenal-item-actions" style={{ display: 'flex', gap: '0.8rem', flexWrap: 'wrap', justifyContent: 'flex-end' }}>
                            <button onClick={() => onRelocate && onRelocate(t)} title="Move to different layer" style={{ background: 'transparent', color: 'var(--neon-purple)', border: '1px solid var(--neon-purple)', padding: '2px 8px', borderRadius: '4px', cursor: 'pointer', fontSize: '0.75rem' }}>Transfer</button>
                            <button onClick={() => onRestore(t.id)} title="Send back to Decoy" style={{ background: 'transparent', color: 'white', border: 'none', cursor: 'pointer', fontSize: '0.75rem' }}>Restore to Decoy</button>
                            <button onClick={() => onEradicate(t.id)} title="Send to Deep Trash" style={{ background: 'transparent', color: '#ef4444', border: 'none', cursor: 'pointer', fontSize: '0.75rem' }}>Eradicate</button>
                          </div>
                        </div>
                        <p style={{ color: '#ccc', margin: '0.5rem 0 0 0', whiteSpace: 'pre-wrap' }}>{t.content}</p>
                      </div>
                    ))}
                  </div>
                );
              })()
            ) : viewState === 'credentials' ? (
              credentialsList.length === 0 ? (
                <p style={{ color: 'var(--text-muted)', fontSize: '0.9rem', marginBottom: '1rem' }}>No external service credentials stored in Level 4.</p>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
                  {credentialsList.map(service => (
                    <div key={service} style={{ background: '#0a0a14', padding: '1rem', border: '1px solid #1e1e2e', borderRadius: '8px', display: 'flex', alignItems: 'center', gap: '1rem' }}>
                      <div style={{ width: '12px', height: '12px', borderRadius: '50%', background: '#10b981', boxShadow: '0 0 10px #10b98166' }}></div>
                      <div style={{ flex: 1 }}>
                        <div style={{ color: 'white', fontWeight: 'bold', letterSpacing: '1px' }}>{service}</div>
                        <div style={{ color: 'var(--text-muted)', fontSize: '0.75rem' }}>Encrypted AES-GCM Bridge: ACTIVE</div>
                      </div>
                      <div style={{ fontSize: '0.7rem', color: '#10b981', background: 'rgba(16, 185, 129, 0.1)', padding: '0.2rem 0.6rem', borderRadius: '4px', border: '1px solid #10b98133' }}>SECURED</div>
                    </div>
                  ))}
                  <p style={{ color: 'var(--text-muted)', fontSize: '0.75rem', marginTop: '1rem', textAlign: 'center' }}>
                    * Credentials are encrypted with your primary Arsenal password and never stored in plaintext.
                  </p>
                </div>
              )
            ) : (
              vaultedTrash.length === 0 ? (
                <p style={{ color: 'var(--text-muted)', fontSize: '0.9rem', marginBottom: '1rem' }}>Deep Trash is empty.</p>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
                  {vaultedTrash.map(t => (
                    <div key={t.id} style={{ opacity: 0.7, background: '#0a0a0a', padding: '1rem', border: '1px dashed #ef4444', borderRadius: '4px' }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                        <strong style={{ color: '#ef4444' }}>[ERADICATED] {t.thought_id}</strong>
                        <div style={{ display: 'flex', gap: '0.5rem' }}>
                          <button onClick={() => onRestoreFromTrash(t.id)} style={{ background: 'transparent', color: '#10b981', border: 'none', cursor: 'pointer', fontSize: '0.8rem' }}>Restore Payload</button>
                          <button onClick={() => onPermanentEradicate(t.id)} style={{ background: 'transparent', color: '#ef4444', border: 'none', cursor: 'pointer', fontSize: '0.8rem', fontWeight: 'bold' }}>Destroy Permanently</button>
                        </div>
                      </div>
                      <p style={{ color: '#888', margin: '0.5rem 0 0 0', whiteSpace: 'pre-wrap' }}>{t.content}</p>
                    </div>
                  ))}
                </div>
              )
            )}
          </div>
        </div>
        
        <div onClick={onWipe} style={{ paddingTop: '2rem', paddingBottom: '1rem', textAlign: 'center' }}>
          <p style={{ color: '#ef4444', fontSize: '0.8rem', letterSpacing: '2px', cursor: 'pointer', opacity: 0.8 }}>⚠ INITIATE SELF-DESTRUCT CORRUPTION WIPE</p>
        </div>
      </main>
    </div>
  );
}
