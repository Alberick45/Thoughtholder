import React, { useState, useEffect, useRef } from 'react';
import { orchestrator } from '../engines/RuntimeOrchestrator';
import { db, addThought, generateUUID } from '../../../shared/infrastructure/db';
import { Send } from 'lucide-react';

import { safeStringify } from '../../../shared/utils/normalization';

export default function JarvisChat({ chatLogs, inVault = false, isTyping, setIsTyping, debugMode, setDebugMode }) {
  const [inputVal, setInputVal] = useState('');
  const [showHistory, setShowHistory] = useState(false);
  const [model, setModel] = useState('llama3');
  const [isDownloading, setIsDownloading] = useState(false);
  const [tempUserMsg, setTempUserMsg] = useState(null); // Optimistic UI
  const bottomRef = useRef(null);

  const toggleDebug = () => {
    const newState = !debugMode;
    setDebugMode(newState);
    localStorage.setItem('jaos_debug', newState);
  };

  // Auto scroll to bottom
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [chatLogs, isTyping, showHistory, tempUserMsg]);

  const handleModelChange = async (e) => {
    const newModel = e.target.value;
    setModel(newModel);

    // Skip electron checks if we are on mobile or using local-wasm
    if (newModel === 'local-wasm') return;

    if (window.electronAPI && window.electronAPI.runModel) {
      setIsDownloading(true);
      try {
        await window.electronAPI.runModel(newModel);
      } catch (err) {
        console.error(err);
      }
      setTimeout(() => setIsDownloading(false), 5000);
    } else if (window.innerWidth > 768) {
      alert('Model switching requires the standalone desktop app.');
    }
  };

  const displayedLogs = showHistory ? chatLogs : chatLogs.slice(-20);

  const handleSend = async () => {
    const text = inputVal.trim();
    console.log("[JARVIS_CHAT] handleSend start. Text:", text);
    if (!text) return;
    
    // Clear input and show optimistic user message
    setInputVal('');
    setTempUserMsg(text);

    // Check leash
    const leashValue = localStorage.getItem('jarvis_leash');
    console.log("[JARVIS_CHAT] Leash value:", leashValue);
    if (leashValue === '0') {
      alert("Jarvis is currently set to Sleeping on the leash. Raise control level to interact.");
      setTempUserMsg(null);
      return;
    }

    // Wipe demo data utility
    if (text.toLowerCase() === '/cleardemo') {
      const allT = await (window.db || db).thoughts.toArray();
      let wiped = 0;
      for (const t of allT) {
        const content = safeStringify(t.content).toLowerCase();
        if (content.includes('information theory') || content.includes('demo') || content.includes('example')) {
          await (window.db || db).thoughts.delete(t.id);
          wiped++;
        }
      }
      alert(`Demo data purge complete. Eradicated ${wiped} ghost records.`);
      setTempUserMsg(null);
      return;
    }

    // Wipe demo docs utility
    if (text.toLowerCase() === '/cleardocs') {
      const allDocs = await (window.db || db).documents.toArray();
      for (const d of allDocs) {
        await (window.db || db).documents.delete(d.id);
      }
      alert(`Documentation vault cleared.`);
      setTempUserMsg(null);
      return;
    }

    const now = Date.now();
    try {
        console.log("[JARVIS_CHAT] Submitting to DB...");
        const queryId = generateUUID();
        await addThought({
          id: queryId,
          thought_id: `Query-${Math.floor(Math.random() * 9000)}`,
          content: `**You:** ${text}`,
          type: 'jarvis_log',
          status: 'archived',
          tags: [],
          created_at: now,
          last_viewed_at: now,
          stale_score: 0,
          linked_thoughts: []
        });
        console.log("[JARVIS_CHAT] DB Submit Success. Calling AI Engine...");
        setIsTyping(true);
        
        // --- NEW JAOS REBUILT KERNEL (PHASE 1) ---
        let response;
        try {
          const { chatKernel } = await import('../kernel/ChatKernel');
          console.log("[JARVIS_CHAT] Calling Kernel for:", text);
          response = await chatKernel.execute(text);
        } catch (kernelErr) {
          console.error("[JARVIS_CHAT] Kernel Crash:", kernelErr);
          response = { reply: "Kernel error: " + kernelErr.message };
        }
        
        const displayReply = response?.reply || "System offline.";
        console.log("[JARVIS_CHAT] FINAL KERNEL RENDER:", displayReply);

        // Clear temp message now that we are moving to the response phase
        setTempUserMsg(null);

        // --- PHASE 6: COGNITIVE ACTION INTERCEPTOR ---
        const actionMatch = displayReply.match(/\[JAOS_ACTION:\s*(\{.*?\})\s*\]/);
        if (actionMatch) {
          try {
            const parsed = JSON.parse(actionMatch[1]);
            console.log("[JARVIS_CHAT] Intercepted Action:", parsed);
            let actionResult = "Action failed or unrecognized.";
            
            // UI feedback for background work
            await addThought({ id: generateUUID(), thought_id: `Jarvis-${Math.floor(Math.random() * 9000)}`, content: `**Jarvis:**\n*Initializing autonomous query: ${parsed.query || parsed.url}...*`, type: 'jarvis_log', status: 'fresh', tags: ['jarvis-verified'], created_at: Date.now(), last_viewed_at: Date.now(), stale_score: 0, linked_thoughts: [] });

            if (parsed.type === 'net_search') {
              const { networkArchitect } = await import('../../vault/services/networkArchitect.js');
              const results = await networkArchitect.search(parsed.query);
              actionResult = results.map(r => `[${r.title}](${r.link})\n${r.snippet}`).join('\n\n');
            } else if (parsed.type === 'scrape') {
              const { networkArchitect } = await import('../../vault/services/networkArchitect.js');
              const scrapedText = await networkArchitect.scrape(parsed.url);
              actionResult = scrapedText.substring(0, 3000);
            }

            const { askJarvisWithContext } = await import('../services/jarvis');
            const followUpPrompt = `[SYSTEM BACKGROUND RESULT FOR YOUR ACTION]:\n${actionResult}\n\nNow, respond naturally to the user based on this newly acquired data.`;
            const secondReply = await askJarvisWithContext(followUpPrompt, window.db || db, inVault);
            await addThought({ id: generateUUID(), thought_id: `Jarvis-${Math.floor(Math.random() * 9000)}`, content: `**Jarvis:**\n${secondReply}`, type: 'jarvis_log', status: 'fresh', tags: ['jarvis-verified'], created_at: Date.now(), last_viewed_at: Date.now(), stale_score: 0, linked_thoughts: [] });
            setIsTyping(false);
            return;
          } catch (e) { console.error("JAOS Action Error", e); }
        }

        if (displayReply) {
          const replyId = generateUUID();
          const words = displayReply.split(' ');
          let currentText = '';
          await addThought({ id: replyId, thought_id: `Jarvis-${Math.floor(Math.random() * 9000)}`, content: `**Jarvis:**\n...`, type: 'jarvis_log', status: 'fresh', tags: ['jarvis-verified'], created_at: Date.now(), last_viewed_at: Date.now(), stale_score: 0, linked_thoughts: [] });
          setIsTyping(false);
          for (let i = 0; i < words.length; i++) {
            currentText += (i === 0 ? '' : ' ') + words[i];
            await (window.db || db).thoughts.update(replyId, { content: `**Jarvis:**\n${currentText}` });
            await new Promise(r => setTimeout(r, 40 + Math.random() * 40));
          }
        }
    } catch (e) {
      console.error("JarvisChat Catch Error:", e);
      setTempUserMsg(null); // Clear temp message on error
      const errorText = e.name === 'AbortError' ? "Request timed out (Ollama might be slow)." : e.message;
      await addThought({ id: generateUUID(), thought_id: `Error-${Math.floor(Math.random() * 9000)}`, content: `**System:** Jarvis Offline. Error: ${errorText}`, type: 'jarvis_log', status: 'fresh', tags: [], created_at: Date.now(), last_viewed_at: Date.now(), stale_score: 0, linked_thoughts: [] });
    }
    setIsTyping(false);
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', flex: 1, height: '100%', overflow: 'hidden' }}>
      {/* Messages Feed */}
      <div style={{ flex: 1, overflowY: 'auto', paddingRight: '0.5rem', display: 'flex', flexDirection: 'column', gap: '0.8rem' }}>

        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem', background: 'rgba(0,0,0,0.3)', padding: '0.5rem', borderRadius: '12px', border: '1px solid var(--border-subtle)' }}>
          <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
            <span style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>Brain:</span>
            <select
              value={model}
              onChange={handleModelChange}
              style={{ background: '#121212', color: 'white', border: '1px solid var(--border-focus)', borderRadius: '8px', padding: '0.3rem', fontSize: '0.8rem', outline: 'none' }}
            >
              <option value="llama3">Llama 3 (Heavy)</option>
              <option value="phi3">Phi-3 (Fast)</option>
              <option value="local-wasm">Local (WASM)</option>
            </select>
            <button
              onClick={toggleDebug}
              style={{ background: debugMode ? 'rgba(239, 68, 68, 0.2)' : 'transparent', color: debugMode ? '#ef4444' : 'var(--text-muted)', border: '1px solid var(--border-subtle)', borderRadius: '8px', padding: '0.3rem 0.6rem', fontSize: '0.7rem', fontWeight: 'bold', cursor: 'pointer' }}
            >
              DEV
            </button>
          </div>

          <div style={{ display: 'flex', gap: '1rem' }}>
            {!showHistory && chatLogs.length > 20 && (
              <button
                onClick={() => setShowHistory(true)}
                style={{ background: 'transparent', border: '1px solid var(--border-subtle)', color: 'var(--text-muted)', padding: '0.4rem 1rem', borderRadius: '12px', fontSize: '0.8rem', cursor: 'pointer' }}
              >
                Older History
              </button>
            )}
            {chatLogs.length > 0 && (
              <button
                onClick={async () => {
                  if (window.confirm("Clear this conversation from your feed? (Data will be sent to Deep Trash)")) {
                    for (const log of chatLogs) {
                      await (window.db || db).thoughts.update(log.id, { status: 'trash' });
                    }
                  }
                }}
                style={{ background: 'transparent', border: '1px solid rgba(239, 68, 68, 0.5)', color: '#ef4444', padding: '0.4rem 1rem', borderRadius: '12px', fontSize: '0.8rem', cursor: 'pointer', transition: 'all 0.2s' }}
              >
                Clear Feed
              </button>
            )}
          </div>
        </div>

        {displayedLogs.length === 0 && !tempUserMsg && (
          <div style={{ textAlign: 'center', padding: '2rem', color: 'var(--text-muted)', fontSize: '0.8rem', opacity: 0.5 }}>
            <div style={{ marginBottom: '0.5rem' }}>🧠 JAOS Cognitive Kernel Ready</div>
            <div>Waiting for user input or environmental trigger...</div>
          </div>
        )}

        {displayedLogs.map(log => {
          const isUser = log.content.startsWith('**You:**');
          const isDaemon = log.content.startsWith('**System:**') || log.content.startsWith('**Jarvis (Autonomous Query):**');
          const cleanText = log.content.replace(/^\*\*(?:You|Jarvis.*|System):\*\*\s*/i, '');

          return (
            <div
              key={log.id}
              style={{ display: 'flex', justifyContent: isUser ? 'flex-end' : (isDaemon ? 'center' : 'flex-start'), cursor: 'context-menu' }}
            >
              <div style={{
                maxWidth: isDaemon ? '95%' : '85%',
                padding: '0.8rem 1rem',
                borderRadius: isDaemon ? '12px' : (isUser ? '16px 16px 2px 16px' : '16px 16px 16px 2px'),
                background: isDaemon ? 'rgba(239, 68, 68, 0.1)' : (isUser ? 'linear-gradient(135deg, var(--accent-blue), var(--neon-purple))' : 'rgba(30, 30, 35, 0.95)'),
                border: isDaemon ? '1px dashed #ef4444' : (isUser ? 'none' : '1px solid var(--border-subtle)'),
                color: isDaemon ? '#fca5a5' : 'white',
                fontSize: '0.9rem',
                lineHeight: '1.5',
                boxShadow: isUser ? '0 4px 16px rgba(139, 92, 246, 0.4)' : 'none'
              }}>
                <span style={{ whiteSpace: 'pre-wrap' }}>{cleanText}</span>
              </div>
            </div>
          );
        })}

        {/* Optimistic UI Placeholder */}
        {tempUserMsg && (
          <div style={{ display: 'flex', justifyContent: 'flex-end', opacity: 0.8 }}>
            <div style={{
              maxWidth: '85%',
              padding: '0.8rem 1rem',
              borderRadius: '16px 16px 2px 16px',
              background: 'linear-gradient(135deg, var(--accent-blue), var(--neon-purple))',
              border: '1px solid #ff4444', // Diagnostic Border
              color: 'white',
              fontSize: '0.9rem',
              lineHeight: '1.5',
              boxShadow: '0 4px 16px rgba(139, 92, 246, 0.4)'
            }}>
              <span style={{ whiteSpace: 'pre-wrap' }}>{tempUserMsg} (Processing...)</span>
            </div>
          </div>
        )}

        {isTyping && (
          <div style={{ display: 'flex', justifyContent: 'flex-start' }}>
            <div style={{ padding: '0.4rem 1rem', borderRadius: '16px 16px 16px 2px', background: 'rgba(30, 30, 35, 0.4)', color: 'var(--text-muted)' }}>
              <div className="typing-dots">
                <span></span>
                <span></span>
                <span></span>
              </div>
            </div>
          </div>
        )}
        <div ref={bottomRef} style={{ height: '4px' }} />
      </div>

      {/* Input Field */}
      <div style={{ 
        marginTop: '1rem', 
        display: 'flex', 
        gap: '0.5rem', 
        background: 'rgba(15, 15, 20, 0.8)', 
        padding: '0.5rem', 
        borderRadius: '28px', 
        border: '1px solid var(--border-focus)',
        backdropFilter: 'blur(10px)',
        boxShadow: 'inset 0 2px 10px rgba(0,0,0,0.5)'
      }}>
        <input
          type="text"
          placeholder="Talk directly to Jarvis..."
          value={inputVal}
          onChange={e => setInputVal(e.target.value)}
          onKeyDown={e => {
             if (e.key === 'Enter') {
                console.log("[JARVIS_CHAT] Enter key detected");
                handleSend();
             }
          }}
          style={{ flex: 1, background: 'transparent', border: 'none', color: 'white', outline: 'none', padding: '0.5rem 1rem', fontSize: '1rem' }}
        />
        <button 
          onClick={() => {
             console.log("[JARVIS_CHAT] Send button clicked");
             handleSend();
          }} 
          style={{ 
            background: 'linear-gradient(135deg, #8B5CF6, #D946EF)', 
            color: 'white', 
            border: 'none', 
            borderRadius: '50%', 
            width: '42px', 
            height: '42px', 
            display: 'flex', 
            alignItems: 'center', 
            justifyContent: 'center', 
            cursor: 'pointer', 
            transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)',
            boxShadow: '0 4px 15px rgba(139, 92, 246, 0.4)',
            flexShrink: 0
          }}
          className="hover-scale"
        >
          <Send size={20} color="white" style={{ pointerEvents: 'none' }} />
        </button>
      </div>
    </div>
  );
}
