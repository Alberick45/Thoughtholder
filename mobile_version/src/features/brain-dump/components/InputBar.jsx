import React, { useState } from 'react';
import { Send, Hash, FileText, CheckCircle2, ChevronUp } from 'lucide-react';
import { addThought, db, generateUUID } from '../../../shared/infrastructure/db';
// using native crypto.randomUUID instead of uuid package

export default function InputBar({ onCommandTrigger }) {
  const [text, setText] = useState('');
  const [status, setStatus] = useState('idle'); // idle, saved, syncing

  // Basic NLP stop-words to filter out for keyword extraction
  const stopWords = new Set(['the', 'a', 'an', 'and', 'or', 'to', 'for', 'of', 'in', 'on', 'with', 'about', 'is', 'it', 'this', 'that', 'i', 'my']);

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
    if (!text.trim()) return;

    // Parse intent
    let intent = 'thought';
    let cleanContent = text;

    const lowerText = text.trim().toLowerCase();

    // System Commands
    if (lowerText.startsWith('/vault')) {
      setText('');
      if (onCommandTrigger) onCommandTrigger('vault');
      return;
    }
    if (lowerText.startsWith('/push')) {
      const targetIp = lowerText.replace('/push', '').trim() || null;
      setText('');
      if (onCommandTrigger) onCommandTrigger('push', targetIp);
      return;
    }
    if (lowerText.startsWith('/trash')) {
      setText('');
      if (onCommandTrigger) onCommandTrigger('trash');
      return;
    }
    if (lowerText.startsWith('/export')) {
      setText('');
      if (onCommandTrigger) onCommandTrigger('export');
      return;
    }
    if (lowerText.startsWith('/import')) {
      setText('');
      if (onCommandTrigger) onCommandTrigger('import');
      return;
    }
    if (lowerText.startsWith('/sync')) {
      setText('');
      if (onCommandTrigger) onCommandTrigger('sync');
      return;
    }
    if (lowerText.startsWith('/suggestions')) {
      setText('');
      if (onCommandTrigger) onCommandTrigger('suggestions');
      return;
    }

    if (lowerText.startsWith('/reset_auth')) {
      await db.settings.delete('vaultConfig');
      alert('Security override complete. Vault Configuration reset.');
      setText('');
      return;
    }

    if (lowerText.startsWith('/jarvis-history')) {
      setText('');
      if (onCommandTrigger) onCommandTrigger('jarvis-history');
      return;
    }

    if (lowerText.startsWith('/jarvis-profile')) {
      setText('');
      if (onCommandTrigger) onCommandTrigger('jarvis-profile');
      return;
    }

    if (lowerText.startsWith('/event')) {
      setText('');
      if (onCommandTrigger) onCommandTrigger('event');
      return;
    }

    if (lowerText.startsWith('/jarvis')) {
      const jarvisQuery = text.replace(/^\/jarvis/i, '').trim();
      setText('');
      if (onCommandTrigger) onCommandTrigger('jarvis', jarvisQuery);
      return;
    }

    if (lowerText.startsWith('/tobuy')) {
      const remaining = text.replace(/^\/tobuy/i, '').trim();
      if (!remaining) {
        setText('');
        if (onCommandTrigger) onCommandTrigger('tobuy');
        return;
      } else {
        intent = 'buy';
        cleanContent = remaining;
      }
    }

    if (lowerText.startsWith('/buy')) {
      intent = 'buy';
      cleanContent = text.replace(/^\/buy/i, '').trim();
    } else if (lowerText.startsWith('/idea')) { intent = 'idea'; cleanContent = text.replace(/^\/idea/i, '').trim(); }
    else if (lowerText.startsWith('/todo')) { intent = 'task'; cleanContent = text.replace(/^\/todo/i, '').trim(); }
    else if (lowerText.startsWith('/note')) { intent = 'note'; cleanContent = text.replace(/^\/note/i, '').trim(); }
    else if (lowerText.startsWith('/suggestion')) {
      import('../../../shared/infrastructure/db').then(({ getDeviceId }) => {
        const contentStr = text.replace(/^\/suggestion/i, '').trim();
        const cleanContent = `[SUG] Feature Request (Sent from ${getDeviceId()}): ${contentStr}`;

        const thought_id = generateAutoId(contentStr, 'suggestion');
        const now = Date.now();
        const newEntry = {
          id: generateUUID(), thought_id, content: cleanContent, type: 'suggestion',
          status: 'vaulted', tags: [], summary: '', created_at: now, last_viewed_at: now, stale_score: 0, linked_thoughts: []
        };
        setStatus('saving');
        import('../../../shared/infrastructure/db').then(({ addThought }) => {
          addThought(newEntry).then(() => { setStatus('saved'); setText(''); setTimeout(() => setStatus('idle'), 2000); });
        });
      });
      return;
    }
    else if (lowerText.startsWith('/thought')) { cleanContent = text.replace(/^\/thought/i, '').trim(); }

    const thought_id = generateAutoId(cleanContent, intent);
    const now = Date.now();

    const newEntry = {
      id: generateUUID(),
      thought_id,
      content: cleanContent,
      type: intent,
      // Suggestions go directly into the vault (Dead Drop mechanism)
      status: intent === 'suggestion' ? 'vaulted' : 'fresh',
      tags: [],
      summary: '',
      created_at: now,
      last_viewed_at: now,
      stale_score: 0,
      linked_thoughts: []
    };

    setStatus('saving');

    try {
      await addThought(newEntry);
      setStatus('saved');
      setText('');

      setTimeout(() => setStatus('idle'), 2000);
    } catch (err) {
      console.error("Failed to save", err);
      setStatus('idle');
    }
  };

  const handleAutoNumbering = (e) => {
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
  };

  const handleKeyDown = async (e) => {
    // Robust mobile check: User Agent + Screen Width
    const isMobile = /iPhone|iPad|iPod|Android|Mobi/i.test(navigator.userAgent) || window.innerWidth < 768;
    
    if (e.key === 'Enter' && !e.shiftKey) {
      if (!isMobile) {
        e.preventDefault();
        handleSubmit();
      } else {
        // Mobile: Auto-numbering on regular Enter
        if (text.startsWith('/todo') || text.startsWith('/buy') || text.startsWith('/tobuy')) {
           handleAutoNumbering(e);
        }
      }
    } else if (e.key === 'Enter' && e.shiftKey) {
      // Auto-numbering for /todo
      if (text.startsWith('/todo') || text.startsWith('/buy') || text.startsWith('/tobuy')) {
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

  const commands = [
    { cmd: '/todo', label: 'Todo', icon: '✅' },
    { cmd: '/buy', label: 'Buy', icon: '🛒' },
    { cmd: '/idea', label: 'Idea', icon: '💡' },
    { cmd: '/event', label: 'Event', icon: '📅' },
    { cmd: '/vault', label: 'Vault', icon: '🔐' },
    { cmd: '/jarvis', label: 'Jarvis', icon: '🧠' }
  ];

  return (
    <div className="input-bar-container" style={{ position: 'relative', width: '100%', maxWidth: '800px', margin: '0 auto 1.5rem auto' }}>
      
      {/* Command Suggestions */}
      {text.startsWith('/') && (
        <div style={{ display: 'flex', gap: '0.5rem', overflowX: 'auto', marginBottom: '0.8rem', padding: '0.2rem', scrollbarWidth: 'none' }}>
           {commands.filter(c => c.cmd.startsWith(text.toLowerCase())).map(c => (
             <button 
               key={c.cmd}
               type="button"
               onClick={() => setText(c.cmd + ' ')}
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
                 gap: '4px',
                 cursor: 'pointer'
               }}
             >
               <span>{c.icon}</span> {c.label}
             </button>
           ))}
        </div>
      )}

      <form onSubmit={handleSubmit} style={{ position: 'relative', margin: 0, padding: 0 }}>
        <textarea
          value={text}
          onChange={e => setText(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="Capture a thought, idea, or sequence (/vault, /trash...)"
          rows={Math.min(5, Math.max(1, text.split('\n').length))}
          style={{
            fontSize: '1.2rem',
            padding: '1.2rem 1.5rem',
            paddingRight: '3.5rem',
            borderRadius: '16px',
            background: 'var(--bg-secondary)',
            boxShadow: '0 8px 32px rgba(0,0,0,0.4)',
            border: '1px solid var(--border-focus)',
            width: '100%',
            resize: 'none',
            fontFamily: 'inherit',
            lineHeight: '1.5',
            color: 'var(--text-primary, white)',
            outline: 'none'
          }}
        />

        <div style={{ position: 'absolute', right: '1rem', bottom: '1.5rem', display: 'flex', alignItems: 'center' }}>
          {status === 'saving' && <Send size={24} color="var(--text-muted)" className="animate-pulse" />}
          {status === 'saved' && <CheckCircle2 size={24} color="var(--accent-blue)" className="animate-slide-up" />}
          {status === 'idle' && <ChevronUp size={24} color="var(--text-muted)" onClick={handleSubmit} style={{ cursor: 'pointer' }} />}
        </div>
      </form>

      {/* WhatsApp style micro-feedback */}
      {status === 'saved' && (
        <div className="animate-slide-up" style={{
          position: 'absolute', top: '-30px', right: '10px',
          background: 'rgba(59, 130, 246, 0.2)', color: 'var(--accent-blue)',
          padding: '4px 10px', borderRadius: '12px', fontSize: '0.8rem', fontWeight: '500',
          backdropFilter: 'blur(8px)'
        }}>
          ✓ Saved Locally
        </div>
      )}
    </div>
  );
}
