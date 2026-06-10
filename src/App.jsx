import React, { useState, useEffect, useMemo } from 'react';
import { SECURITY_CONFIG, AI_CONFIG } from './core/config/constants';
import { useLiveQuery } from 'dexie-react-hooks';
import Fuse from 'fuse.js';

// Infrastructure & Utils
import { db, updateThought, addThought, generateUUID } from './shared/infrastructure/db';
import { credentialManager } from './features/vault/services/credentialManager';

// Hooks
import { useBackgroundDaemons } from './app/hooks/useBackgroundDaemons';
import { useAutoBackup } from './app/hooks/useAutoBackup';

// Layout & Features
import Header from './app/layout/Header';
import GlobalWidget from './app/layout/GlobalWidget';
import VaultSetupUI from './features/vault/components/VaultSetupUI';
import InputBar from './features/brain-dump/components/InputBar';
import ThoughtCard from './features/brain-dump/components/ThoughtCard';
import Arsenal from './features/vault/components/Arsenal';
import WineCellar from './features/vault/components/WineCellar';
import ArchitectureVisualizer from './features/visuals/components/ArchitectureVisualizer';
import CognitiveDashboard from './features/intelligence/components/CognitiveDashboard';
import CognitiveStream from './features/intelligence/components/CognitiveStream';
import VaultRecovery from './features/vault/components/VaultRecovery';
import SecurePrompt from './shared/ui/SecurePrompt';
import SettingsModal from './shared/ui/SettingsModal';
import PwaAlerts from './shared/ui/PwaAlerts';
import { decryptData } from './shared/utils/crypto';

