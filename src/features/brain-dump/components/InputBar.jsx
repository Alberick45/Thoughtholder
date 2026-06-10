import React, { useState, useRef, useEffect } from 'react';
import { Send, Hash, FileText, CheckCircle2, ChevronUp, Mic, MicOff, Image as ImageIcon, Paperclip, ListTodo, ShoppingCart, Lightbulb, MessageSquare, X } from 'lucide-react';
import { addThought, db, hashCodeword, saveRecoveryCodeHash, verifyRecoveryCode, hasRecoveryCode, generateUUID, getDeviceId } from '../../../shared/infrastructure/db';
import { voiceEngine } from '../../intelligence/voice/VoiceEngineManager';
import { formatEngine } from '../../intelligence/voice/formatEngine';

export default function InputBar({ onCommandTrigger }) {
  const [text, setText] = useState('');
  const [status, setStatus] = useState('idle'); // idle, saved, syncing
  const [activeMode, setActiveMode] = useState('thought'); // thought, task, buy
  const [attachments, setAttachments] = useState([]);
  
  // Voice State
  const [voiceState, setVoiceState] = useState('idle'); // idle, listening, processing, error
  const [voiceMode, setVoiceMode] = useState('unknown'); // online, offline
  const [interimText, setInterimText] = useState('');
  
  const [downloadProgress, setDownloadProgress] = useState(null);
  const [offlineError, setOfflineError] = useState(false);
  const fileInputRef = useRef(null);
  
  const activeModeRef = useRef(activeMode);
  useEffect(() => {
    activeModeRef.current = activeMode;
  }, [activeMode]);

  useEffect(() => {
    voiceEngine.onStateChange = (state, mode) => {
      setVoiceState(state);
      setVoiceMode(mode);
      if (state === 'error' && mode === 'offline') {
        setOfflineError(true);
      }
    };
    
    voiceEngine.onInterimResult = (transcript) => {
      setInterimText(transcript);
    };

    voiceEngine.onFinalResult = (transcript) => {
      setInterimText('');
      setText(prev => formatEngine.process(transcript, prev, activeModeRef.current, true));
    };

    return () => {
      voiceEngine.stop();
    };
  }, []);

  useEffect(() => {
    // Silently pre-warm local voice model if online so it caches the model
    if (navigator.onLine) {
      const prewarm = async () => {
        try {
          const { initLocalVoice } = await import('../../intelligence/services/localVoice.js');
          await initLocalVoice((progressData) => {
            if (progressData.status === 'downloading') {
              setDownloadProgress({
                file: progressData.file,
                progress: Math.round(progressData.progress || 0),
                status: 'downloading'
              });
            } else if (progressData.status === 'ready') {
              setDownloadProgress({ status: 'ready' });
              setTimeout(() => setDownloadProgress(null), 3000);
            }
          });
        } catch (err) {
          console.warn('[LOCAL VOICE] Silent background pre-warm failed:', err);
        }
      };
      // Short delay to allow high-priority page load tasks to run first
      const timer = setTimeout(prewarm, 2000);
      return () => clearTimeout(timer);
    }
  }, []);
  
  // Basic NLP stop-words to filter out for keyword extraction
  const stopWords = new Set(['the', 'a', 'an', 'and', 'or', 'to', 'for', 'of', 'in', 'on', 'with', 'about', 'is', 'it', 'this', 'that', 'i', 'my']);

  const commands = [
    { cmd: '/todo', label: 'Todo', icon: '✅' },
    { cmd: '/tobuy', label: 'To Buy', icon: '🛒' },
    { cmd: '/idea', label: 'Idea', icon: '💡' },
    { cmd: '/vault', label: 'Vault', icon: '🔐' },
    { cmd: '/jarvis', label: 'Jarvis AI', icon: '🧠' },
    { cmd: '/recover', label: 'Recover', icon: '🔑' },
    { cmd: '/settings', label: 'Settings', icon: '⚙️' }
  ];

// processVoiceTranscript removed in favor of formatEngine

  const generateAutoId = (content, intent) => {
    // extract longest word that is not a stop word
    const words = content.replace(/[^\w\s]/g, '').toLowerCase().split(/\s+/);
    let keyword = 'Thought';
    let longestLength = 0;
    
    for (const w of words) {
      if (!stopWords.has(w) && w.length > longestLength) {
        keyword = w;
        longestLength = w.length;
      }
    }
    
    // capitalize
    keyword = keyword.charAt(0).toUpperCase() + keyword.slice(1);
    
    // suffix
    const suffix = Math.floor(100 + Math.random() * 900); // 3 digit
    
    return `${keyword}-${intent.charAt(0).toUpperCase() + intent.slice(1)}-${suffix}`;
  };

  const handleSubmit = async (e) => {
    if (e) e.preventDefault();
    const cleanText = text.trim();
    if (!cleanText && attachments.length === 0) return;
    
    // Parse intent
    let intent = activeMode;
    let cleanContent = text;
    
    const lowerText = cleanText.toLowerCase();

    try {
      // System Commands
      if (lowerText.startsWith('/')) {
        const match = cleanText.match(/^\/([a-z0-9_]+)(?:\s+([\s\S]*))?$/i);
        if (match) {
          const cmd = match[1].toLowerCase();
          const payload = (match[2] || '').trim();

        // Handle some commands locally if needed, else pass to trigger
        if (cmd === 'setcode') {
          const word = payload;
          if (!word) { alert('Usage: /setcode yourSecretWord'); setText(''); return; }
          const alreadySet = await hasRecoveryCode();
          if (alreadySet) {
            const confirm = window.confirm('A recovery codeword is already set. Overwrite it?');
            if (!confirm) { setText(''); return; }
          }
          const hash = await hashCodeword(word);
          await saveRecoveryCodeHash(hash);
          alert(`✓ Recovery codeword locked in. SHA-256 fingerprint stored. Fingerprint: ${hash.slice(0, 16)}...`);
          setText('');
          return;
        }

        if (cmd === 'recover') {
          const word = payload;
          const alreadySet = await hasRecoveryCode();
          if (!alreadySet) {
            if (word) {
              const hash = await hashCodeword(word);
              await saveRecoveryCodeHash(hash);
              alert('✓ Recovery codeword established.');
            }
            if (onCommandTrigger) onCommandTrigger('recover-open');
            setText('');
            return;
          }
          if (!word) { alert('Usage: /recover yourSecretWord'); setText(''); return; }
          const valid = await verifyRecoveryCode(word);
          if (valid) {
            if (onCommandTrigger) onCommandTrigger('recover-open');
          } else {
            alert('INVALID RECOVERY CODE. Access denied.');
          }
          setText('');
          return;
        }

        if (cmd === 'reassign') {
          if (onCommandTrigger) onCommandTrigger('recover-open');
          setText('');
          return;
        }

        if (cmd === 'reset_auth') {
          import('../../intelligence/engines/SystemCommandEngine').then(({ SystemCommandEngine }) => {
            SystemCommandEngine.resetAuth().then((msg) => {
              alert(msg);
              window.location.reload();
            });
          });
          setText('');
          return;
        }

        if (cmd === 'reset_db' || cmd === 'nuclear') {
          const confirm = window.confirm("CRITICAL: This will PERMANENTLY WIPE all thoughts and local data to fix database corruption. Export your data first if possible. Continue?");
          if (confirm) {
            if (onCommandTrigger) onCommandTrigger('reset-db-local');
          }
          setText('');
          return;
        }

        if (cmd === 'clear_memory' || cmd === 'cleardemo') {
          const confirm = window.confirm("JAOS Memory Wipe: This will clear all AI conversation history and personality notes. Proceed?");
          if (confirm) {
            import('../../intelligence/engines/SystemCommandEngine').then(({ SystemCommandEngine }) => {
              SystemCommandEngine.clearMemory().then((msg) => {
                alert(msg);
                window.location.reload();
              });
            });
          }
          setText('');
          return;
        }

        if (cmd === 'cleardocs') {
          const confirm = window.confirm("ERADICATION: This will wipe the entire internal documentation vault. Proceed?");
          if (confirm) {
            import('../../intelligence/engines/SystemCommandEngine').then(({ SystemCommandEngine }) => {
              SystemCommandEngine.clearDocs().then((msg) => {
                alert(msg);
                window.location.reload();
              });
            });
          }
          setText('');
          return;
        }

        if (cmd === 'vault') {
          if (onCommandTrigger) onCommandTrigger('vault-open');
          setText('');
          return;
        }

        // Special case for types
        if (cmd === 'idea') { intent = 'idea'; cleanContent = payload; }
        else if (cmd === 'todo') { intent = 'task'; cleanContent = payload; }
        else if (cmd === 'tobuy') { intent = 'buy'; cleanContent = payload; }
        else if (cmd === 'note') { intent = 'note'; cleanContent = payload; }
        else if (cmd === 'thought') { intent = 'thought'; cleanContent = payload; }
        else if (cmd === 'suggestion') {
          const cleanContentSug = `[SUG] Feature Request (Sent from ${getDeviceId()}): ${payload}`;
          const thought_id = generateAutoId(payload, 'suggestion');
          const now = Date.now();
          const newEntry = {
            id: generateUUID(), thought_id, content: cleanContentSug, type: 'suggestion',
            status: 'vaulted', tags: [], summary: '', created_at: now, last_viewed_at: now, stale_score: 0, linked_thoughts: []
          };
          setStatus('saving');
          await addThought(newEntry);
          setStatus('saved');
          setText('');
          setTimeout(() => setStatus('idle'), 2000);
          return;
        } else {
          // General command trigger
          setText('');
          if (onCommandTrigger) await onCommandTrigger(cmd, payload);
          return;
        }
      }
    }

      // Handle @ tags
      if (lowerText.startsWith('@net ')) {
        const query = cleanText.replace(/^@net\s+/i, '').trim();
        setText('');
        if (onCommandTrigger) await onCommandTrigger('net-search', query);
        return;
      }

      if (lowerText.startsWith('@scrape ')) {
        const url = cleanText.replace(/^@scrape\s+/i, '').trim();
        setText('');
        if (onCommandTrigger) await onCommandTrigger('scrape-url', url);
        return;
      }

      // If not a special command or tag, treat as content with potential intent
      const thought_id = generateAutoId(cleanContent, intent);
      const now = Date.now();
      
      const newEntry = {
        id: generateUUID(),
        thought_id,
        content: cleanContent,
        type: intent,
        status: 'fresh',
        tags: [],
        attachments: attachments,
        summary: '',
        created_at: now,
        last_viewed_at: now,
        stale_score: 0,
        linked_thoughts: []
      };

      setStatus('saving');
      await addThought(newEntry);
      setStatus('saved');
      setText('');
      setAttachments([]);
      setTimeout(() => setStatus('idle'), 2000);
    } catch (err) {
      console.error("[InputBar] Submission Error:", err);
      alert("Submission Error: Check console for details.");
      setStatus('idle');
    }
  };

  const handleKeyDown = async (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSubmit();
    } else if (e.key === 'Enter' && e.shiftKey) {
      // Auto-numbering for /todo or when activeMode is task/buy
      if (text.startsWith('/todo') || text.startsWith('/tobuy') || activeMode === 'task' || activeMode === 'buy') {
        e.preventDefault();
        const lines = text.split('\n');
        
        let nextNumber = 1;
        for (let i = lines.length - 1; i >= 0; i--) {
          const match = lines[i].match(/^(\d+)\.\s/);
          if (match) {
            nextNumber = parseInt(match[1], 10) + 1;
            break;
          }
        }
        
        const insertion = `\n${nextNumber}. `;
        const cursorPosition = e.target.selectionStart;
        
        const newText = text.substring(0, cursorPosition) + insertion + text.substring(e.target.selectionEnd);
        setText(newText);
        
        // Push cursor past the insertion async
        setTimeout(() => {
          e.target.selectionStart = e.target.selectionEnd = cursorPosition + insertion.length;
        }, 0);
      }
    }
  };

  const toggleRecording = async () => {
    if (voiceState === 'listening' || voiceState === 'processing') {
      voiceEngine.stop();
    } else {
      setOfflineError(false);
      setInterimText('');
      await voiceEngine.start();
    }
  };

  const handleFileSelect = (e) => {
    const files = Array.from(e.target.files);
    files.forEach(file => {
      const reader = new FileReader();
      reader.onload = (event) => {
        setAttachments(prev => [...prev, {
          name: file.name,
          type: file.type,
          data: event.target.result,
          size: file.size
        }]);
      };
      reader.readAsDataURL(file);
    });
    if (fileInputRef.current) fileInputRef.current.value = '';
  };

  const removeAttachment = (index) => {
    setAttachments(prev => prev.filter((_, i) => i !== index));
  };

  return (
    <div className="input-bar-container" style={{ position: 'relative', width: '100%', maxWidth: '800px', margin: '0 auto' }}>
      {/* Command Suggestions */}
      {text.startsWith('/') && (
        <div style={{ 
          display: 'flex', 
          gap: '0.5rem', 
          overflowX: 'auto', 
          marginBottom: '0.8rem', 
          padding: '0.4rem', 
          scrollbarWidth: 'none',
          background: 'rgba(20, 20, 25, 0.4)',
          borderRadius: '10px',
          border: '1px solid var(--border-subtle)',
          backdropFilter: 'blur(10px)'
        }}>
          {commands.filter(c => c.cmd.startsWith(text.toLowerCase())).map(c => (
            <button 
              key={c.cmd}
              type="button"
              onClick={() => {
                setText(c.cmd + ' ');
                if (c.cmd === '/todo') {
                  setActiveMode('task');
                  setText('1. ');
                }
                if (c.cmd === '/tobuy') {
                  setActiveMode('buy');
                  setText('1. ');
                }
                if (c.cmd === '/vault') setActiveMode('thought');
              }}
              style={{ 
                background: 'rgba(139, 92, 246, 0.1)', 
                border: '1px solid var(--neon-purple)', 
                color: 'var(--neon-purple)', 
                padding: '0.4rem 0.8rem', 
                borderRadius: '20px', 
                fontSize: '0.8rem', 
                whiteSpace: 'nowrap',
                display: 'flex',
                alignItems: 'center',
                gap: '6px',
                cursor: 'pointer',
                transition: 'all 0.2s',
                fontWeight: '500'
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.background = 'rgba(139, 92, 246, 0.2)';
                e.currentTarget.style.transform = 'scale(1.05)';
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.background = 'rgba(139, 92, 246, 0.1)';
                e.currentTarget.style.transform = 'scale(1)';
              }}
            >
              <span>{c.icon}</span> {c.label}
            </button>
          ))}
        </div>
      )}

      <div style={{ display: 'flex', gap: '0.5rem', marginBottom: '0.8rem', flexWrap: 'wrap', alignItems: 'center' }}>
        <div style={{ display: 'flex', gap: '0.5rem', background: 'rgba(20, 20, 25, 0.8)', padding: '4px', borderRadius: '8px', border: '1px solid var(--border-subtle)' }}>
          <button type="button" onClick={() => setActiveMode('thought')} style={{ display: 'flex', alignItems: 'center', gap: '4px', padding: '4px 10px', borderRadius: '6px', fontSize: '0.8rem', background: activeMode === 'thought' ? 'rgba(139, 92, 246, 0.2)' : 'transparent', color: activeMode === 'thought' ? 'var(--neon-purple)' : 'var(--text-muted)', border: 'none', cursor: 'pointer', transition: 'all 0.2s' }}>
            💭 Thought
          </button>
          <button type="button" onClick={() => { setActiveMode('task'); if(!text) setText('1. '); }} style={{ display: 'flex', alignItems: 'center', gap: '4px', padding: '4px 10px', borderRadius: '6px', fontSize: '0.8rem', background: activeMode === 'task' ? 'rgba(59, 130, 246, 0.2)' : 'transparent', color: activeMode === 'task' ? 'var(--accent-blue)' : 'var(--text-muted)', border: 'none', cursor: 'pointer', transition: 'all 0.2s' }}>
            ✅ Todo
          </button>
          <button type="button" onClick={() => { setActiveMode('buy'); if(!text) setText('1. '); }} style={{ display: 'flex', alignItems: 'center', gap: '4px', padding: '4px 10px', borderRadius: '6px', fontSize: '0.8rem', background: activeMode === 'buy' ? 'rgba(16, 185, 129, 0.2)' : 'transparent', color: activeMode === 'buy' ? '#10b981' : 'var(--text-muted)', border: 'none', cursor: 'pointer', transition: 'all 0.2s' }}>
            🛒 To Buy
          </button>
        </div>

        <div style={{ display: 'flex', gap: '0.5rem', marginLeft: 'auto' }}>
          <input type="file" multiple ref={fileInputRef} onChange={handleFileSelect} style={{ display: 'none' }} />
          <button type="button" onClick={() => fileInputRef.current?.click()} style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', width: '32px', height: '32px', borderRadius: '8px', background: 'rgba(255, 255, 255, 0.05)', color: 'var(--text-secondary)', border: '1px solid var(--border-subtle)', cursor: 'pointer', transition: 'all 0.2s' }}>
            📎
          </button>
          <button type="button" onClick={toggleRecording} disabled={voiceState === 'processing'} style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', width: '32px', height: '32px', borderRadius: '8px', background: voiceState === 'listening' ? 'rgba(239, 68, 68, 0.2)' : (voiceState === 'processing' ? 'rgba(234, 179, 8, 0.2)' : 'rgba(255, 255, 255, 0.05)'), color: voiceState === 'listening' ? '#ef4444' : (voiceState === 'processing' ? '#eab308' : 'var(--text-secondary)'), border: `1px solid ${voiceState === 'listening' ? '#ef4444' : (voiceState === 'processing' ? '#eab308' : 'var(--border-subtle)')}`, cursor: voiceState === 'processing' ? 'wait' : 'pointer', transition: 'all 0.2s' }} className={(voiceState === 'listening' || voiceState === 'processing') ? 'animate-pulse' : ''}>
            {voiceState === 'processing' ? '⏳' : (voiceState === 'listening' ? '🛑' : '🎤')}
          </button>
        </div>
      </div>

      {attachments.length > 0 && (
        <div style={{ display: 'flex', gap: '0.5rem', marginBottom: '0.8rem', flexWrap: 'wrap' }}>
          {attachments.map((att, idx) => (
            <div key={idx} style={{ position: 'relative', display: 'flex', alignItems: 'center', gap: '6px', background: 'rgba(20, 20, 25, 0.8)', padding: '4px 8px', borderRadius: '6px', border: '1px solid var(--border-subtle)', fontSize: '0.8rem' }}>
              {att.type.startsWith('image/') ? '🖼️' : '📄'}
              <span style={{ maxWidth: '120px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', color: 'var(--text-secondary)' }}>{att.name}</span>
              <button type="button" onClick={() => removeAttachment(idx)} style={{ background: 'transparent', border: 'none', color: 'var(--text-muted)', cursor: 'pointer', display: 'flex', alignItems: 'center', padding: '2px' }}>❌</button>
            </div>
          ))}
        </div>
      )}

      {downloadProgress && (
        <div style={{
          background: 'rgba(30, 30, 40, 0.75)',
          backdropFilter: 'blur(12px)',
          border: '1px solid var(--border-subtle)',
          borderRadius: '12px',
          padding: '0.8rem 1.2rem',
          marginBottom: '0.8rem',
          display: 'flex',
          flexDirection: 'column',
          gap: '0.4rem',
          fontSize: '0.85rem',
          color: 'var(--text-primary)',
          boxShadow: '0 4px 20px rgba(0,0,0,0.3)',
          transition: 'all 0.3s ease-in-out'
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', width: '100%' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
              {downloadProgress.status === 'downloading' ? '🤖' : '✓'}
              <span style={{ fontWeight: '500' }}>
                {downloadProgress.status === 'downloading' 
                  ? 'Downloading Offline Voice Engine...' 
                  : 'Offline Voice Engine Ready!'}
              </span>
            </div>
            {downloadProgress.status === 'downloading' && (
              <span style={{ marginLeft: 'auto', fontWeight: 'bold', color: 'var(--neon-purple)' }}>
                {downloadProgress.progress}%
              </span>
            )}
          </div>
          
          {downloadProgress.status === 'downloading' && (
            <>
              <div style={{
                width: '100%',
                height: '6px',
                background: 'rgba(255, 255, 255, 0.1)',
                borderRadius: '3px',
                overflow: 'hidden',
                position: 'relative'
              }}>
                <div style={{
                  width: `${downloadProgress.progress}%`,
                  height: '100%',
                  background: 'linear-gradient(90deg, #8b5cf6, #3b82f6)',
                  borderRadius: '3px',
                  transition: 'width 0.2s ease-out'
                }} />
              </div>
              <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)', textOverflow: 'ellipsis', overflow: 'hidden', whiteSpace: 'nowrap' }}>
                Configuring: {downloadProgress.file ? downloadProgress.file.split('/').pop() : 'model files'}
              </span>
            </>
          )}
        </div>
      )}

      {offlineError && (
        <div style={{
          background: 'rgba(239, 68, 68, 0.1)',
          backdropFilter: 'blur(12px)',
          border: '1px solid rgba(239, 68, 68, 0.3)',
          borderRadius: '12px',
          padding: '0.8rem 1.2rem',
          marginBottom: '0.8rem',
          display: 'flex',
          flexDirection: 'column',
          gap: '0.4rem',
          fontSize: '0.85rem',
          color: 'var(--text-primary)',
          boxShadow: '0 4px 20px rgba(0,0,0,0.3)',
          position: 'relative'
        }}>
          <button 
            type="button" 
            onClick={() => setOfflineError(false)} 
            style={{
              position: 'absolute',
              top: '8px',
              right: '8px',
              background: 'transparent',
              border: 'none',
              color: 'var(--text-muted)',
              cursor: 'pointer',
              fontSize: '0.75rem'
            }}
          >
            ❌
          </button>
          <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontWeight: 'bold', color: '#ef4444' }}>
            ⚠️ Offline Voice Not Setup
          </div>
          <p style={{ margin: 0, fontSize: '0.8rem', color: 'var(--text-secondary)', lineHeight: '1.4' }}>
            Offline speech recognition requires a one-time download (approx. 75MB) to run locally on your machine. 
            Please connect to the internet and click the microphone button (or let the app sit open online) to automatically download and initialize the offline engine.
          </p>
        </div>
      )}

      <form onSubmit={handleSubmit} style={{ position: 'relative', margin: 0, padding: 0 }}>
        {voiceState === 'listening' && (
          <div style={{
            fontSize: '0.85rem',
            color: voiceMode === 'online' ? '#60a5fa' : '#f87171',
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
            marginBottom: '0.6rem',
            fontWeight: '650',
            padding: '6px 12px',
            borderRadius: '8px',
            border: `1px solid ${voiceMode === 'online' ? 'rgba(96, 165, 250, 0.25)' : 'rgba(239, 68, 68, 0.25)'}`,
            background: voiceMode === 'online' ? 'rgba(96, 165, 250, 0.1)' : 'rgba(239, 68, 68, 0.1)',
            width: 'fit-content'
          }}>
            <span className="animate-pulse" style={{ display: 'inline-block', width: '8px', height: '8px', borderRadius: '50%', background: voiceMode === 'online' ? '#60a5fa' : '#ef4444' }} />
            {voiceMode === 'online' ? 'Online Mode: Live Transcription Active...' : 'Offline Mode: Chunked WASM Transcribing...'}
          </div>
        )}
        
        {voiceState === 'processing' && (
          <div style={{
            fontSize: '0.85rem',
            color: '#eab308',
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
            marginBottom: '0.6rem',
            fontWeight: '650',
            padding: '6px 12px',
            borderRadius: '8px',
            border: '1px solid rgba(234, 179, 8, 0.25)',
            background: 'rgba(234, 179, 8, 0.1)',
            width: 'fit-content'
          }}>
            <span className="animate-pulse" style={{ display: 'inline-block', width: '8px', height: '8px', borderRadius: '50%', background: '#eab308' }} />
            Finalizing speech processing...
          </div>
        )}
        <div style={{ position: 'relative' }}>
          <textarea 
            value={text}
            onChange={e => setText(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder={activeMode === 'task' ? "Add a todo task... (Shift+Enter for auto-numbering)" : activeMode === 'buy' ? "Add items to buy... (Shift+Enter for auto-numbering)" : "Capture a thought, idea, or sequence (/vault, /trash...)"}
            rows={Math.min(5, Math.max(1, text.split('\n').length))}
            style={{
              fontSize: '1.2rem',
              padding: '1.2rem 1.5rem',
              paddingRight: '3.5rem',
              borderRadius: '16px',
              boxShadow: '0 8px 32px rgba(0,0,0,0.4)',
              border: '1px solid var(--border-focus)',
              background: 'var(--bg-secondary)',
              color: 'var(--text-primary)',
              width: '100%',
              resize: 'none',
              fontFamily: 'inherit',
              lineHeight: '1.5',
              outline: 'none'
            }}
          />
          {interimText && (
            <div style={{
              position: 'absolute',
              bottom: '-24px',
              left: '1rem',
              fontSize: '0.9rem',
              color: 'var(--text-muted)',
              fontStyle: 'italic',
              pointerEvents: 'none',
              maxWidth: '80%',
              whiteSpace: 'nowrap',
              overflow: 'hidden',
              textOverflow: 'ellipsis'
            }}>
              {interimText}...
            </div>
          )}
        </div>
        
        <div style={{ position: 'absolute', right: '1rem', bottom: '1.5rem', display: 'flex', alignItems: 'center' }}>
          {status === 'saving' && <Send size={24} color="var(--text-muted)" className="animate-pulse" />}
          {(status === 'saved' || status === 'idle') && <ChevronUp size={24} color="var(--text-muted)" onClick={handleSubmit} style={{ cursor: 'pointer' }} />}
        </div>
      </form>
      
      {/* Micro-feedback removed for ambient experience */}
    </div>
  );
}
