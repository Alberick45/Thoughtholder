import React from 'react';
import JarvisChat from '../../features/intelligence/components/JarvisChat';
import CalendarView from '../../features/visuals/components/CalendarView';
import VisionDrop from '../../features/intelligence/components/VisionDrop';
import { generateUUID } from '../../shared/infrastructure/db';

export default function GlobalWidget({ 
  showWidget, setShowWidget, 
  widgetTab, setWidgetTab, 
  appLevel, thoughts, 
  unreadJarvis, setUnreadJarvis, 
  jarvisPreview, setJarvisPreview,
  jarvisIsTyping, setJarvisIsTyping,
  debugMode, setDebugMode
}) {
  
  return (
    <div className="global-widget-container" style={{ position: 'fixed', bottom: '2rem', right: '2rem', zIndex: 5000, display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: '1rem' }}>
      {showWidget && (
        <div className="glass-panel slide-up global-widget-panel" style={{ background: 'rgba(15, 15, 20, 0.95)', display: 'flex', flexDirection: 'column', boxShadow: '0 12px 40px rgba(0,0,0,0.8)', border: '1px solid var(--border-focus)', borderRadius: '12px', overflow: 'hidden' }}>
          
          {/* Widget Tabs Header */}
          <div style={{ display: 'flex', background: 'rgba(0,0,0,0.5)', borderBottom: '1px solid var(--border-subtle)', padding: '0.5rem' }}>
             <button onClick={() => setWidgetTab('jarvis')} style={{ flex: 1, padding: '0.8rem', background: widgetTab === 'jarvis' ? 'rgba(139, 92, 246, 0.2)' : 'transparent', color: widgetTab === 'jarvis' ? 'var(--neon-purple)' : 'var(--text-muted)', border: 'none', borderBottom: widgetTab === 'jarvis' ? '2px solid var(--neon-purple)' : '2px solid transparent', fontWeight: 'bold', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px', cursor: 'pointer' }}>
               🧠 Jarvis Chat
             </button>
             <button onClick={() => setWidgetTab('calendar')} style={{ flex: 1, padding: '0.8rem', background: widgetTab === 'calendar' ? 'rgba(59, 130, 246, 0.2)' : 'transparent', color: widgetTab === 'calendar' ? 'var(--accent-blue)' : 'var(--text-muted)', border: 'none', borderBottom: widgetTab === 'calendar' ? '2px solid var(--accent-blue)' : '2px solid transparent', fontWeight: 'bold', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px', cursor: 'pointer' }}>
               📅 Calendar
             </button>
             <button onClick={() => setWidgetTab('vision')} style={{ flex: 1, padding: '0.8rem', background: widgetTab === 'vision' ? 'rgba(16, 185, 129, 0.2)' : 'transparent', color: widgetTab === 'vision' ? '#10b981' : 'var(--text-muted)', border: 'none', borderBottom: widgetTab === 'vision' ? '2px solid #10b981' : '2px solid transparent', fontWeight: 'bold', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px', cursor: 'pointer' }}>
               👁️ OCR Vision
             </button>
          </div>
          
          {/* Widget Body */}
          <div style={{ flex: 1, padding: '1rem', overflowY: widgetTab === 'jarvis' ? 'hidden' : 'auto', display: 'flex', flexDirection: 'column' }}>
             {widgetTab === 'jarvis' && (
               <JarvisChat 
                 inVault={appLevel === 4} 
                 chatLogs={thoughts.filter(t => t.type === 'jarvis_log' && t.status !== 'trash').sort((a,b) => a.created_at - b.created_at)} 
                 isTyping={jarvisIsTyping}
                 setIsTyping={setJarvisIsTyping}
                 debugMode={debugMode}
                 setDebugMode={setDebugMode}
               />
             )}
             {widgetTab === 'calendar' && <CalendarView thoughts={thoughts} />}
             {widgetTab === 'vision' && (
               <VisionDrop onExtracted={(text) => {
                 import('../../features/intelligence/services/jarvis').then(({ processOCR }) => {
                    processOCR(text).then(correctedText => {
                      import('../../shared/infrastructure/db').then(({ addThought }) => {
                          const now = Date.now();
                          addThought({
                            id: generateUUID(),
                            thought_id: `OCR-INTEL-${Math.floor(Math.random()*9000+1000)}`,
                            content: "[JARVIS CLEANED SECURE PAYLOAD]\n\n" + correctedText,
                            type: 'thought', status: 'fresh', tags: ['jarvis-verified'], summary: '',
                            created_at: now, last_viewed_at: now, stale_score: 0, linked_thoughts: []
                          });
                      });
                    }).catch(err => {
                       import('../../shared/infrastructure/db').then(({ addThought }) => {
                          const now = Date.now();
                          addThought({
                            id: generateUUID(),
                            thought_id: `OCR-INTEL-${Math.floor(Math.random()*9000+1000)}`,
                            content: "[RAW OCR PAYLOAD] (Jarvis Offline)\n\n" + text,
                            type: 'thought', status: 'fresh', tags: [], summary: '',
                            created_at: now, last_viewed_at: now, stale_score: 0, linked_thoughts: []
                          });
                       });
                    });
                 });
               }} />
             )}
          </div>
        </div>
      )}
      
      <div style={{ position: 'relative' }}>
        {unreadJarvis > 0 && !showWidget && (
          <>
            <div style={{ position: 'absolute', top: '-6px', right: '-6px', background: '#ef4444', color: 'white', borderRadius: '50%', width: '20px', height: '20px', fontSize: '0.7rem', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 'bold', zIndex: 10 }}>
              {unreadJarvis}
            </div>
            <div style={{ position: 'absolute', right: '70px', top: '10px', background: 'rgba(239, 68, 68, 0.9)', color: 'white', padding: '0.5rem 1rem', borderRadius: '8px', fontSize: '0.8rem', whiteSpace: 'nowrap', pointerEvents: 'none', boxShadow: '0 4px 12px rgba(239, 68, 68, 0.3)', border: '1px solid #ff7b7b' }}>
              <strong style={{ display: 'block', marginBottom: '2px' }}>Jarvis says:</strong>
              {jarvisPreview}
            </div>
          </>
        )}
        <button 
          onClick={() => { 
             setShowWidget(!showWidget);
             if (!showWidget) {
                setUnreadJarvis(0);
                setJarvisPreview('');
             }
          }}
          title="Toggle Tactical Modules Hub"
          style={{ width: '60px', height: '60px', borderRadius: '50%', background: showWidget ? 'var(--neon-purple)' : 'var(--bg-secondary)', border: '2px solid var(--border-focus)', color: 'white', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', transition: 'all 0.3s', boxShadow: '0 6px 16px rgba(0,0,0,0.6)', fontSize: '1.5rem' }}
        >
          {showWidget ? '✕' : '👁️'}
        </button>
      </div>
    </div>
  );
}
