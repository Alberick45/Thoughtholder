import React, { useState, useEffect } from 'react';
import { formatDistanceToNow } from 'date-fns';
import { Tag, CheckCircle, Clock, Pin, Edit3, Link2, Archive } from 'lucide-react';
import { updateThought, deleteThought } from '../../../shared/infrastructure/db';

export default function ThoughtCard({ thought, allThoughts = [], onAction }) {
  const { id, thought_id, content = '', type, status, stale_score, created_at, linked_thoughts = [], pinned = false, attachments = [] } = thought;
  const [isEditing, setIsEditing] = useState(false);
  const [editContent, setEditContent] = useState(content);
  const [editTitle, setEditTitle] = useState(thought_id);
  const [isExpanded, setIsExpanded] = useState(false);
  const [expandedImage, setExpandedImage] = useState(null);

  const isActionable = (content || '').includes('[JAOS_ACTION:');
  const isVerified = (thought.tags || []).includes('jarvis-verified');

  const isEphemeral = ((thought.tags || []).includes('net-result') || (thought.tags || []).includes('siphoned')) && !(thought.tags || []).includes('kept');

  const handleKeep = async (e) => {
    e.stopPropagation();
    const currentTags = thought.tags || [];
    await updateThought(id, { tags: [...currentTags, 'kept'] });
  };

  const getTypeColor = (t) => {
    if (thought.tags?.includes('siphoned')) return '#eab308'; // Gold for mail
    if (thought.tags?.includes('net-result')) return '#64748b'; // Slate Grey for search results
    
    switch(t) {
      case 'idea': return '#eab308';
      case 'task': return '#ef4444';
      case 'buy': return '#10b981'; // Emerald for shopping/procurement
      case 'note': return '#8b5cf6';
      default: return '#3b82f6';
    }
  };

  const handleMarkDone = async (e) => {
    e.stopPropagation();
    if (status === 'archived') {
      await updateThought(id, { status: 'trash' });
    } else {
      await updateThought(id, { status: 'archived' });
    }
  };

  const handlePin = async (e) => {
    e.stopPropagation();
    await updateThought(id, { pinned: !pinned });
  };

  const handleSaveEdit = async (e) => {
    e.stopPropagation();
    await updateThought(id, { content: editContent, thought_id: editTitle });
    setIsEditing(false);
  };

  const [showStealthMenu, setShowStealthMenu] = useState(false);

  const handleOpen = async () => {
    if (showStealthMenu) {
      setShowStealthMenu(false);
      return;
    }
    if (status !== 'archived' && !isEditing) {
      await updateThought(id, { status: 'active', stale_score: 0, last_viewed_at: Date.now() });
    }
  };

  const handleContextMenu = (e) => {
    e.preventDefault();
    setShowStealthMenu(true);
  };

  const handleStealthDelete = async (e) => {
    e.stopPropagation();
    e.preventDefault();
    if (status === 'trash' || status === 'vaulted_trash') {
      await deleteThought(id); // Permanent eradicate
    } else {
      await updateThought(id, { status: status === 'vaulted' ? 'vaulted_trash' : 'trash' });
    }
    setShowStealthMenu(false);
  };
  
  const handleRestore = async (e) => {
    e.stopPropagation();
    e.preventDefault();
    await updateThought(id, { status: status === 'vaulted_trash' ? 'vaulted' : 'fresh' });
    setShowStealthMenu(false);
  };

  const handleMoveToVault = async (e) => {
    e.stopPropagation();
    e.preventDefault();
    await updateThought(id, { status: 'vaulted' });
    if (onAction) onAction('moved_to_vault', thought);
    setShowStealthMenu(false);
  };

  return (
    <div 
      className="glass-panel" 
      onClick={handleOpen}
      onContextMenu={handleContextMenu}
      style={{ 
        padding: '1.2rem', 
        marginBottom: '1rem',
        cursor: 'pointer',
        borderLeft: `4px solid ${getTypeColor(type)}`,
        background: pinned ? 'rgba(59, 130, 246, 0.1)' : undefined
      }}
    >
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '0.8rem' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', flexWrap: 'wrap' }}>
          {pinned && <Pin size={14} color="var(--accent-blue)" />}
          <span style={{ fontWeight: 'bold', letterSpacing: '0.5px' }}>{thought_id}</span>
          <span style={{ 
            fontSize: '0.75rem', 
            background: 'var(--bg-tertiary)', 
            padding: '2px 8px', 
            borderRadius: '12px',
            textTransform: 'uppercase'
          }}>
            {type}
          </span>
          {status === 'fresh' && <span style={{ fontSize: '0.75rem', color: '#10b981' }}>⚡ Fresh</span>}
          {status === 'ignored' && <span style={{ fontSize: '0.75rem', color: '#f59e0b' }}>👀 Ignored ({stale_score}d)</span>}
          {status === 'archived' && <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>📦 Done</span>}
        </div>
        <span style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>
          {formatDistanceToNow(created_at, { addSuffix: true })}
        </span>
      </div>

      {isEditing ? (
        <div onClick={e => e.stopPropagation()} style={{ marginBottom: '1rem' }}>
          <input 
            value={editTitle} 
            onChange={e => setEditTitle(e.target.value)}
            style={{ width: '100%', marginBottom: '0.5rem', background: 'var(--bg-primary)', color: 'white', borderRadius: '8px', padding: '0.5rem', border: '1px solid var(--border-focus)', fontWeight: 'bold' }}
          />
          <textarea 
            value={editContent} 
            onChange={e => setEditContent(e.target.value)}
            style={{ width: '100%', minHeight: '80px', background: 'var(--bg-primary)', color: 'white', borderRadius: '8px', padding: '0.5rem', border: '1px solid var(--border-focus)' }}
          />
          <div style={{ marginTop: '0.5rem', display: 'flex', gap: '0.5rem' }}>
            <button onClick={handleSaveEdit} style={{ background: 'var(--accent-blue)', color: 'white', padding: '0.3rem 0.8rem', fontSize: '0.8rem' }}>Save</button>
            <button onClick={() => { setIsEditing(false); setEditContent(content); setEditTitle(thought_id); }} style={{ padding: '0.3rem 0.8rem', fontSize: '0.8rem' }}>Cancel</button>
          </div>
        </div>
      ) : (
        <div onClick={e => e.stopPropagation()} style={{ fontSize: '1rem', lineHeight: '1.5', margin: '0 0 1rem 0', whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>
          {type === 'task' || type === 'buy' || content.includes('1. ') ? content.split('\n').map((line, idx) => {
             const isChecked = line.trim().startsWith('✓ ');
             const cleanLine = line.trim().replace(/^✓ /, '');
             const isListItem = /^\s*\d+\.\s/.test(line);
             
             if (isListItem || isChecked) {
                return (
                  <div key={idx} style={{ display: 'flex', alignItems: 'center', gap: '8px', marginTop: '4px' }}>
                    <input 
                      type="checkbox" 
                      checked={isChecked}
                      onChange={async (e) => {
                         e.stopPropagation();
                         const lines = content.split('\n');
                         if (!isChecked) {
                            lines[idx] = '✓ ' + cleanLine;
                         } else {
                            lines[idx] = cleanLine;
                         }
                         await updateThought(id, { content: lines.join('\n') });
                      }}
                      style={{ cursor: 'pointer', accentColor: 'var(--neon-purple)', width: '16px', height: '16px' }}
                    />
                    <span style={{ textDecoration: isChecked ? 'line-through' : 'none', opacity: isChecked ? 0.5 : 1 }}>
                       {cleanLine}
                    </span>
                  </div>
                );
             }
             return <p key={idx} style={{ margin: 0, marginTop: idx > 0 ? '4px' : 0 }} dangerouslySetInnerHTML={{ __html: line.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>').replace(/\[(.*?)\]\((.*?)\)/g, '<a href="$2" target="_blank" style="color: var(--accent-blue)">$1</a>') }}></p>;
          }) : (
            <>
              <div dangerouslySetInnerHTML={{ __html: (!isExpanded && content.length > 300 ? content.slice(0, 300) + '...' : content).split('\n').map(line => `<p style="margin: 0; margin-top: 4px;">${line.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>').replace(/\[(.*?)\]\((.*?)\)/g, '<a href="$2" target="_blank" style="color: var(--accent-blue)">$1</a>')}</p>`).join('') }}></div>
              {content.length > 300 && (
                <button onClick={(e) => { e.stopPropagation(); setIsExpanded(!isExpanded); }} style={{ background: 'transparent', border: 'none', color: 'var(--accent-blue)', padding: '0', marginTop: '0.5rem', cursor: 'pointer', fontSize: '0.85rem' }}>
                  {isExpanded ? 'Show Less' : 'Load More...'}
                </button>
              )}
            </>
          )}
        </div>
      )}

      {attachments && attachments.length > 0 && (
        <div style={{ marginTop: '0.5rem', marginBottom: '1rem', display: 'flex', gap: '0.5rem', flexWrap: 'wrap' }} onClick={e => e.stopPropagation()}>
          {attachments.map((att, idx) => (
            <div key={idx} style={{ 
              borderRadius: '8px', 
              overflow: 'hidden', 
              border: '1px solid var(--border-subtle)',
              background: 'rgba(0,0,0,0.2)',
              width: att.type.startsWith('image/') ? '120px' : 'auto',
              display: 'flex',
              flexDirection: 'column'
            }}>
              {att.type.startsWith('image/') ? (
                <img src={att.data} alt={att.name} style={{ width: '100%', height: '80px', objectFit: 'cover', cursor: 'zoom-in' }} onClick={(e) => { e.stopPropagation(); setExpandedImage(att.data); }} />
              ) : (
                <div style={{ padding: '0.5rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                  <span style={{ fontSize: '0.75rem', color: 'var(--text-secondary)', maxWidth: '150px', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>📎 {att.name}</span>
                </div>
              )}
            </div>
          ))}
        </div>
      )}

      {isEphemeral && (
        <div style={{ background: 'rgba(234, 179, 8, 0.1)', border: '1px solid rgba(234, 179, 8, 0.5)', borderRadius: '8px', padding: '0.5rem', marginBottom: '1rem', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span style={{ fontSize: '0.75rem', color: '#eab308' }}>⏱ Ephemeral Intelligence: Auto-deletes in 30m</span>
          <button onClick={handleKeep} style={{ background: '#eab308', color: '#000', border: 'none', padding: '0.2rem 0.6rem', borderRadius: '4px', fontSize: '0.75rem', fontWeight: 'bold', cursor: 'pointer' }}>Keep</button>
        </div>
      )}

      {linked_thoughts && linked_thoughts.length > 0 && (
        <div style={{ display: 'flex', gap: '0.5rem', marginBottom: '1rem', flexWrap: 'wrap' }}>
          {linked_thoughts.map(link => {
            const targetThought = allThoughts.find(t => t.id === link || t.thought_id === link);
            const displayName = targetThought ? targetThought.thought_id : link;
            return (
              <span 
                key={link} 
                onClick={(e) => { e.stopPropagation(); if(onAction) onAction('navigate', targetThought ? targetThought.id : link); }}
                style={{ fontSize: '0.75rem', background: 'rgba(139, 92, 246, 0.2)', color: 'var(--neon-purple)', padding: '2px 8px', borderRadius: '12px', display: 'flex', alignItems: 'center', gap: '4px', cursor: 'pointer' }}>
                <Link2 size={10} /> {displayName}
              </span>
            );
          })}
        </div>
      )}

      {status !== 'trash' && status !== 'vaulted_trash' && (
      <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '0.5rem', opacity: 0.6, transition: 'opacity 0.2s' }} 
           className="card-actions">
        
        <button 
          title="Rename / Edit" 
          onClick={(e) => { e.stopPropagation(); setIsEditing(true); }}
          style={{ background: 'transparent', border: 'none', padding: '4px' }}>
          <Edit3 size={16} color="var(--text-primary)" />
        </button>
        
        <button 
          title="Link Thought" 
          onClick={(e) => { e.stopPropagation(); onAction('link', thought); }}
          style={{ background: 'transparent', border: 'none', padding: '4px' }}>
          <Link2 size={16} color="var(--text-primary)" />
        </button>
        
        <button 
          title={pinned ? "Unpin" : "Pin"} 
          onClick={handlePin}
          style={{ background: 'transparent', border: 'none', padding: '4px' }}>
          <Pin size={16} color={pinned ? "var(--accent-blue)" : "var(--text-primary)"} />
        </button>
        
        {status !== 'archived' && (
          <button 
            title="Mark Done" 
            onClick={handleMarkDone}
            style={{ background: 'transparent', border: 'none', padding: '4px', cursor: 'pointer' }}
          >
            <CheckCircle size={16} color="#10b981" />
          </button>
        )}
      </div>
      )}

      {showStealthMenu && (
        <div style={{ marginTop: '1rem', padding: '0.5rem', background: 'black', borderRadius: '4px', display: 'flex', gap: '1rem', border: '1px solid #333' }}>
          {(status === 'trash' || status === 'vaulted_trash') ? (
            <>
              <button onClick={handleRestore} style={{ background: 'transparent', color: '#10b981', fontSize: '0.75rem', padding: '4px 8px' }}>Restore Context</button>
              <button onClick={handleStealthDelete} style={{ background: 'transparent', color: '#ef4444', fontSize: '0.75rem', padding: '4px 8px' }}>Eradicate Permanently</button>
            </>
          ) : (
            <>
              {status !== 'vaulted' && <button onClick={handleMoveToVault} style={{ background: 'transparent', color: 'var(--neon-purple)', fontSize: '0.75rem', padding: '4px 8px' }}>Encrypt & Move to Vault</button>}
              <button onClick={handleStealthDelete} style={{ background: 'transparent', color: '#ef4444', fontSize: '0.75rem', padding: '4px 8px' }}>Eradicate to Deep Trash</button>
            </>
          )}
        </div>
      )}

      {expandedImage && (
        <div 
          onClick={(e) => { e.stopPropagation(); setExpandedImage(null); }}
          style={{
            position: 'fixed', top: 0, left: 0, right: 0, bottom: 0,
            background: 'rgba(0,0,0,0.9)', zIndex: 9999,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            cursor: 'zoom-out'
          }}
        >
          <img src={expandedImage} alt="Expanded" style={{ maxWidth: '90vw', maxHeight: '90vh', objectFit: 'contain' }} />
        </div>
      )}
    </div>
  );
}
