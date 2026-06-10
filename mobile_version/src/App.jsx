import React, { useState, useEffect, useMemo, useRef } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import Fuse from 'fuse.js';

// Infrastructure & Config
import { db, updateThought, addThought, generateUUID } from './shared/infrastructure/db';
import { decryptData, encryptData } from './shared/utils/crypto';
import { SECURITY_CONFIG, AI_CONFIG } from './core/config/constants';

// Hooks & Layout
import { useBackgroundDaemons } from './app/hooks/useBackgroundDaemons';
import MobileHeader from './app/layout/MobileHeader';
import GlobalWidget from './app/layout/GlobalWidget'; // Local mobile version

// Features
import InputBar from './features/brain-dump/components/InputBar';
import ThoughtCard from './features/brain-dump/components/ThoughtCard';
import Arsenal from './features/vault/components/Arsenal';
import WineCellar from './features/vault/components/WineCellar';
import CalendarView from './features/visuals/components/CalendarView';
import JarvisChat from './features/intelligence/components/JarvisChat';
import VisionDrop from './features/intelligence/components/VisionDrop';

export default function App() {
  const thoughts = useLiveQuery(() => db.thoughts.orderBy('created_at').reverse().toArray()) || [];
  const [filter, setFilter] = useState('attention');
  const [searchQuery, setSearchQuery] = useState('');
  const [showWidget, setShowWidget] = useState(false);
  const [widgetTab, setWidgetTab] = useState('jarvis');
  const [jarvisOfflineAlert, setJarvisOfflineAlert] = useState(false);
  const [unreadJarvis, setUnreadJarvis] = useState(0);
  const [jarvisPreview, setJarvisPreview] = useState('');
  const [jarvisLeash, setJarvisLeash] = useState(localStorage.getItem('jarvis_leash') || '1');
  const fileInputRef = useRef(null);

  // App Level
  const [appLevel, setAppLevel] = useState(SECURITY_CONFIG.VAULT_LEVELS.DECK);
  const [showVaultSetup, setShowVaultSetup] = useState(false);
  const [hasConfig, setHasConfig] = useState(false);
  const [isReconfiguringMode, setIsReconfiguringMode] = useState(false);
  const [vaultType, setVaultType] = useState('password');
  const [vaultPassword, setVaultPassword] = useState('');
  const [activeTargetLayer, setActiveTargetLayer] = useState('');
  const [pictureFiles, setPictureFiles] = useState([]);
  const [pictureSequence, setPictureSequence] = useState([]);
  const [decryptSequence, setDecryptSequence] = useState([]);
  const [linkingTarget, setLinkingTarget] = useState(null);

  // Background Hooks
  useBackgroundDaemons(db, addThought, setUnreadJarvis, setJarvisPreview, setJarvisOfflineAlert);

  const openVaultUI = async (targetLayer = '') => {
    setActiveTargetLayer(targetLayer);
    const store = await db.settings.get('hydraConfigs');
    const configs = store ? store.value : {};
    const config = configs[targetLayer];

    if (config) {
      setHasConfig(true);
      setVaultType(config.type);
      if (config.type === 'picture') setPictureFiles(config.images || []);
    } else {
      setHasConfig(false);
      setVaultType('password');
    }
    setVaultPassword('');
    setDecryptSequence([]);
    setPictureSequence([]);
    setShowVaultSetup(true);
  };

  useEffect(() => {
    const handleEncryptedBulk = async (e) => {
      const cipherText = e.detail;
      const pwd = prompt('Classified Payload Detected. Password:');
      if (!pwd) return;
      try {
        const plainText = await decryptData(pwd, cipherText);
        const importedData = JSON.parse(plainText);
        const { intelligentMerge } = await import('./shared/infrastructure/db');
        await intelligentMerge(importedData);
        alert('Payload Merged.');
      } catch (err) { alert('Decryption Failed.'); }
    };
    window.addEventListener('hiveEncryptedBulk', handleEncryptedBulk);
    const handleKeyDown = (e) => { if (e.ctrlKey && e.shiftKey && e.key.toLowerCase() === 'v') setAppLevel(2); };
    window.addEventListener('keydown', handleKeyDown);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
      window.removeEventListener('hiveEncryptedBulk', handleEncryptedBulk);
    };
  }, []);

  const displayedThoughts = useMemo(() => {
    try {
      let base = thoughts.filter(t => {
        if (filter === 'suggestions') return t.type === 'suggestion';
        if (filter === 'event') return t.type === 'event';
        if (filter === 'tobuy') return t.type === 'buy';
        if (filter === 'todo') return t.type === 'task';
        return t.status !== 'vaulted' && t.status !== 'vaulted_trash' && t.type !== 'jarvis_log' && t.type !== 'suggestion' && t.type !== 'event' && t.type !== 'buy' && t.type !== 'task';
      });

      if (filter === 'attention') base = base.filter(t => (t.status === 'fresh' || t.status === 'active' || t.status === 'ignored'));
      else if (filter === 'archived') base = base.filter(t => t.status === 'archived');
      else if (filter === 'trash') base = base.filter(t => t.status === 'trash');
      else if (filter === 'all') base = base.filter(t => t.status !== 'trash');

      if (searchQuery.trim() !== '') {
        const fuse = new Fuse(base, { keys: ['content', 'thought_id', 'type'], threshold: 0.3 });
        return fuse.search(searchQuery).map(result => result.item);
      }
      return base;
    } catch (err) {
      return [];
    }
  }, [thoughts, filter, searchQuery]);

  const activeTodosCount = useMemo(() => {
    return thoughts.filter(t => t.status !== 'trash' && t.status !== 'vaulted' && t.status !== 'vaulted_trash' && t.type !== 'jarvis_log' && t.type === 'task').length;
  }, [thoughts]);

  const handleCardAction = (action, payload) => {
    if (action === 'link') setLinkingTarget(payload);
    else if (action === 'navigate') {
      const target = thoughts.find(t => t.id === payload || t.thought_id === payload);
      if (target) {
        if ((target.status === 'vaulted' || target.status === 'vaulted_trash') && appLevel !== 4) return;
        if (target.status === 'archived') setFilter('archived');
        else if (target.status === 'trash') setFilter('trash');
        else if (target.type === 'buy') setFilter('tobuy');
        else if (target.type === 'task') setFilter('todo');
        else setFilter('all');
        setSearchQuery(target.thought_id);
      }
    }
  };

  const GlobalWidgetComp = (
    <div style={{ position: 'fixed', bottom: '1.5rem', right: '1.5rem', zIndex: 5000, display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: '1rem' }}>
      {showWidget && (
        <div className="glass-panel slide-up" style={{ width: '90vw', maxWidth: '400px', height: '70vh', background: 'rgba(15, 15, 20, 0.95)', display: 'flex', flexDirection: 'column', boxShadow: '0 12px 40px rgba(0,0,0,0.8)', border: '1px solid var(--border-focus)', borderRadius: '12px', overflow: 'hidden' }}>
          <div style={{ display: 'flex', background: 'rgba(0,0,0,0.5)', borderBottom: '1px solid var(--border-subtle)', padding: '0.5rem' }}>
            {['jarvis', 'calendar', 'vision'].map(tab => (
              <button key={tab} onClick={() => setWidgetTab(tab)} style={{ flex: 1, padding: '0.8rem', background: widgetTab === tab ? 'rgba(139, 92, 246, 0.2)' : 'transparent', color: widgetTab === tab ? 'white' : 'var(--text-muted)', border: 'none', fontWeight: 'bold', cursor: 'pointer' }}>{tab.toUpperCase()}</button>
            ))}
          </div>
          <div style={{ flex: 1, padding: '1rem', overflowY: 'auto' }}>
            {widgetTab === 'jarvis' && <JarvisChat inVault={appLevel === 4} chatLogs={thoughts.filter(t => t.type === 'jarvis_log').sort((a, b) => a.created_at - b.created_at)} />}
            {widgetTab === 'calendar' && <CalendarView thoughts={thoughts} />}
            {widgetTab === 'vision' && <VisionDrop onExtracted={(text) => { /* OCR Logic */ }} />}
          </div>
        </div>
      )}
      <button onClick={() => { setShowWidget(!showWidget); setUnreadJarvis(0); }} style={{ width: '56px', height: '56px', borderRadius: '50%', background: showWidget ? 'var(--neon-purple)' : 'var(--bg-secondary)', border: '2px solid var(--border-focus)', color: 'white', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '1.2rem' }}>
        {showWidget ? '✕' : '🧠'}
      </button>
    </div>
  );

  try {
    if (appLevel === 4) {
      return (
        <>
          <Arsenal
            forcedLayer={activeTargetLayer}
            vaultedThoughts={thoughts.filter(t => t.status === 'vaulted')}
            vaultedTrash={thoughts.filter(t => t.status === 'vaulted_trash')}
            allThoughts={thoughts}
            onLockDown={() => { setAppLevel(1); setHasConfig(false); setActiveTargetLayer(''); }}
            onConfig={async () => { setIsReconfiguringMode(true); setAppLevel(2); setShowVaultSetup(true); }}
            onStoreIntel={async (text, tags = []) => { await db.thoughts.add({ id: generateUUID(), type: 'thought', status: 'vaulted', thought_id: 'VLT-' + Math.floor(Math.random() * 9999), content: text, tags, created_at: Date.now(), last_viewed_at: Date.now(), stale_score: 0 }); }}
            onRestore={async (id) => { await updateThought(id, { status: 'fresh' }); }}
            onEradicate={async (id) => { await updateThought(id, { status: 'vaulted_trash' }); }}
            onWipe={async () => { (await db.thoughts.toArray()).forEach(t => { if (t.status === 'vaulted' || t.status === 'vaulted_trash') db.thoughts.delete(t.id); }); await db.settings.clear(); window.location.reload(); }}
          />
          {GlobalWidgetComp}
        </>
      );
    }

    if (appLevel === 2) {
      return (
        <div className="app-container" style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', background: 'var(--bg-primary)' }}>
          <WineCellar onNavigateDeeper={openVaultUI} onLockDown={() => setAppLevel(1)} />
          {GlobalWidgetComp}
        </div>
      );
    }

    return (
      <div className="app-container" style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', background: 'var(--bg-primary)', padding: '1rem' }}>
        <MobileHeader jarvisLeash={jarvisLeash} setJarvisLeash={setJarvisLeash} jarvisOfflineAlert={jarvisOfflineAlert} setJarvisOfflineAlert={setJarvisOfflineAlert} />

        <main style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: '1.5rem', minHeight: 0 }}>
          <InputBar onCommandTrigger={async (cmd, payload) => {
            if (cmd === 'vault') setAppLevel(2);
            else if (cmd === 'trash') setFilter('trash');
            else if (cmd === 'tobuy') setFilter('tobuy');
            else if (cmd === 'todo') setFilter('todo');
            else if (cmd === 'reset_db') {
              if (window.confirm("Nuclear Wipe?")) {
                await db.thoughts.clear();
                await db.settings.clear();
                window.location.reload();
              }
            }
            else if (cmd === 'jarvis') {
              setShowWidget(true); setWidgetTab('jarvis');
              if (payload) {
                const now = Date.now();
                await addThought({ id: generateUUID(), thought_id: `Query-${Math.floor(Math.random() * 9000)}`, content: `**You:** ${payload}`, type: 'jarvis_log', status: 'archived', tags: [], created_at: now, last_viewed_at: now, stale_score: 0, linked_thoughts: [] });
              }
            }
          }} />

          <div style={{ display: 'flex', overflowX: 'auto', gap: '0.5rem', paddingBottom: '0.5rem' }}>
            {['attention', 'all', 'todo', 'tobuy', 'archived', 'trash', 'suggestions', 'event'].map(f => (
              <button key={f} onClick={() => setFilter(f)} style={{ padding: '0.4rem 1rem', borderRadius: '12px', background: filter === f ? 'var(--neon-purple)' : 'var(--bg-secondary)', color: 'white', border: '1px solid var(--border-subtle)', whiteSpace: 'nowrap', fontSize: '0.8rem' }}>{f.toUpperCase()}</button>
            ))}
          </div>

          <div style={{ flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: '1rem' }}>
            {displayedThoughts.map(t => (
              <ThoughtCard key={t.id} thought={t} onAction={handleCardAction} />
            ))}
          </div>
        </main>

        {GlobalWidgetComp}
      </div>
    );
  } catch (err) {
    return (
      <div style={{ background: '#0a0a0c', color: '#f87171', height: '100vh', padding: '2rem', display: 'flex', flexDirection: 'column', justifyContent: 'center', alignItems: 'center', textAlign: 'center' }}>
        <h2 style={{ marginBottom: '1rem' }}>SYSTEM CORE DISRUPTION</h2>
        <p style={{ marginBottom: '2rem', opacity: 0.8 }}>{err.message}</p>
        <button onClick={() => window.location.reload()} style={{ background: '#3b82f6', color: 'white' }}>Re-Initiate Matrix</button>
      </div>
    );
  }
}
