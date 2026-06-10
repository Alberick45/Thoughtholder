import React, { useState, useEffect, useRef } from 'react';
import { Book, FileText, UploadCloud, Search, Settings } from 'lucide-react';
import { db, generateUUID } from '../../../shared/infrastructure/db';

export default function WineCellar({ onNavigateDeeper, onLockDown, showHiddenFiles }) {
  const [documents, setDocuments] = useState([]);
  const [existingLayers, setExistingLayers] = useState([]);

  const [stealthTriggerSequence, setStealthTriggerSequence] = useState({ id: null, count: 0 });
  const [triggerConfig, setTriggerConfig] = useState({});
  const [setupMode, setSetupMode] = useState(null);
  const [setupClicks, setSetupClicks] = useState(3);
  const [setupTargetLayer, setSetupTargetLayer] = useState('');
  const [activeMedia, setActiveMedia] = useState(null);
  const [searchQuery, setSearchQuery] = useState('');
  const fileInputRef = useRef(null);

  useEffect(() => {
    // Load documents from DB or use defaults
    const loadData = async () => {
      let docs = await db.documents.toArray();
      setDocuments(docs);
      
      const config = await db.settings.get('hydraTriggers');
      if (config) setTriggerConfig(config.value);
      else setTriggerConfig({});

      // Load existing vault configurations + any layers used in thoughts
      const vaultStore = await db.settings.get('hydraConfigs');
      const allThoughts = await db.thoughts.toArray();
      const layersInThoughts = new Set(allThoughts.flatMap(t => t.tags || []).filter(tag => tag.startsWith('Layer: ')).map(tag => tag.replace('Layer: ', '')));
      
      const configLayers = vaultStore ? Object.keys(vaultStore.value) : [];
      const combined = Array.from(new Set(['', ...configLayers, ...layersInThoughts]));
      setExistingLayers(combined);
    };
    loadData();
  }, []);

  const handleDocClick = (doc) => {
    setActiveMedia(doc);

    // Click anywhere on the active media to process trigger
    const trigger = triggerConfig[doc.id];
    if (trigger) {
      const newCount = stealthTriggerSequence.id === doc.id ? stealthTriggerSequence.count + 1 : 1;
      setStealthTriggerSequence({ id: doc.id, count: newCount });
      
      if (newCount >= trigger.clicks) {
        setActiveMedia(null); // Abort decoy view immediately
        onNavigateDeeper(trigger.targetLayer);
        setStealthTriggerSequence({ id: null, count: 0 });
      }
    } else {
      setStealthTriggerSequence({ id: null, count: 0 });
    }
  };

  const handleDocRightClick = (e, id) => {
    e.preventDefault();
    setSetupMode(id);
    const existing = triggerConfig[id];
    setSetupClicks(existing ? existing.clicks : 3);
    setSetupTargetLayer(existing ? existing.targetLayer : '');
  };

  const toggleHideDoc = async (id, currentHidden) => {
    await db.documents.update(id, { hidden: !currentHidden });
    setDocuments(prev => prev.map(d => d.id === id ? { ...d, hidden: !currentHidden } : d));
    setSetupMode(null);
  };

  const handleUpload = async (e) => {
    const files = Array.from(e.target.files);
    for (const file of files) {
      let type = 'DOC';
      if (file.type.includes('pdf')) type = 'PDF';
      if (file.type.includes('image')) type = 'IMAGE';
      if (file.type.includes('video')) type = 'VIDEO';

      const newDoc = {
        id: generateUUID(),
        title: file.name.replace(/\.[^/.]+$/, ""),
        type: type,
        author: file.type || 'Unknown Format',
        date: new Date().toISOString().split('T')[0],
        fileData: file
      };
      await db.documents.add(newDoc);
      setDocuments(prev => [...prev, newDoc]);
    }
    fileInputRef.current.value = '';
  };

  return (
    <div style={{ background: '#050505', height: '100vh', color: '#E5E7EB', fontFamily: 'serif', display: 'flex', flexDirection: 'column' }}>
      <div style={{ height: '30px', width: '100vw', background: 'transparent', position: 'absolute', top: 0, WebkitAppRegion: 'drag', zIndex: 1000 }}></div>
      <header className="vault-header" style={{ background: '#000000', padding: '1.5rem', borderBottom: '1px solid #222', display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '1rem' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.8rem' }}>
          <Book size={24} color="#6B7280" />
          <h1 style={{ fontSize: '1.5rem', fontWeight: '500', margin: 0, letterSpacing: '-0.5px', color: 'white' }}>Personal Library</h1>
        </div>
        <div className="vault-header-actions" style={{ display: 'flex', gap: '1rem', alignItems: 'center', flexWrap: 'wrap' }}>
          <div style={{ position: 'relative', flex: '1 1 200px' }}>
            <Search size={16} style={{ position: 'absolute', left: '10px', top: '10px', color: '#6B7280' }} />
            <input 
              type="text" 
              placeholder="Search volumes..." 
              value={searchQuery} 
              onChange={e => setSearchQuery(e.target.value)}
              style={{ width: '100%', padding: '0.5rem 1rem 0.5rem 2.2rem', borderRadius: '4px', border: '1px solid #333', background: '#111', color: 'white', boxSizing: 'border-box' }} 
            />
          </div>
          <input type="file" ref={fileInputRef} style={{ display: 'none' }} multiple accept=".pdf,.txt,.epub,image/*,video/*" onChange={handleUpload} />
          <button onClick={() => fileInputRef.current.click()} style={{ background: '#3B82F6', color: 'white', border: 'none', padding: '0.5rem 1rem', borderRadius: '4px', fontWeight: '500', display: 'flex', alignItems: 'center', gap: '0.5rem', cursor: 'pointer' }}>
            <UploadCloud size={16} /> Import Document
          </button>
          <button onClick={onLockDown} style={{ background: 'transparent', color: '#6B7280', border: 'none', cursor: 'pointer', fontSize: '0.9rem' }}>Disconnect</button>
        </div>
      </header>
      
      <main className="vault-main" style={{ padding: '1.5rem', maxWidth: '1200px', margin: '0 auto', flex: 1, width: '100%', overflowY: 'auto' }}>
        <p style={{ color: '#6B7280', marginBottom: '2rem', display: 'flex', justifyContent: 'space-between' }}>
          <span>Archived Research & Strategic Manuscripts</span>
        </p>

        {activeMedia && (
          <div onClick={() => handleDocClick(activeMedia)} style={{ position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, background: 'rgba(0,0,0,0.9)', zIndex: 9999, padding: '2rem', display: 'flex', flexDirection: 'column' }}>
            <div onClick={(e) => e.stopPropagation()} style={{ background: '#111', borderRadius: '8px', flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden', border: '1px solid #333' }}>
              <div style={{ padding: '1rem', background: '#000', display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid #333' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                  <FileText size={18} color="#3B82F6" />
                  <h3 style={{ margin: 0, color: 'white' }}>{activeMedia.title}</h3>
                </div>
                <button onClick={(e) => { e.stopPropagation(); setActiveMedia(null); }} style={{ background: '#EF4444', color: 'white', border: 'none', padding: '0.4rem 1rem', borderRadius: '4px', cursor: 'pointer', fontWeight: 'bold' }}>Close Media Viewer</button>
              </div>
              <div onClick={() => handleDocClick(activeMedia)} style={{ flex: 1, position: 'relative', background: '#1a1a1a', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                {activeMedia.fileData ? (
                  activeMedia.type === 'IMAGE' ? (
                    <img src={URL.createObjectURL(activeMedia.fileData)} style={{ maxWidth: '100%', maxHeight: '100%', objectFit: 'contain' }} alt="media resource" />
                  ) : activeMedia.type === 'VIDEO' ? (
                    <video src={URL.createObjectURL(activeMedia.fileData)} controls style={{ maxWidth: '100%', maxHeight: '100%' }} />
                  ) : (
                    <iframe src={URL.createObjectURL(activeMedia.fileData)} style={{ width: '100%', height: '100%', border: 'none' }} title={activeMedia.title} />
                  )
                ) : (
                  <div style={{ textAlign: 'center', color: '#6B7280' }}>
                    <p style={{ fontSize: '1.2rem', marginBottom: '0.5rem' }}>Media Render Engine Offline.</p>
                  </div>
                )}
              </div>
            </div>
          </div>
        )}

        {setupMode && (
          <div style={{ position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, background: 'rgba(0,0,0,0.85)', backdropFilter: 'blur(10px)', zIndex: 10001, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <div className="glass-panel animate-slide-up" style={{ padding: '2.5rem', width: '90vw', maxWidth: '450px', border: '1px solid var(--neon-purple)', boxShadow: '0 0 50px rgba(139,92,246,0.2)' }}>
              <h3 style={{ margin: '0 0 1.5rem 0', color: 'var(--neon-purple)', fontSize: '1.5rem', letterSpacing: '2px', textTransform: 'uppercase' }}>Configure Deep Guard</h3>
              
              <div style={{ marginBottom: '1.5rem' }}>
                <p style={{ color: 'var(--text-muted)', fontSize: '0.8rem', marginBottom: '0.5rem' }}>TRIGGER INTENSITY (CLICKS)</p>
                <input type="number" value={setupClicks} onChange={e => setSetupClicks(parseInt(e.target.value) || 1)} min="1" max="10" style={{ padding: '0.8rem', width: '100%', border: '1px solid #333', background: 'black', color: 'white', borderRadius: '4px' }} />
              </div>

              <div style={{ marginBottom: '1.5rem' }}>
                <p style={{ color: 'var(--text-muted)', fontSize: '0.8rem', marginBottom: '0.5rem' }}>TARGET ARSENAL LAYER</p>
                <input 
                  type="text" 
                  value={setupTargetLayer} 
                  onChange={e => setSetupTargetLayer(e.target.value)} 
                  placeholder="Base Arsenal (Empty) or Custom ID" 
                  style={{ padding: '0.8rem', width: '100%', marginBottom: '0.5rem', border: '1px solid #333', background: 'black', color: 'white', borderRadius: '4px' }} 
                />
                
                <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap', marginTop: '0.8rem' }}>
                  <span style={{ fontSize: '0.7rem', color: 'var(--text-muted)', width: '100%', marginBottom: '0.2rem' }}>ATTACH TO EXISTING ARSENAL:</span>
                  {existingLayers.map(l => (
                    <button 
                      key={l} 
                      onClick={() => setSetupTargetLayer(l)} 
                      style={{ 
                        background: setupTargetLayer === l ? 'var(--neon-purple)' : '#222', 
                        border: 'none', 
                        color: 'white', 
                        fontSize: '0.75rem', 
                        padding: '0.4rem 0.8rem', 
                        borderRadius: '4px', 
                        cursor: 'pointer',
                        transition: 'background 0.2s'
                      }}
                    >
                      {l === '' ? 'BASE ARSENAL' : l}
                    </button>
                  ))}
                </div>
                <button onClick={() => setSetupTargetLayer('Arsenal-' + Math.floor(1000 + Math.random() * 9000))} style={{ marginTop: '0.8rem', background: 'transparent', border: '1px dashed var(--neon-purple)', color: 'var(--neon-purple)', width: '100%', padding: '0.5rem', fontSize: '0.8rem', cursor: 'pointer' }}>+ Generate Unique Private Arsenal</button>
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1rem', marginTop: '2rem' }}>
                <button onClick={async () => {
                  const newTriggers = { ...triggerConfig, [setupMode]: { clicks: setupClicks, targetLayer: setupTargetLayer.trim() } };
                  await db.settings.put({ key: 'hydraTriggers', value: newTriggers });
                  setTriggerConfig(newTriggers);
                  setSetupMode(null);
                }} style={{ background: 'var(--neon-purple)', color: 'white', border: 'none', padding: '1rem', borderRadius: '4px', cursor: 'pointer', fontWeight: 'bold' }}>Save Alignment</button>
                <button onClick={() => setSetupMode(null)} style={{ background: 'transparent', border: '1px solid #333', color: 'white', padding: '1rem', borderRadius: '4px', cursor: 'pointer' }}>Cancel</button>
              </div>

              <div style={{ marginTop: '1.5rem', borderTop: '1px solid #222', paddingTop: '1.5rem', display: 'flex', flexDirection: 'column', gap: '0.8rem' }}>
                <button 
                  onClick={() => toggleHideDoc(setupMode, documents.find(d => d.id === setupMode)?.hidden)}
                  style={{ width: '100%', background: 'rgba(59, 130, 246, 0.1)', color: '#3B82F6', border: '1px solid #3B82F6', padding: '0.6rem', borderRadius: '4px', cursor: 'pointer', fontSize: '0.9rem' }}
                >
                  {documents.find(d => d.id === setupMode)?.hidden ? 'Unhide Document' : 'Hide Document (Ctrl+Shift+L to reveal)'}
                </button>
                <button 
                  onClick={async () => {
                    await db.documents.delete(setupMode);
                    setDocuments(prev => prev.filter(d => d.id !== setupMode));
                    setSetupMode(null);
                  }} 
                  style={{ width: '100%', background: 'rgba(239, 68, 68, 0.1)', color: '#EF4444', border: '1px solid #EF4444', padding: '0.6rem', borderRadius: '4px', cursor: 'pointer', fontSize: '0.9rem' }}
                >
                  Destroy Document Permanently
                </button>
              </div>
            </div>
          </div>
        )}
        
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))', gap: '2rem', paddingBottom: '4rem' }}>
          {documents
            .filter(doc => (!doc.hidden || showHiddenFiles))
            .filter(doc => doc.title.toLowerCase().includes(searchQuery.toLowerCase()) || doc.author.toLowerCase().includes(searchQuery.toLowerCase()))
            .map(doc => (
            <div 
              key={doc.id} 
              onClick={() => handleDocClick(doc)}
              onContextMenu={(e) => handleDocRightClick(e, doc.id)}
              style={{ position: 'relative', background: '#111', border: doc.hidden ? '1px dashed #3B82F6' : (triggerConfig[doc.id] ? '2px dashed #333' : '1px solid #222'), borderRadius: '8px', padding: '1.5rem', cursor: 'pointer', transition: 'box-shadow 0.2s, transform 0.2s', opacity: doc.hidden ? 0.6 : 1 }}
            >
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '1rem' }}>
                <span style={{ fontSize: '0.8rem', background: '#000', color: doc.hidden ? '#3B82F6' : '#6B7280', padding: '2px 8px', borderRadius: '4px', fontWeight: 'bold' }}>{doc.hidden ? 'HIDDEN' : doc.type}</span>
                <span style={{ fontSize: '0.8rem', color: '#4B5563' }}>{doc.date}</span>
              </div>
              <h3 style={{ margin: '0 0 0.5rem 0', color: 'white', fontSize: '1.2rem', fontWeight: '600' }}>{doc.title}</h3>
              <p style={{ margin: 0, color: '#6B7280', fontSize: '0.9rem', display: 'flex', alignItems: 'center', gap: '0.4rem' }}><FileText size={14} /> {doc.author}</p>
            </div>
          ))}
        </div>
      </main>
    </div>
  );
}