// Cognitive Runtime OS
import './features/intelligence/engines/RuntimeOrchestrator';
import './features/intelligence/engines/RelationshipEngine';
import './features/intelligence/engines/SleepEngine';
import './features/intelligence/engines/ReflectiveEngine';

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
  const [jarvisIsTyping, setJarvisIsTyping] = useState(false);
  const [debugMode, setDebugMode] = useState(localStorage.getItem('jaos_debug') === 'true');
  const [sidebarCollapsed, setSidebarCollapsed] = useState(window.innerWidth < 1000);
  const fileInputRef = React.useRef(null);
  
  // App Level State
  const [appLevel, setAppLevel] = useState(SECURITY_CONFIG.VAULT_LEVELS.DECK); // 1=Deck, 2=WineCellar, 3=Visualizer, 4=Arsenal
  
  // Vault State
  const [showVaultSetup, setShowVaultSetup] = useState(false);
  const [showVaultRecovery, setShowVaultRecovery] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [hasConfig, setHasConfig] = useState(false);
  const [isReconfiguringMode, setIsReconfiguringMode] = useState(false);
  const [vaultType, setVaultType] = useState('password');
  const [vaultPassword, setVaultPassword] = useState('');
  const [activeTargetLayer, setActiveTargetLayer] = useState('');
  const [showHiddenFiles, setShowHiddenFiles] = useState(false);
  const [credentialsList, setCredentialsList] = useState([]);
  const [pictureFiles, setPictureFiles] = useState([]);
  const [pictureSequence, setPictureSequence] = useState([]);
  const [decryptSequence, setDecryptSequence] = useState([]);
  const [targetVaultSelection, setTargetVaultSelection] = useState(null); // { item, onComplete }
  
  const [linkingTarget, setLinkingTarget] = useState(null);

  // Secure Prompt State
  const [promptConfig, setPromptConfig] = useState({ show: false, title: '', message: '', onConfirm: null, onCancel: null });

  const requestSecurePrompt = (title, message) => {
    return new Promise((resolve) => {
      setPromptConfig({
        show: true,
        title,
        message,
        onConfirm: (val) => {
          setPromptConfig(prev => ({ ...prev, show: false }));
          resolve(val);
        },
        onCancel: () => {
          setPromptConfig(prev => ({ ...prev, show: false }));
          resolve(null);
        }
      });
    });
  };

  // Background Daemons
  useBackgroundDaemons(db, addThought, generateUUID, setUnreadJarvis, setJarvisPreview, setJarvisOfflineAlert);
  useAutoBackup(db);

  const openVaultUI = async (targetLayer = '') => {
    setActiveTargetLayer(targetLayer);
    const list = await credentialManager.listServices();
    setCredentialsList(list);
    
    const store = await db.settings.get('hydraConfigs');
    const configs = store ? store.value : {};
    const config = configs[targetLayer];

    // Substantive Check: Ensure config actually has a password or images set
    const isSubstantive = config && (
      (config.type === 'password' && config.password) ||
      (config.type === 'pin' && config.password) ||
      (config.type === 'picture' && Array.isArray(config.images) && config.images.length > 0)
    );

    if (isSubstantive) {
      setHasConfig(true);
      setVaultType(config.type);
      if (config.type === 'picture') setPictureFiles(config.images || []);
    } else {
      setHasConfig(false);
      setVaultType('password');
      setPictureFiles([]);
    }
    setVaultPassword('');
    setDecryptSequence([]);
    setPictureSequence([]);
    setShowVaultSetup(true);
  };

  const jarvisNotify = (msg) => {
    setJarvisPreview(msg);
    setUnreadJarvis(prev => prev + 1);
    // Auto-clear after 5 seconds if widget not open
    setTimeout(() => {
       setJarvisPreview(prev => prev === msg ? '' : prev);
    }, 5000);
  };

  useEffect(() => {
    const handleEncryptedBulk = async (e) => {
      const cipherText = e.detail;
      const pwd = await requestSecurePrompt('Network Sync', 'Incoming classified payload detected! Enter decryption key:');
      if (!pwd) return;
      try {
        const plainText = await decryptData(pwd, cipherText);
        const importedData = JSON.parse(plainText);
        const { intelligentMerge } = await import('./shared/infrastructure/db');
        await intelligentMerge(importedData);
        alert('✓ Payload successfully merged.');
      } catch(err) { alert('Decryption failed. Incorrect key?'); }
    };
    window.addEventListener('hiveEncryptedBulk', handleEncryptedBulk);
    
    const handleKeyDown = (e) => {
      const sKey = localStorage.getItem('jaos_settings_key') || 'i';
      const lKey = localStorage.getItem('jaos_stealth_key') || 'l';
      const vKey = localStorage.getItem('jaos_vault_key') || 'v';

      if (e.ctrlKey && e.shiftKey) {
        const k = e.key.toLowerCase();
        if (k === vKey) setAppLevel(2);
        if (k === sKey) setShowSettings(true);
        if (k === lKey) {
          setShowHiddenFiles(prev => !prev);
          jarvisNotify(`Stealth Visibility: ${!showHiddenFiles ? 'DE-CLOAKED' : 'CLOAKED'}`);
        }
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    
    // Identity Authority Protocol
    const initializeIdentityAuthority = async () => {
      try {
        const { identityAuthority } = await import('./features/intelligence/identity/IdentityAuthority');
        await identityAuthority.getAuthorityState(); // Triggers kernel sync and cache warm
      } catch (err) { console.error("[IDENTITY AUTHORITY BOOT ERROR]", err); }
    };
    initializeIdentityAuthority();

    return () => {
      window.removeEventListener('keydown', handleKeyDown);
      window.removeEventListener('hiveEncryptedBulk', handleEncryptedBulk);
    };
  }, []);

  const handleCardAction = async (action, payload) => {
    if (action === 'link') setLinkingTarget(payload);
    else if (action === 'moved_to_vault') {
      const layersStore = await db.settings.get('hydraConfigs');
      const configLayers = layersStore ? Object.keys(layersStore.value) : [];
      // Forensic Scan: Also include layers mentioned in thoughts
      const thoughtLayers = Array.from(new Set(thoughts.flatMap(t => t.tags || []).filter(tag => tag.startsWith('Layer: ')).map(tag => tag.replace('Layer: ', ''))));
      const allKnownLayers = Array.from(new Set(['', ...configLayers, ...thoughtLayers]));

      setTargetVaultSelection({ 
        item: payload, 
        layers: allKnownLayers,
        onComplete: async (layer) => {
          console.log(`[VAULT ORCHESTRATION] Relocating payload ${payload.thought_id} to target layer: "${layer}"`);
          const tags = Array.isArray(payload.tags) ? payload.tags : [];
          await updateThought(payload.id, { 
            status: 'vaulted', 
            tags: [...tags.filter(t => !t.startsWith('Layer: ')), `Layer: ${layer}`] 
          });
          setTargetVaultSelection(null);
          jarvisNotify(`Payload secured in ${layer || 'Base Arsenal'}.`);
        }
      });
    }
    else if (action === 'navigate') {
      const target = thoughts.find(t => t.id === payload || t.thought_id === payload);
      if (target) {
        if ((target.status === 'vaulted' || target.status === 'vaulted_trash') && appLevel !== 4) return;
        if (target.status === 'archived') setFilter('archived');
        else if (target.status === 'trash') setFilter('trash');
        else setFilter('all');
        setSearchQuery(target.thought_id);
      }
    }
  };

  // --- Filtering & Searching ---
  const displayedThoughts = useMemo(() => {
    let base = thoughts.filter(t => {
      if (filter === 'suggestions') return t.type === 'suggestion';
      if (filter === 'event') return t.type === 'event';
      if (filter === 'tobuy') return t.status !== 'trash' && t.status !== 'vaulted' && t.status !== 'vaulted_trash' && t.type !== 'jarvis_log' && t.type === 'buy';
      if (filter === 'todo') return t.status !== 'trash' && t.status !== 'vaulted' && t.status !== 'vaulted_trash' && t.type !== 'jarvis_log' && t.type !== 'buy' && (t.type === 'task' || (t.content || '').split('\n').some(line => /^\d+\.\s/.test(line) && !line.startsWith('✓ ')));
      return t.status !== 'vaulted' && t.status !== 'vaulted_trash' && t.type !== 'jarvis_log' && t.type !== 'suggestion' && t.type !== 'event' && !t.tags?.includes('jarvis-verified') && t.type !== 'buy';
    });

    if (filter === 'attention') base = base.filter(t => (t.status === 'fresh' || t.status === 'active' || t.status === 'ignored'));
    else if (filter === 'archived') base = base.filter(t => t.status === 'archived');
    else if (filter === 'trash') base = base.filter(t => t.status === 'trash');
    else if (filter === 'all') base = base.filter(t => t.status !== 'trash');

    if (searchQuery.trim() !== '') {
      const fuse = new Fuse(base, { keys: ['content', 'thought_id', 'type'], threshold: 0.3 });
      return fuse.search(searchQuery).map(result => result.item);
    }
    return window.innerWidth < 768 ? base.slice(0, 5) : base;
  }, [thoughts, filter, searchQuery]);

  const activeTodosCount = useMemo(() => {
    return thoughts.filter(t => t.status !== 'trash' && t.status !== 'vaulted' && t.status !== 'vaulted_trash' && t.type !== 'jarvis_log' && t.type !== 'suggestion' && t.type !== 'event' && t.type !== 'buy').reduce((count, t) => {
      const lines = (t.content || '').split('\n');
      const checkboxes = lines.filter(line => /^\d+\.\s/.test(line) || line.startsWith('✓ '));
      
      if (checkboxes.length > 0) {
        // If it has checkboxes, count the unchecked ones
        const pendingInCard = lines.filter(line => /^\d+\.\s/.test(line) && !line.startsWith('✓ ')).length;
        return count + pendingInCard;
      } else if (t.type === 'task') {
        // If it's a task-type card with no checkboxes, it's 1 pending task
        return count + 1;
      }
      return count;
    }, 0);
  }, [thoughts]);

  const activeBuysCount = useMemo(() => {
    return thoughts.filter(t => t.status !== 'trash' && t.status !== 'vaulted' && t.status !== 'vaulted_trash' && t.type !== 'jarvis_log' && t.type === 'buy').reduce((count, t) => {
      const lines = (t.content || '').split('\n');
      const checkboxes = lines.filter(line => /^\d+\.\s/.test(line) || line.startsWith('✓ '));
      
      if (checkboxes.length > 0) {
        const pendingInCard = lines.filter(line => /^\d+\.\s/.test(line) && !line.startsWith('✓ ')).length;
        return count + pendingInCard;
      } else if (t.type === 'buy') {
        return count + 1;
      }
      return count;
    }, 0);
  }, [thoughts]);

  const GlobalWidgetComp = (
    <GlobalWidget 
      showWidget={showWidget} setShowWidget={setShowWidget}
      widgetTab={widgetTab} setWidgetTab={setWidgetTab}
      appLevel={appLevel} thoughts={thoughts}
      unreadJarvis={unreadJarvis} setUnreadJarvis={setUnreadJarvis}
      jarvisPreview={jarvisPreview} setJarvisPreview={setJarvisPreview}
      jarvisIsTyping={jarvisIsTyping}
      setJarvisIsTyping={setJarvisIsTyping}
      debugMode={debugMode}
      setDebugMode={setDebugMode}
    />
  );

  const VaultSetupUIComp = (
    <VaultSetupUI 
      showVaultSetup={showVaultSetup} setShowVaultSetup={setShowVaultSetup}
      isReconfiguringMode={isReconfiguringMode} setIsReconfiguringMode={setIsReconfiguringMode}
      vaultType={vaultType} setVaultType={setVaultType}
      vaultPassword={vaultPassword} setVaultPassword={setVaultPassword}
      pictureFiles={pictureFiles} setPictureFiles={setPictureFiles}
      pictureSequence={pictureSequence} setPictureSequence={setPictureSequence}
      decryptSequence={decryptSequence} setDecryptSequence={setDecryptSequence}
      hasConfig={hasConfig} setHasConfig={setHasConfig}
      activeTargetLayer={activeTargetLayer}
      setAppLevel={setAppLevel} db={db}
      jarvisOfflineAlert={jarvisOfflineAlert} setJarvisOfflineAlert={setJarvisOfflineAlert}
    />
  );

  // Renderers for global modals to avoid duplication
  const renderVaultSelectionModal = () => {
    if (!targetVaultSelection) return null;
    return (
      <div style={{ position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, background: 'rgba(0,0,0,0.85)', backdropFilter: 'blur(10px)', zIndex: 10002, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <div className="glass-panel" style={{ padding: '2rem', width: '90vw', maxWidth: '400px', border: '1px solid var(--neon-purple)', boxShadow: '0 0 30px rgba(139,92,246,0.3)' }}>
          <h3 style={{ color: 'var(--neon-purple)', marginBottom: '1.5rem', letterSpacing: '2px' }}>SELECT TARGET ARSENAL</h3>
          <p style={{ color: 'var(--text-muted)', fontSize: '0.8rem', marginBottom: '1.5rem' }}>Encapsulate payload: <strong>{targetVaultSelection.item.thought_id}</strong></p>
          
          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', maxHeight: '200px', overflowY: 'auto', marginBottom: '1.5rem' }}>
            {targetVaultSelection.layers.map(l => (
              <button key={l} onClick={() => targetVaultSelection.onComplete(l)} style={{ background: '#111', border: '1px solid #333', color: 'white', padding: '0.8rem', borderRadius: '4px', cursor: 'pointer', textAlign: 'left', display: 'flex', justifyContent: 'space-between' }}>
                <span>{l || 'Base Arsenal'}</span>
                <span style={{ color: 'var(--neon-purple)', fontSize: '0.7rem' }}>SELECT</span>
              </button>
            ))}
          </div>

          <div style={{ display: 'flex', gap: '1rem' }}>
            <button onClick={() => {
              const newLayer = prompt('Enter New Arsenal Layer ID:');
              if (newLayer) targetVaultSelection.onComplete(newLayer.trim());
            }} style={{ flex: 1, background: 'transparent', border: '1px dashed var(--neon-purple)', color: 'var(--neon-purple)', padding: '0.8rem', cursor: 'pointer', borderRadius: '4px' }}>+ New Layer</button>
            <button onClick={() => setTargetVaultSelection(null)} style={{ background: 'transparent', border: '1px solid #333', color: 'white', padding: '0.8rem', cursor: 'pointer', borderRadius: '4px' }}>Cancel</button>
          </div>
        </div>
      </div>
    );
  };

  if (appLevel === 4) {
    return (
      <div className="app-container" style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', background: 'var(--bg-primary)' }}>
        <Header jarvisLeash={jarvisLeash} setJarvisLeash={setJarvisLeash} fileInputRef={fileInputRef} setAppLevel={setAppLevel} requestSecurePrompt={requestSecurePrompt} notify={jarvisNotify} />
        <Arsenal 
          forcedLayer={activeTargetLayer}
          vaultedThoughts={thoughts.filter(t => t.status === 'vaulted')} 
          vaultedTrash={thoughts.filter(t => t.status === 'vaulted_trash')}
          allThoughts={thoughts}
          credentialsList={credentialsList}
          onLockDown={() => { 
            setAppLevel(1); 
            setHasConfig(false); 
            setActiveTargetLayer(''); 
            setShowVaultSetup(false);
            setVaultPassword('');
            setDecryptSequence([]);
          }} 
          onConfig={async () => { setIsReconfiguringMode(true); setAppLevel(2); setShowVaultSetup(true); }}
          onStoreIntel={async (text, tags = []) => { await db.thoughts.add({ id: generateUUID(), type: 'thought', status: 'vaulted', thought_id: 'VLT-' + Math.floor(Math.random() * 9999), content: text, tags, created_at: Date.now(), last_viewed_at: Date.now(), stale_score: 0 }); }}
          onRestore={async (id) => { await updateThought(id, { status: 'fresh' }); }}
          onEradicate={async (id) => { await updateThought(id, { status: 'vaulted_trash' }); }}
          onPermanentEradicate={async (id) => { await db.thoughts.delete(id); }}
          onRestoreFromTrash={async (id) => { await updateThought(id, { status: 'vaulted' }); }}
          onRelocate={async (t) => {
            const layersStore = await db.settings.get('hydraConfigs');
            const configLayers = layersStore ? Object.keys(layersStore.value) : [];
            // Forensic Scan: Also include layers mentioned in thoughts
            const thoughtLayers = Array.from(new Set(thoughts.flatMap(th => th.tags || []).filter(tag => tag.startsWith('Layer: ')).map(tag => tag.replace('Layer: ', ''))));
            const allKnownLayers = Array.from(new Set(['', ...configLayers, ...thoughtLayers]));

            setTargetVaultSelection({
              item: t,
              layers: allKnownLayers,
              onComplete: async (layer) => {
                const currentLayer = (Array.isArray(t.tags) ? t.tags : []).find(tag => tag.startsWith('Layer: '))?.replace('Layer: ', '') || '';
                if (layer === currentLayer) {
                  jarvisNotify(`Payload is already in ${layer || 'Base Arsenal'}. No transfer required.`);
                  setTargetVaultSelection(null);
                  return;
                }

                console.log(`[VAULT ORCHESTRATION] Transferring intel ${t.thought_id || '[ID MISSING]'} from "${currentLayer}" to new target layer: "${layer}"`);
                const tags = Array.isArray(t.tags) ? t.tags : [];
                await updateThought(t.id, {
                  tags: [...tags.filter(tag => !tag.startsWith('Layer: ')), `Layer: ${layer}`]
                });
                setTargetVaultSelection(null);
                jarvisNotify(`Payload relocated to ${layer || 'Base Arsenal'}.`);
              }
            });
          }}
          onWipe={async () => { (await db.thoughts.toArray()).forEach(t => { if (t.status === 'vaulted' || t.status === 'vaulted_trash') db.thoughts.delete(t.id); }); await db.settings.clear(); window.location.reload(); }}
        />
        {GlobalWidgetComp}
        {showSettings && <SettingsModal onClose={() => setShowSettings(false)} jarvisNotify={jarvisNotify} />}
        {targetVaultSelection && renderVaultSelectionModal()}
      </div>
    );
  }

  // --- TOTAL PAGE OVERRIDES ---
  if (showVaultSetup) {
    return (
      <div className="app-container" style={{ minHeight: '100vh', background: 'var(--bg-primary)' }}>
        {VaultSetupUIComp}
      </div>
    );
  }

  if (appLevel === 3) {
    return (
      <div className="app-container" style={{ minHeight: '100vh', background: '#000' }}>
        <header style={{ padding: '1rem 2rem', display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid #222' }}>
          <button onClick={() => setAppLevel(1)} style={{ background: 'transparent', color: 'var(--text-muted)', border: 'none', cursor: 'pointer' }}>← Back to Deck</button>
          <div style={{ color: 'var(--neon-purple)', fontWeight: 'bold' }}>STRATEGIST ARCHITECTURE: LEVEL 3</div>
          <div style={{ width: '100px' }}></div>
        </header>
        <div style={{ height: 'calc(100vh - 60px)' }}>
          <ArchitectureVisualizer thoughts={thoughts} onNodeClick={(node) => { setAppLevel(1); setFilter('all'); setSearchQuery(node.thought_id); }} />
        </div>
        {GlobalWidgetComp}
        {showSettings && <SettingsModal onClose={() => setShowSettings(false)} jarvisNotify={jarvisNotify} />}
        {targetVaultSelection && renderVaultSelectionModal()}
      </div>
    );
  }

  if (appLevel === 2) {
    return (
      <div className="app-container" style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', background: 'var(--bg-primary)' }}>
        <Header jarvisLeash={jarvisLeash} setJarvisLeash={setJarvisLeash} fileInputRef={fileInputRef} setAppLevel={setAppLevel} requestSecurePrompt={requestSecurePrompt} notify={jarvisNotify} />
        <WineCellar onNavigateDeeper={openVaultUI} onLockDown={() => { setAppLevel(1); setShowVaultSetup(false); setActiveTargetLayer(''); }} showHiddenFiles={showHiddenFiles} />
        {GlobalWidgetComp}
        {showSettings && <SettingsModal onClose={() => setShowSettings(false)} jarvisNotify={jarvisNotify} />}
        {targetVaultSelection && renderVaultSelectionModal()}
      </div>
    );
  }

  if (appLevel === 5) {
    return (
      <div className="app-container" style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', background: 'var(--bg-primary)' }}>
        <Header jarvisLeash={jarvisLeash} setJarvisLeash={setJarvisLeash} fileInputRef={fileInputRef} setAppLevel={setAppLevel} requestSecurePrompt={requestSecurePrompt} notify={jarvisNotify} />
        <div style={{ flex: 1, overflowY: 'auto' }}>
          <div style={{ maxWidth: '900px', margin: '0 auto' }}>
            <CognitiveDashboard onBack={() => setAppLevel(1)} />
          </div>
        </div>
        {GlobalWidgetComp}
        <CognitiveStream />
        {showSettings && <SettingsModal onClose={() => setShowSettings(false)} jarvisNotify={jarvisNotify} />}
        {targetVaultSelection && renderVaultSelectionModal()}
      </div>
    );
  }

  return (
    <div className="app-container" style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', background: 'var(--bg-primary)' }}>
      <Header jarvisLeash={jarvisLeash} setJarvisLeash={setJarvisLeash} fileInputRef={fileInputRef} setAppLevel={setAppLevel} requestSecurePrompt={requestSecurePrompt} notify={jarvisNotify} />
      
      <div style={{ flex: 1, display: 'flex', overflow: 'hidden', position: 'relative' }}>
        <div className="sidebar-toggle-btn" onClick={() => setSidebarCollapsed(c => !c)} style={{ position: 'absolute', top: '50%', transform: 'translateY(-50%)', zIndex: 2500, width: '24px', height: '48px', background: 'rgba(30,30,38,0.95)', border: '1px solid var(--border-subtle)', borderTopRightRadius: '8px', borderBottomRightRadius: '8px', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-primary)', transition: 'left 0.3s ease' }}>
          {sidebarCollapsed ? '›' : '‹'}
        </div>

        <aside className={`glass-panel sidebar ${sidebarCollapsed ? 'sidebar-closed' : 'sidebar-open'}`} style={{ 
          display: 'flex', 
          flexDirection: 'column', 
          borderRight: sidebarCollapsed ? 'none' : '1px solid var(--border-subtle)', 
          background: 'rgba(15, 15, 20, 0.95)', 
          overflow: 'hidden',
          transition: 'width 0.3s cubic-bezier(0.4, 0, 0.2, 1), transform 0.3s ease'
        }}>
          <nav style={{ padding: '1.5rem', display: 'flex', flexDirection: 'column', gap: '0.8rem', overflowY: 'auto', flex: 1, scrollbarWidth: 'none', msOverflowStyle: 'none' }}>
             {['attention', 'all', 'archived', 'trash', 'suggestions', 'event'].map(f => (
               <button key={f} onClick={() => { setFilter(f); if(window.innerWidth < 768) setSidebarCollapsed(true); }} className={filter === f ? 'nav-btn active' : 'nav-btn'}>{f.toUpperCase()}</button>
             ))}
             <div onClick={() => { setFilter('todo'); if(window.innerWidth < 768) setSidebarCollapsed(true); }} style={{ margin: '1.5rem 0', padding: '1rem', background: filter === 'todo' ? 'rgba(59, 130, 246, 0.3)' : 'rgba(59, 130, 246, 0.1)', borderRadius: '8px', border: filter === 'todo' ? '1px solid var(--accent-blue)' : '1px solid var(--border-focus)', cursor: 'pointer', transition: 'all 0.2s' }}>
                <div style={{ fontSize: '0.7rem', color: 'var(--accent-blue)', fontWeight: 'bold', marginBottom: '0.5rem' }}>TASKS PENDING</div>
                <div style={{ fontSize: '1.5rem', fontWeight: '800', color: 'white' }}>{activeTodosCount}</div>
             </div>
             <div onClick={() => { setFilter('tobuy'); if(window.innerWidth < 768) setSidebarCollapsed(true); }} style={{ margin: '0 0 1.5rem 0', padding: '1rem', background: filter === 'tobuy' ? 'rgba(16, 185, 129, 0.3)' : 'rgba(16, 185, 129, 0.1)', borderRadius: '8px', border: filter === 'tobuy' ? '1px solid #10b981' : '1px solid var(--border-focus)', cursor: 'pointer', transition: 'all 0.2s' }}>
                <div style={{ fontSize: '0.7rem', color: '#10b981', fontWeight: 'bold', marginBottom: '0.5rem' }}>TO BUY LIST</div>
                <div style={{ fontSize: '1.5rem', fontWeight: '800', color: 'white' }}>{activeBuysCount}</div>
             </div>
             <button onClick={() => { setAppLevel(5); if(window.innerWidth < 768) setSidebarCollapsed(true); }} className={appLevel === 5 ? 'nav-btn active' : 'nav-btn'} style={{ background: 'rgba(59, 130, 246, 0.2)', borderColor: 'var(--accent-blue)', marginBottom: '0.8rem' }}>COGNITIVE INSIGHT</button>
             <button onClick={() => { setAppLevel(3); if(window.innerWidth < 768) setSidebarCollapsed(true); }} className="nav-btn" style={{ background: 'rgba(139, 92, 246, 0.2)', borderColor: 'var(--neon-purple)' }}>STRATEGIST MAP</button>
          </nav>
        </aside>

        <main style={{ flex: 1, padding: '2rem', overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: '2rem' }}>
          <div style={{ maxWidth: '800px', width: '100%', margin: '0 auto' }}>
            <InputBar onCommandTrigger={async (cmd, payload) => {
              if (cmd === 'vault-open') {
                if (!payload) setAppLevel(2);
                else openVaultUI(payload);
              }
              else if (cmd === 'recover-open') setShowVaultRecovery(true);
              else if (cmd === 'reset-auth') {
                await db.settings.delete('hydraConfigs');
                await db.settings.delete('hydraTriggers');
                window.location.reload();
              }
              else if (cmd === 'cleardemo') {
                const all = await db.thoughts.toArray();
                const demos = all.filter(t => t.tags && t.tags.includes('demo'));
                for (const t of demos) await db.thoughts.delete(t.id);
                jarvisNotify("Demo payloads purged from local memory.");
              }
              else if (cmd === 'cleardocs') {
                await db.documents.clear();
                jarvisNotify("Internal documentation vault eradicated.");
              }
              else if (cmd === 'reset-db-local') {
                const { nuclearReset } = await import('./shared/infrastructure/db');
                nuclearReset();
              }
              else if (cmd === 'settings') {
                setShowSettings(true);
              }
            }} />
            
            <div style={{ marginTop: '2rem', display: 'flex', flexDirection: 'column', gap: '1.5rem' }}>
              {displayedThoughts.map(t => (
                <ThoughtCard key={t.id} thought={t} onAction={handleCardAction} />
              ))}
            </div>
          </div>
        </main>
      </div>
      {GlobalWidgetComp}
      {showVaultRecovery && (
        <VaultRecovery 
          onClose={() => setShowVaultRecovery(false)} 
          onReassignComplete={(layer) => {
            console.log(`[VAULT] Reassignment complete for layer: ${layer}`);
          }}
        />
      )}
      <SecurePrompt {...promptConfig} />
      {showSettings && <SettingsModal onClose={() => setShowSettings(false)} jarvisNotify={jarvisNotify} />}
      {targetVaultSelection && renderVaultSelectionModal()}
      <PwaAlerts />
    </div>
  );
}
