import React, { useState, useCallback } from 'react';
import { formatDistanceToNow } from 'date-fns';
import { Edit3, CheckCircle, Pin, Shield, Trash2, RotateCcw, X, Link2 } from 'lucide-react';
import { updateThought, deleteThought } from '../../../shared/infrastructure/db';
import { useLongPress } from '../../../shared/hooks/useLongPress';

export default function ThoughtCard({ thought, allThoughts = [], onAction }) {
  const { id, thought_id, content, type, status, created_at, pinned = false } = thought;
  const [isEditing, setIsEditing] = useState(false);
  const [editContent, setEditContent] = useState(content);
  const [editTitle, setEditTitle] = useState(thought_id);
  const [showStealthMenu, setShowStealthMenu] = useState(false);

  const getTypeColor = (t) => {
    switch (t) {
      case 'idea': return '#eab308';
      case 'task': return '#ef4444';
      case 'note': return '#8b5cf6';
      default: return '#3b82f6';
    }
  };

  const handleLongPress = useCallback(() => {
    setShowStealthMenu(true);
    if (navigator.vibrate) navigator.vibrate(50);
  }, []);

  const longPressProps = useLongPress(handleLongPress);

  const handleMarkDone = async (e) => {
    e.stopPropagation();
    await updateThought(id, { status: 'archived' });
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

  const handleStealthDelete = async (e) => {
    e.stopPropagation();
    if (status === 'trash' || status === 'vaulted_trash') {
      await deleteThought(id);
    } else {
      await updateThought(id, { status: status === 'vaulted' ? 'vaulted_trash' : 'trash' });
    }
    setShowStealthMenu(false);
  };

  const handleRestore = async (e) => {
    e.stopPropagation();
    await updateThought(id, { status: status === 'vaulted_trash' ? 'vaulted' : 'fresh' });
    setShowStealthMenu(false);
  };

  const handleMoveToVault = async (e) => {
    e.stopPropagation();
    await updateThought(id, { status: 'vaulted' });
    if (onAction) onAction('moved_to_vault', thought);
    setShowStealthMenu(false);
  };

  return (
    <div
      className="glass-panel"
      onClick={() => !showStealthMenu && !isEditing && updateThought(id, { status: 'active', last_viewed_at: Date.now() })}
      {...longPressProps}
      style={{
        padding: '1rem',
        marginBottom: '1rem',
        borderLeft: `4px solid ${getTypeColor(type)}`,
        background: pinned ? 'rgba(59, 130, 246, 0.1)' : undefined,
        position: 'relative'
      }}
    >
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '0.6rem' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.4rem', flexWrap: 'wrap' }}>
          {pinned && <Pin size={12} color="var(--accent-blue)" />}
          <span style={{ fontWeight: 'bold', fontSize: '0.85rem' }}>{thought_id}</span>
          <span style={{ fontSize: '0.6rem', background: 'var(--bg-tertiary)', padding: '1px 6px', borderRadius: '10px' }}>{type}</span>
        </div>
        <span style={{ fontSize: '0.7rem', color: 'var(--text-muted)' }}>
          {created_at ? formatDistanceToNow(created_at, { addSuffix: true }) : '...'}
        </span>
      </div>

      {isEditing ? (
        <div onClick={e => e.stopPropagation()} style={{ marginBottom: '1rem' }}>
          <input value={editTitle} onChange={e => setEditTitle(e.target.value)} style={{ width: '100%', marginBottom: '0.5rem', background: '#000', color: 'white', border: '1px solid #333', padding: '0.5rem', borderRadius: '8px' }} />
          <textarea value={editContent} onChange={e => setEditContent(e.target.value)} style={{ width: '100%', minHeight: '80px', background: '#000', color: 'white', border: '1px solid #333', padding: '0.5rem', borderRadius: '8px' }} />
          <div style={{ marginTop: '0.5rem', display: 'flex', gap: '0.5rem' }}>
            <button onClick={handleSaveEdit} style={{ background: 'var(--accent-blue)', color: 'white', padding: '0.4rem 1rem', borderRadius: '8px', fontSize: '0.8rem' }}>Save</button>
            <button onClick={() => setIsEditing(false)} style={{ padding: '0.4rem 1rem', borderRadius: '8px', fontSize: '0.8rem', background: 'transparent', color: 'white', border: '1px solid #333' }}>Cancel</button>
          </div>
        </div>
      ) : (
        <div style={{ fontSize: '0.95rem', lineHeight: '1.4', marginBottom: '0.8rem', whiteSpace: 'pre-wrap' }}>
          {content}
        </div>
      )}

      <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '1rem', opacity: 0.5 }}>
        <button onClick={(e) => { e.stopPropagation(); setIsEditing(true); }} style={{ background: 'transparent', border: 'none' }}><Edit3 size={16} color="white" /></button>
        <button onClick={handlePin} style={{ background: 'transparent', border: 'none' }}><Pin size={16} color={pinned ? 'var(--accent-blue)' : 'white'} /></button>
        {status !== 'archived' && <button onClick={handleMarkDone} style={{ background: 'transparent', border: 'none' }}><CheckCircle size={16} color="#10b981" /></button>}
      </div>

      {showStealthMenu && (
        <div onClick={e => e.stopPropagation()} style={{ position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, background: 'rgba(0,0,0,0.8)', zIndex: 6000, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '1.5rem' }}>
          <div className="glass-panel" style={{ width: '100%', background: '#111', padding: '1.5rem', borderRadius: '16px', border: '1px solid var(--border-focus)' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '1.5rem' }}>
              <h3 style={{ margin: 0, fontSize: '1rem', color: 'white' }}>{thought_id}</h3>
              <button onClick={() => setShowStealthMenu(false)} style={{ background: 'transparent', border: 'none' }}><X size={20} color="white" /></button>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.8rem' }}>
              {(status === 'trash' || status === 'vaulted_trash') ? (
                <>
                  <button onClick={handleRestore} style={{ background: 'rgba(16, 185, 129, 0.1)', color: '#10b981', padding: '1rem', borderRadius: '12px', textAlign: 'left', fontWeight: 'bold', border: '1px solid #10b981' }}>Restore Context</button>
                  <button onClick={handleStealthDelete} style={{ background: 'rgba(239, 68, 68, 0.1)', color: '#ef4444', padding: '1rem', borderRadius: '12px', textAlign: 'left', fontWeight: 'bold', border: '1px solid #ef4444' }}>Eradicate Permanently</button>
                </>
              ) : (
                <>
                  {status !== 'vaulted' && <button onClick={handleMoveToVault} style={{ background: 'rgba(139, 92, 246, 0.1)', color: 'var(--neon-purple)', padding: '1rem', borderRadius: '12px', textAlign: 'left', fontWeight: 'bold', border: '1px solid var(--neon-purple)', display: 'flex', alignItems: 'center', gap: '0.8rem' }}><Shield size={18} /> Encrypt & Vault</button>}
                  <button onClick={handleStealthDelete} style={{ background: 'rgba(239, 68, 68, 0.1)', color: '#ef4444', padding: '1rem', borderRadius: '12px', textAlign: 'left', fontWeight: 'bold', border: '1px solid #ef4444', display: 'flex', alignItems: 'center', gap: '0.8rem' }}><Trash2 size={18} /> Eradicate to Trash</button>
                </>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
