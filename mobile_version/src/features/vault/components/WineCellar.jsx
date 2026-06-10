import React, { useState, useEffect, useRef, useCallback } from 'react';
import { Book, FileText, UploadCloud, Search, Settings, X, Trash2, Save } from 'lucide-react';
import { db, generateUUID } from '../../../shared/infrastructure/db';
import { useLongPress } from '../../../shared/hooks/useLongPress';

export default function WineCellar({ onNavigateDeeper, onLockDown }) {
  const [documents, setDocuments] = useState([]);
  const [stealthTriggerSequence, setStealthTriggerSequence] = useState({ id: null, count: 0 });
  const [triggerConfig, setTriggerConfig] = useState({});
  const [setupMode, setSetupMode] = useState(null);
  const [setupClicks, setSetupClicks] = useState(3);
  const [setupTargetLayer, setSetupTargetLayer] = useState('');
  const [activeMedia, setActiveMedia] = useState(null);
  const [searchQuery, setSearchQuery] = useState('');
  const fileInputRef = useRef(null);

  useEffect(() => {
    const loadData = async () => {
      let docs = await db.documents.toArray();
      setDocuments(docs);
      const config = await db.settings.get('hydraTriggers');
      if (config) setTriggerConfig(config.value);
    };
    loadData();
  }, []);

  const handleDocClick = (doc) => {
    setActiveMedia(doc);
    const trigger = triggerConfig[doc.id];
    if (trigger) {
      const newCount = stealthTriggerSequence.id === doc.id ? stealthTriggerSequence.count + 1 : 1;
      setStealthTriggerSequence({ id: doc.id, count: newCount });
      if (newCount >= trigger.clicks) {
        setActiveMedia(null);
        onNavigateDeeper(trigger.targetLayer);
        setStealthTriggerSequence({ id: null, count: 0 });
      }
    } else {
      setStealthTriggerSequence({ id: null, count: 0 });
    }
  };

  const handleLongPress = useCallback((docId) => {
    setSetupMode(docId);
    const existing = triggerConfig[docId];
    setSetupClicks(existing ? existing.clicks : 3);
    setSetupTargetLayer(existing ? existing.targetLayer : '');
  }, [triggerConfig]);

  const handleUpload = async (e) => {
    const files = Array.from(e.target.files);
    for (const file of files) {
      const newDoc = {
        id: generateUUID(),
        title: file.name.replace(/\.[^/.]+$/, ""),
        type: file.type.includes('pdf') ? 'PDF' : (file.type.includes('image') ? 'IMAGE' : (file.type.includes('video') ? 'VIDEO' : 'DOC')),
        author: file.type || 'Generic Format',
        date: new Date().toISOString().split('T')[0],
        fileData: file
      };
      await db.documents.add(newDoc);
      setDocuments(prev => [...prev, newDoc]);
    }
  };

  return (
    <div style={{ background: '#050505', height: '100vh', color: '#E5E7EB', display: 'flex', flexDirection: 'column', position: 'relative' }}>
      <header style={{ background: '#000', padding: '1rem', borderBottom: '1px solid #222', display: 'flex', flexWrap: 'wrap', gap: '1rem', alignItems: 'center' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.6rem', flex: 1 }}>
          <Book size={20} color="#6B7280" />
          <h1 style={{ fontSize: '1.2rem', fontWeight: '500', margin: 0, color: 'white' }}>Library</h1>
        </div>
        <div style={{ display: 'flex', gap: '0.8rem', alignItems: 'center' }}>
          <button onClick={() => fileInputRef.current.click()} style={{ background: '#3B82F6', color: 'white', border: 'none', padding: '0.5rem', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <UploadCloud size={18} />
          </button>
          <button onClick={onLockDown} style={{ background: 'transparent', color: '#6B7280', border: 'none', fontSize: '0.8rem' }}>Exit</button>
        </div>
        <div style={{ width: '100%', position: 'relative' }}>
          <Search size={14} style={{ position: 'absolute', left: '10px', top: '10px', color: '#6B7280' }} />
          <input 
            type="text" 
            placeholder="Search volumes..." 
            value={searchQuery} 
            onChange={e => setSearchQuery(e.target.value)}
            style={{ width: '100%', padding: '0.5rem 1rem 0.5rem 2rem', borderRadius: '8px', border: '1px solid #333', background: '#111', color: 'white', fontSize: '0.9rem' }} 
          />
        </div>
        <input type="file" ref={fileInputRef} style={{ display: 'none' }} multiple accept=".pdf,.txt,image/*,video/*" onChange={handleUpload} />
      </header>
      
      <main style={{ flex: 1, overflowY: 'auto', padding: '1rem' }}>
        {activeMedia && (
          <div onClick={() => handleDocClick(activeMedia)} style={{ position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, background: 'rgba(0,0,0,0.95)', zIndex: 9999, display: 'flex', flexDirection: 'column' }}>
            <div style={{ padding: '0.8rem', display: 'flex', justifyContent: 'space-between', alignItems: 'center', background: '#000', borderBottom: '1px solid #222' }}>
              <span style={{ color: 'white', fontSize: '0.9rem', fontWeight: 'bold', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{activeMedia.title}</span>
              <button onClick={(e) => { e.stopPropagation(); setActiveMedia(null); }} style={{ background: '#EF4444', color: 'white', border: 'none', padding: '0.4rem 0.8rem', borderRadius: '4px', fontSize: '0.8rem' }}>Close</button>
            </div>
            <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', background: '#111' }}>
                {activeMedia.fileData ? (
                  activeMedia.type === 'IMAGE' ? <img src={URL.createObjectURL(activeMedia.fileData)} style={{ maxWidth: '100%', maxHeight: '100%', objectFit: 'contain' }} /> :
                  activeMedia.type === 'VIDEO' ? <video src={URL.createObjectURL(activeMedia.fileData)} controls style={{ maxWidth: '100%', maxHeight: '100%' }} /> :
                  <iframe src={URL.createObjectURL(activeMedia.fileData)} style={{ width: '100%', height: '100%', border: 'none' }} />
                ) : <p style={{ color: '#6B7280' }}>Render Offline</p>}
            </div>
          </div>
        )}

        {setupMode && (
          <div style={{ position: 'fixed', bottom: 0, left: 0, right: 0, background: '#111', padding: '1.5rem', borderTop: '2px solid var(--neon-purple)', zIndex: 10000, borderRadius: '20px 20px 0 0', boxShadow: '0 -10px 40px rgba(0,0,0,0.8)' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '1.5rem' }}>
              <h3 style={{ margin: 0, color: 'white' }}>Trigger Pattern</h3>
              <button onClick={() => setSetupMode(null)}><X size={20} color="white" /></button>
            </div>
            <div style={{ marginBottom: '1rem' }}>
              <label style={{ display: 'block', color: '#6B7280', fontSize: '0.8rem', marginBottom: '0.4rem' }}>CONSECUTIVE CLICKS</label>
              <input type="number" value={setupClicks} onChange={e => setSetupClicks(parseInt(e.target.value) || 1)} style={{ width: '100%', padding: '0.8rem', background: '#000', border: '1px solid #333', color: 'white', borderRadius: '8px' }} />
            </div>
            <div style={{ marginBottom: '2rem' }}>
              <label style={{ display: 'block', color: '#6B7280', fontSize: '0.8rem', marginBottom: '0.4rem' }}>TARGET ARSENAL LAYER</label>
              <input type="text" value={setupTargetLayer} onChange={e => setSetupTargetLayer(e.target.value)} placeholder="e.g. Delta, Alpha" style={{ width: '100%', padding: '0.8rem', background: '#000', border: '1px solid #333', color: 'white', borderRadius: '8px' }} />
            </div>
            <div style={{ display: 'flex', gap: '0.8rem' }}>
              <button onClick={async () => {
                const newTriggers = { ...triggerConfig, [setupMode]: { clicks: setupClicks, targetLayer: setupTargetLayer.trim() } };
                await db.settings.put({ key: 'hydraTriggers', value: newTriggers });
                setTriggerConfig(newTriggers);
                setSetupMode(null);
              }} style={{ flex: 2, background: '#3B82F6', color: 'white', border: 'none', padding: '1rem', borderRadius: '12px', fontWeight: 'bold' }}>Save Pattern</button>
              <button onClick={async () => {
                await db.documents.delete(setupMode);
                setDocuments(prev => prev.filter(d => d.id !== setupMode));
                setSetupMode(null);
              }} style={{ flex: 1, background: 'rgba(239, 68, 68, 0.2)', border: '1px solid #EF4444', color: '#EF4444', borderRadius: '12px', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Trash2 size={20} />
              </button>
            </div>
          </div>
        )}
        
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(140px, 1fr))', gap: '1rem' }}>
          {documents.filter(doc => doc.title.toLowerCase().includes(searchQuery.toLowerCase())).map(doc => {
            const longPressProps = useLongPress(() => handleLongPress(doc.id));
            return (
              <div 
                key={doc.id} 
                {...longPressProps}
                onClick={() => handleDocClick(doc)}
                style={{ background: '#111', border: triggerConfig[doc.id] ? '1px solid var(--neon-purple)' : '1px solid #222', borderRadius: '12px', padding: '1rem', position: 'relative' }}
              >
                <div style={{ fontSize: '0.7rem', color: '#6B7280', marginBottom: '0.4rem', textTransform: 'uppercase' }}>{doc.type}</div>
                <h3 style={{ margin: 0, color: 'white', fontSize: '0.9rem', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{doc.title}</h3>
                <p style={{ margin: '0.4rem 0 0 0', color: '#4B5563', fontSize: '0.7rem' }}>{doc.author.substring(0, 15)}</p>
                {triggerConfig[doc.id] && <div style={{ position: 'absolute', top: '8px', right: '8px', width: '6px', height: '6px', background: 'var(--neon-purple)', borderRadius: '50%' }}></div>}
              </div>
            );
          })}
        </div>
      </main>
    </div>
  );
}
