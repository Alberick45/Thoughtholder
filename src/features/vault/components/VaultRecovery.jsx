import React, { useState, useEffect, useRef } from 'react';
import { db, generateUUID } from '../../../shared/infrastructure/db';

/**
 * VaultRecovery — Phase 1 of Strategist 2.0
 *
 * Orphan definition:
 *   A vault layer that exists in `hydraTriggers` but whose linked document
 *   was deleted from `db.documents`, OR a layer that has vaulted thoughts
 *   but zero trigger pointing to it.
 *
 * Reassignment flow:
 *   1. User picks any existing WineCellar document (or uploads a new one).
 *   2. Sets the click-count trigger (default 3).
 *   3. Saves to `hydraTriggers` — old dead trigger is removed.
 *   4. hydraConfigs (the Arsenal password) is NEVER touched.
 *   5. Next time user opens WineCellar and clicks that document N times,
 *      it opens the vault exactly as before.
 */
export default function VaultRecovery({ onClose, onReassignComplete }) {
  const [orphanedLayers, setOrphanedLayers] = useState([]);
  const [libraryDocs, setLibraryDocs]       = useState([]);
  const [selectedLayer, setSelectedLayer]   = useState(null);
  const [selectedDocId, setSelectedDocId]   = useState(null);
  const [clickCount, setClickCount]         = useState(3);
  const [savedMsg, setSavedMsg]             = useState('');
  const [step, setStep]                     = useState('list'); // 'list' | 'pick-doc'
  const [showAllLayers, setShowAllLayers]   = useState(false);
  const [allLayers, setAllLayers]           = useState([]);
  const [usedDocIds, setUsedDocIds]         = useState(new Set()); // docs already assigned to a live vault
  const uploadRef                           = useRef(null);

  useEffect(() => { boot(); }, []);

  /* ── Load orphaned layers + WineCellar library ──────────────────────────── */
  const boot = async () => {
    const [triggersRow, configsRow, docs, allThoughts] = await Promise.all([
      db.settings.get('hydraTriggers'),
      db.settings.get('hydraConfigs'),
      db.documents.toArray(),
      db.thoughts.toArray(),
    ]);

    const triggers = triggersRow ? triggersRow.value : {};   // { docId: { clicks, targetLayer } }
    const configs  = configsRow ? configsRow.value : {};     // { layer: { ... } }
    const docIds   = new Set(docs.map(d => String(d.id)));

    /* Build a map: targetLayer → { docId, clicks } for triggers that are ALIVE */
    const aliveLayerMap = {};
    const liveTriggerDocIds = new Set();
    for (const [docId, cfg] of Object.entries(triggers)) {
      if (docIds.has(String(docId))) {
        const layer = cfg.targetLayer ?? '';
        aliveLayerMap[layer] = { docId, clicks: cfg.clicks };
        liveTriggerDocIds.add(String(docId)); // mark as in-use
      }
    }
    setUsedDocIds(liveTriggerDocIds);

    /* Collect every layer key mentioned in vaulted thoughts OR in security configs */
    const vaultedLayerSet = new Set();
    
    // 1. From thoughts
    for (const t of allThoughts) {
      if (t.status !== 'vaulted' && t.status !== 'vaulted_trash') continue;
      const tags = Array.isArray(t.tags) ? t.tags : [];
      const layerTag = tags.find(x => x.startsWith('Layer: '));
      vaultedLayerSet.add(layerTag ? layerTag.replace('Layer: ', '') : '');
    }

    // 2. From security configs (allows recovery of empty vaults)
    for (const layer of Object.keys(configs)) {
      vaultedLayerSet.add(layer);
    }

    /* Orphans: layers that exist in system but have NO alive trigger */
    const orphans = [];
    for (const layer of vaultedLayerSet) {
      if (aliveLayerMap[layer]) continue; // trigger is fine
      const count = allThoughts.filter(t => {
        if (t.status !== 'vaulted' && t.status !== 'vaulted_trash') return false;
        const tags = Array.isArray(t.tags) ? t.tags : [];
        const tLayer = tags.find(x => x.startsWith('Layer: '))?.replace('Layer: ', '') || '';
        return tLayer === layer;
      }).length;
      orphans.push({
        key:         layer,
        displayName: layer === '' ? 'Base Arsenal' : `Layer: ${layer}`,
        count,
      });
    }

    /* Also catch dead-trigger entries (doc deleted) for layers that might
       have zero vaulted thoughts — still need cleaning */
    for (const [docId, cfg] of Object.entries(triggers)) {
      if (docIds.has(String(docId))) continue; // alive
      const layer = cfg.targetLayer ?? '';
      if (!orphans.some(o => o.key === layer)) {
        orphans.push({
          key:         layer,
          displayName: layer === '' ? 'Base Arsenal' : `Layer: ${layer}`,
          count:       0,
          deadTrigger: true,
        });
      }
    }

    setOrphanedLayers(orphans);
    setLibraryDocs(docs);
    
    // Store all layers for debug view with source forensic data
    const all = Array.from(vaultedLayerSet).map(key => {
      const sources = [];
      if (allThoughts.some(t => ((t.status === 'vaulted' || t.status === 'vaulted_trash') && ((Array.isArray(t.tags) ? t.tags : []).find(x => x.startsWith('Layer: '))?.replace('Layer: ', '') || '') === key))) sources.push('Thoughts');
      if (configs[key]) sources.push('Password/Config');
      const triggersForThisLayer = Object.entries(triggers).filter(([dId, c]) => (c.targetLayer ?? '') === key);
      if (triggersForThisLayer.length > 0) sources.push(`Triggers(${triggersForThisLayer.length})`);

      return {
        key,
        displayName: key === '' ? 'Base Arsenal' : `Layer: ${key}`,
        isOrphan: orphans.some(o => o.key === key),
        sources: sources.join(', ')
      };
    });
    setAllLayers(all);

    console.log("[VAULT RECOVERY] Scanned Triggers:", triggers);
    console.log("[VAULT RECOVERY] Scanned Configs:", configs);
    console.log("[VAULT RECOVERY] Orphans Found:", orphans);
  };

  /* ── Start reassignment flow for a layer ───────────────────────────────── */
  const startReassign = (layer) => {
    setSelectedLayer(layer);
    setSelectedDocId(null);
    setClickCount(3);
    setSavedMsg('');
    setStep('pick-doc');
  };

  /* ── Upload a brand-new document into WineCellar + auto-select it ──────── */
  const handleUploadNewDoc = async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    let type = 'DOC';
    if (file.type.includes('pdf'))   type = 'PDF';
    if (file.type.includes('image')) type = 'IMAGE';
    if (file.type.includes('video')) type = 'VIDEO';
    const newDoc = {
      id:       generateUUID(),
      title:    file.name.replace(/\.[^/.]+$/, ''),
      type,
      author:   file.type || 'Unknown Format',
      date:     new Date().toISOString().split('T')[0],
      fileData: file,
    };
    await db.documents.add(newDoc);
    setLibraryDocs(prev => [...prev, newDoc]);
    setSelectedDocId(newDoc.id);
    uploadRef.current.value = '';
  };

  /* ── Confirm: write new trigger, purge dead ones ───────────────────────── */
  const handleConfirmLink = async () => {
    if (!selectedLayer || !selectedDocId) {
      alert('Select a document from your library first.');
      return;
    }

    const triggersRow = await db.settings.get('hydraTriggers');
    const triggers    = triggersRow ? { ...triggersRow.value } : {};

    /* Remove any old dead triggers pointing to this same layer */
    for (const [docId, cfg] of Object.entries(triggers)) {
      const layer = cfg.targetLayer ?? '';
      if (layer === selectedLayer.key) delete triggers[docId];
    }

    /* Write the new live trigger */
    triggers[selectedDocId] = {
      clicks:      clickCount,
      targetLayer: selectedLayer.key,
    };

    await db.settings.put({ key: 'hydraTriggers', value: triggers });

    setSavedMsg(`✓ "${selectedLayer.displayName}" is now linked to "${libraryDocs.find(d => d.id === selectedDocId)?.title}". Open WineCellar and click it ${clickCount}× to enter.`);
    setStep('list');
    setSelectedLayer(null);
    await boot();

    if (onReassignComplete) onReassignComplete(selectedLayer.key);
  };

  /* ── Styles ─────────────────────────────────────────────────────────────── */
  const S = {
    overlay: {
      position: 'fixed', inset: 0,
      background: 'rgba(0,0,0,0.93)',
      backdropFilter: 'blur(14px)',
      zIndex: 9999,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
    },
    modal: {
      background: 'linear-gradient(145deg, #0d0d14 0%, #090910 100%)',
      border: '1px solid rgba(139,92,246,0.35)',
      borderRadius: '18px',
      padding: '2.5rem',
      width: 'min(660px, 96vw)',
      maxHeight: '88vh',
      overflowY: 'auto',
      boxShadow: '0 0 80px rgba(139,92,246,0.12), 0 24px 60px rgba(0,0,0,0.9)',
      position: 'relative',
    },
    title: {
      fontFamily: 'monospace', fontSize: '1.35rem', fontWeight: '900',
      letterSpacing: '3px', color: '#8b5cf6', textTransform: 'uppercase',
      margin: '0 0 0.25rem 0',
    },
    sub: {
      color: '#6b7280', fontSize: '0.82rem', letterSpacing: '0.5px',
      marginBottom: '2rem', lineHeight: 1.6,
    },
    layerCard: (sel) => ({
      background: sel ? 'rgba(139,92,246,0.1)' : '#111',
      border: `1px solid ${sel ? '#8b5cf6' : '#222'}`,
      borderRadius: '10px', padding: '1rem 1.4rem', marginBottom: '0.7rem',
      display: 'flex', justifyContent: 'space-between', alignItems: 'center',
      cursor: 'pointer', transition: 'all 0.18s',
    }),
    orphanPill: {
      background: 'rgba(239,68,68,0.12)', color: '#ef4444',
      border: '1px solid rgba(239,68,68,0.3)',
      borderRadius: '20px', padding: '2px 10px',
      fontSize: '0.72rem', fontWeight: 'bold', whiteSpace: 'nowrap',
    },
    docCard: (sel) => ({
      background: sel ? 'rgba(139,92,246,0.12)' : '#0f0f18',
      border: `1.5px solid ${sel ? '#8b5cf6' : '#1e1e2e'}`,
      borderRadius: '8px', padding: '0.85rem 1.1rem',
      display: 'flex', alignItems: 'center', gap: '0.75rem',
      cursor: 'pointer', transition: 'all 0.15s',
      marginBottom: '0.5rem',
    }),
    docIcon: (type) => {
      const c = type === 'PDF' ? '#ef4444' : type === 'IMAGE' ? '#10b981' : type === 'VIDEO' ? '#3b82f6' : '#f59e0b';
      return { width: '32px', height: '32px', borderRadius: '6px', background: `${c}22`, color: c, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '0.75rem', fontWeight: 'bold', flexShrink: 0 };
    },
    btn: (v) => ({
      padding: '0.7rem 1.4rem', borderRadius: '8px', border: 'none',
      cursor: 'pointer', fontWeight: 'bold', fontSize: '0.88rem',
      background: v === 'primary' ? '#8b5cf6' : v === 'green' ? 'rgba(16,185,129,0.15)' : 'transparent',
      color: v === 'primary' ? 'white' : v === 'green' ? '#10b981' : '#6b7280',
      ...(v === 'ghost' && { border: '1px solid #2a2a3a' }),
      ...(v === 'green' && { border: '1px solid rgba(16,185,129,0.35)' }),
    }),
    clickRow: {
      display: 'flex', alignItems: 'center', gap: '1rem',
      background: '#0a0a14', border: '1px solid #1e1e2e',
      borderRadius: '8px', padding: '0.75rem 1rem', marginTop: '1rem',
    },
  };

  const typeEmoji = { PDF: 'PDF', IMAGE: '🖼', VIDEO: '▶', DOC: '📄' };

  /* ── Render ─────────────────────────────────────────────────────────────── */
  return (
    <div style={S.overlay}>
      <div style={S.modal}>

        {/* Close */}
        <button onClick={onClose} style={{ position: 'absolute', top: '1.1rem', right: '1.1rem', background: 'transparent', border: 'none', color: '#555', fontSize: '1.4rem', cursor: 'pointer', lineHeight: 1 }}>✕</button>

        <h2 style={S.title}>🔓 Vault Recovery Protocol</h2>
        <p style={S.sub}>
          Your security document was deleted or unlinked.<br/>
          Pick a new document from your library — it becomes the new hidden entry point to that vault.<br/>
          <span style={{ color: '#4b5563' }}>Your vault passwords and payloads are untouched.</span>
        </p>

        {/* Success banner */}
        {savedMsg && (
          <div style={{ background: 'rgba(16,185,129,0.08)', border: '1px solid rgba(16,185,129,0.35)', color: '#10b981', padding: '0.85rem 1rem', borderRadius: '8px', marginBottom: '1.5rem', fontSize: '0.88rem', lineHeight: 1.5 }}>
            {savedMsg}
          </div>
        )}

        {/* ── Step: list orphaned vaults ─────────────────────────────────── */}
        {step === 'list' && (
          <>
            {orphanedLayers.length === 0 ? (
              <div style={{ textAlign: 'center', color: '#6b7280', padding: '3rem 0' }}>
                <div style={{ fontSize: '2.5rem', marginBottom: '1rem' }}>🛡️</div>
                <p style={{ fontSize: '1rem' }}>No orphaned vaults detected.</p>
                <p style={{ fontSize: '0.82rem' }}>Every vault in system memory has an active trigger document.</p>
              </div>
            ) : (
              <>
                <p style={{ color: '#9ca3af', fontSize: '0.82rem', marginBottom: '1rem' }}>
                  {orphanedLayers.length} vault{orphanedLayers.length > 1 ? 's' : ''} with missing trigger. Click one to re-link it to a document.
                </p>
                {orphanedLayers.map(layer => (
                  <div
                    key={layer.key}
                    style={S.layerCard(false)}
                    onClick={() => startReassign(layer)}
                  >
                    <div>
                      <div style={{ color: 'white', fontWeight: '700', fontSize: '0.97rem', marginBottom: '0.15rem' }}>
                        {layer.displayName}
                      </div>
                      <div style={{ color: '#6b7280', fontSize: '0.78rem' }}>
                        {layer.count > 0
                          ? `${layer.count} encrypted payload${layer.count !== 1 ? 's' : ''} inside`
                          : 'Empty secure layer (no payloads)'}
                      </div>
                    </div>
                    <span style={S.orphanPill}>RE-LINK REQUIRED</span>
                  </div>
                ))}
              </>
            )}

            <div style={{ borderTop: '1px solid #222', marginTop: '2rem', paddingTop: '1.5rem' }}>
               <button onClick={() => setShowAllLayers(!showAllLayers)} style={{ background: 'transparent', border: 'none', color: '#8b5cf6', fontSize: '0.8rem', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                  {showAllLayers ? '▼ Hide System Map' : '▶ Reveal All Known Layers (Debug Mode)'}
               </button>
               {showAllLayers && (
                 <div style={{ marginTop: '1rem', display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                   {allLayers.map(l => (
                     <div key={l.key} style={{ background: '#0a0a0a', padding: '0.8rem 1rem', borderRadius: '4px', border: '1px solid #111', display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.4rem' }}>
                        <div>
                          <div style={{ fontSize: '0.85rem', color: l.isOrphan ? '#ef4444' : '#10b981', fontWeight: 'bold' }}>{l.displayName}</div>
                          <div style={{ fontSize: '0.65rem', color: '#555', textTransform: 'uppercase', letterSpacing: '1px', marginTop: '2px' }}>Sources: {l.sources || 'None'}</div>
                        </div>
                        <button onClick={() => startReassign(l)} style={{ background: 'transparent', border: '1px solid #333', color: 'white', fontSize: '0.7rem', padding: '4px 10px', borderRadius: '4px', cursor: 'pointer' }}>Forced Link</button>
                     </div>
                   ))}
                   {allLayers.length === 0 && <p style={{ fontSize: '0.75rem', color: '#4b5563' }}>No layers registered in system memory.</p>}
                 </div>
               )}
            </div>
          </>
        )}

        {/* ── Step: pick document ────────────────────────────────────────── */}
        {step === 'pick-doc' && selectedLayer && (
          <div>
            {/* Back */}
            <button onClick={() => { setStep('list'); setSelectedLayer(null); }} style={{ ...S.btn('ghost'), marginBottom: '1.5rem', fontSize: '0.8rem', padding: '0.4rem 0.9rem' }}>
              ← Back
            </button>

            <div style={{ background: 'rgba(139,92,246,0.07)', border: '1px solid rgba(139,92,246,0.2)', borderRadius: '8px', padding: '0.85rem 1rem', marginBottom: '1.5rem' }}>
              <div style={{ color: '#8b5cf6', fontWeight: '700', fontSize: '0.9rem', marginBottom: '0.2rem' }}>Linking: {selectedLayer.displayName}</div>
              <div style={{ color: '#6b7280', fontSize: '0.78rem' }}>Choose which document in your library will open this vault when clicked the right number of times.</div>
            </div>

            {/* Upload a new doc */}
            <input type="file" ref={uploadRef} style={{ display: 'none' }} accept=".pdf,.txt,.epub,image/*,video/*" onChange={handleUploadNewDoc} />
            <button onClick={() => uploadRef.current.click()} style={{ ...S.btn('ghost'), width: '100%', marginBottom: '1.25rem', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '0.5rem' }}>
              <span style={{ fontSize: '1rem' }}>📤</span> Upload a New Document to Link
            </button>

            {/* Existing library */}
            {libraryDocs.length === 0 ? (
              <p style={{ color: '#4b5563', fontSize: '0.85rem', textAlign: 'center', padding: '1rem 0' }}>
                No documents in library yet. Upload one above.
              </p>
            ) : (
              <>
                <p style={{ color: '#6b7280', fontSize: '0.8rem', marginBottom: '0.75rem' }}>Or select an existing library document:</p>
                <div style={{ maxHeight: '240px', overflowY: 'auto', paddingRight: '2px' }}>
                  {libraryDocs.map(doc => {
                    const isInUse = usedDocIds.has(String(doc.id));
                    return (
                      <div
                        key={doc.id}
                        style={S.docCard(selectedDocId === doc.id)}
                        onClick={() => setSelectedDocId(doc.id)}
                      >
                        <div style={S.docIcon(doc.type)}>
                          {typeEmoji[doc.type] || '📄'}
                        </div>
                        <div style={{ flex: 1, minWidth: 0 }}>
                          <div style={{ color: 'white', fontWeight: '600', fontSize: '0.9rem', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                            {doc.title}
                          </div>
                          <div style={{ color: '#4b5563', fontSize: '0.75rem' }}>
                            {doc.type} · {doc.date}
                            {isInUse && <span style={{ color: 'var(--neon-purple)', marginLeft: '8px' }}>(Already Linked)</span>}
                          </div>
                        </div>
                        {selectedDocId === doc.id && (
                          <div style={{ color: '#8b5cf6', fontSize: '1.1rem' }}>✓</div>
                        )}
                      </div>
                    );
                  })}
                </div>
              </>
            )}

            {/* Click count selector */}
            {selectedDocId && (
              <div style={S.clickRow}>
                <span style={{ color: '#9ca3af', fontSize: '0.85rem', flex: 1 }}>
                  How many clicks on this document to open the vault?
                </span>
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                  <button onClick={() => setClickCount(c => Math.max(1, c - 1))} style={{ width: '28px', height: '28px', borderRadius: '50%', background: '#1e1e2e', border: '1px solid #333', color: 'white', cursor: 'pointer', fontSize: '1rem', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>−</button>
                  <span style={{ color: '#8b5cf6', fontWeight: 'bold', fontSize: '1.1rem', minWidth: '24px', textAlign: 'center' }}>{clickCount}</span>
                  <button onClick={() => setClickCount(c => Math.min(10, c + 1))} style={{ width: '28px', height: '28px', borderRadius: '50%', background: '#1e1e2e', border: '1px solid #333', color: 'white', cursor: 'pointer', fontSize: '1rem', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>+</button>
                </div>
              </div>
            )}

            {/* Confirm */}
            <div style={{ display: 'flex', gap: '0.75rem', marginTop: '1.5rem' }}>
              <button
                onClick={handleConfirmLink}
                disabled={!selectedDocId}
                style={{ ...S.btn('primary'), opacity: selectedDocId ? 1 : 0.4, cursor: selectedDocId ? 'pointer' : 'not-allowed' }}
              >
                🔗 Link Document to Vault
              </button>
              <button onClick={() => { setStep('list'); setSelectedLayer(null); }} style={S.btn('ghost')}>Cancel</button>
            </div>
          </div>
        )}

        {/* Footer close */}
        {step === 'list' && (
          <div style={{ marginTop: '2rem', textAlign: 'center' }}>
            <button onClick={onClose} style={S.btn('ghost')}>Close Recovery Protocol</button>
          </div>
        )}

      </div>
    </div>
  );
}
