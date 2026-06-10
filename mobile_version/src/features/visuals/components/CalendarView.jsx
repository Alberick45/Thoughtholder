import React, { useState } from 'react';

export default function CalendarView({ thoughts }) {
  const [currentDate, setCurrentDate] = useState(new Date());

  const daysInMonth = new Date(currentDate.getFullYear(), currentDate.getMonth() + 1, 0).getDate();
  const firstDay = new Date(currentDate.getFullYear(), currentDate.getMonth(), 1).getDay();

  const prevMonth = () => setCurrentDate(new Date(currentDate.getFullYear(), currentDate.getMonth() - 1, 1));
  const nextMonth = () => setCurrentDate(new Date(currentDate.getFullYear(), currentDate.getMonth() + 1, 1));

  const thoughtsForDate = (dateNum) => {
    return thoughts.filter(t => {
      // 1. Explicit Event parsing
      if (t.type === 'event' && t.content.includes('[EVENT:')) {
         const dStr = t.content.match(/\[EVENT:(.*?)\]/)?.[1];
         if (dStr && dStr.includes('-')) {
            const [y, m, d] = dStr.split('-').map(Number);
            return d === dateNum && (m-1) === currentDate.getMonth() && y === currentDate.getFullYear();
         }
      }
      // 2. Generic fallback to created_at
      const td = new Date(t.created_at);
      return td.getDate() === dateNum && td.getMonth() === currentDate.getMonth() && td.getFullYear() === currentDate.getFullYear();
    });
  };

  const [activeDateModal, setActiveDateModal] = useState(null);
  const [eventInput, setEventInput] = useState('');

  const handleAddEvent = async (dayNum) => {
     if (!eventInput.trim()) {
        setActiveDateModal(null);
        return;
     }
     const d = new Date(currentDate.getFullYear(), currentDate.getMonth(), dayNum);
     const dateStr = `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
     
     import('../../../shared/infrastructure/db').then(({ addThought, generateUUID }) => {
        addThought({
          id: generateUUID(),
          thought_id: `Event-${Math.floor(Math.random()*9000)}`,
          content: `[EVENT:${dateStr}] ${eventInput.trim()}`,
          type: 'event', status: 'fresh', tags: ['schedule'], summary: '',
          created_at: Date.now(), last_viewed_at: Date.now(), stale_score: 0, linked_thoughts: []
        });
        setEventInput('');
        setActiveDateModal(null);
     });
  };

  return (
    <div style={{ padding: '0.5rem', marginBottom: '1rem', color: 'white' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
         <button onClick={prevMonth} style={{ background: 'var(--bg-secondary)', color: 'white', border: '1px solid var(--border-subtle)', cursor: 'pointer', padding: '0.4rem 0.8rem', borderRadius: '4px' }}>&lt; Prev</button>
         <h2 style={{ margin: 0, color: 'var(--neon-purple)', fontSize: '1rem', textTransform: 'uppercase', letterSpacing: '1px' }}>{currentDate.toLocaleString('default', { month: 'long' })} {currentDate.getFullYear()}</h2>
         <button onClick={nextMonth} style={{ background: 'var(--bg-secondary)', color: 'white', border: '1px solid var(--border-subtle)', cursor: 'pointer', padding: '0.4rem 0.8rem', borderRadius: '4px' }}>Next &gt;</button>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: '4px' }}>
         {['Sun','Mon','Tue','Wed','Thu','Fri','Sat'].map(d => (
           <div key={d} style={{ textAlign: 'center', fontSize: '0.65rem', color: 'var(--text-muted)', fontWeight: 'bold', textTransform: 'uppercase' }}>{d}</div>
         ))}
         {Array.from({ length: firstDay }).map((_, i) => <div key={`empty-${i}`}></div>)}
         {Array.from({ length: daysInMonth }).map((_, i) => {
           const dayNum = i + 1;
           const dayThoughts = thoughtsForDate(dayNum);
           const today = new Date();
           const isToday = today.getDate() === dayNum && today.getMonth() === currentDate.getMonth() && today.getFullYear() === currentDate.getFullYear();
           
           const dayEvents = dayThoughts.filter(t => t.type === 'event');
           const genericCount = dayThoughts.filter(t => t.type !== 'event').length;
           
           return (
             <div key={dayNum} 
               onClick={() => { setActiveDateModal(dayNum); setEventInput(''); }}
               style={{ 
                minHeight: '70px', 
                background: isToday ? 'rgba(139, 92, 246, 0.15)' : 'rgba(20,20,25,0.6)', 
                border: isToday ? '1px solid var(--neon-purple)' : '1px solid var(--border-subtle)',
                borderRadius: '6px', padding: '0.4rem', cursor: 'pointer',
                position: 'relative',
                transition: 'transform 0.1s',
                ...(activeDateModal === dayNum ? { outline: '2px solid var(--accent-blue)', background: 'rgba(59, 130, 246, 0.2)' } : {})
             }}>
               <span style={{ fontSize: '0.85rem', color: isToday ? 'var(--neon-purple)' : '#ccc', fontWeight: isToday ? 'bold' : 'normal' }}>{dayNum}</span>
               
               {/* Event Indicator Dots */}
               {(dayEvents.length > 0 || genericCount > 0) && (
                 <div style={{ display: 'flex', flexWrap: 'wrap', gap: '3px', marginTop: '6px', justifyContent: 'center' }}>
                   {dayEvents.map(e => {
                      const isBirthday = e.content.toLowerCase().includes('birthday');
                      return <div key={e.id} style={{ width: '8px', height: '8px', borderRadius: '50%', background: isBirthday ? '#f97316' : 'var(--accent-blue)', boxShadow: `0 0 8px ${isBirthday ? '#f97316' : 'var(--accent-blue)'}` }} title={isBirthday ? "Birthday" : "Scheduled Event"} />
                   })}
                   {Array.from({length: Math.min(genericCount, 3)}).map((_, idx) => (
                      <div key={idx} style={{ width: '6px', height: '6px', borderRadius: '50%', background: '#666' }} title="Routine Activity" />
                   ))}
                 </div>
               )}
             </div>
           );
         })}
      </div>

      {/* Massive Central Modal Overlay for the Active Date */}
      {activeDateModal !== null && (() => {
         const activeEvents = thoughtsForDate(activeDateModal).filter(t => t.type === 'event');
         return (
         <div style={{ position: 'absolute', top: 0, left: 0, width: '100%', height: '100%', background: 'rgba(5, 5, 8, 0.85)', backdropFilter: 'blur(4px)', zIndex: 100, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '2rem' }}>
            <div style={{ background: '#111', border: '1px solid var(--neon-purple)', borderRadius: '12px', width: '100%', padding: '1.5rem', boxShadow: '0 12px 40px rgba(0,0,0,0.8)' }}>
               <h3 style={{ marginTop: 0, color: 'var(--neon-purple)', borderBottom: '1px solid #333', paddingBottom: '0.5rem', marginBottom: '1rem' }}>
                  Schedule: {currentDate.toLocaleString('default', { month: 'long' })} {activeDateModal}, {currentDate.getFullYear()}
               </h3>
               
               <div style={{ maxHeight: '150px', overflowY: 'auto', marginBottom: '1rem', display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                  {activeEvents.length > 0 ? activeEvents.map(e => (
                     <div key={e.id} style={{ background: 'rgba(59, 130, 246, 0.1)', borderLeft: '3px solid var(--accent-blue)', padding: '0.5rem', fontSize: '0.9rem', color: '#e2e8f0' }}>
                        {e.content.replace(/\[EVENT:.*?\]/i, '').trim()}
                     </div>
                  )) : (
                     <div style={{ color: '#666', fontStyle: 'italic', fontSize: '0.9rem' }}>No events scheduled for this day.</div>
                  )}
               </div>

               <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                  <input 
                     autoFocus
                     value={eventInput}
                     onChange={e => setEventInput(e.target.value)}
                     onKeyDown={e => { if(e.key === 'Enter') handleAddEvent(activeDateModal); if(e.key === 'Escape') setActiveDateModal(null); }}
                     placeholder="Type new event here..."
                     style={{ width: '100%', background: '#000', color: 'white', border: '1px solid #444', fontSize: '1rem', padding: '0.8rem', borderRadius: '6px', outline: 'none' }}
                  />
                  <div style={{ display: 'flex', gap: '0.5rem', marginTop: '0.5rem' }}>
                     <button onClick={() => handleAddEvent(activeDateModal)} style={{ flex: 1, background: 'var(--accent-blue)', border: 'none', color: 'white', fontSize: '0.9rem', padding: '0.6rem', borderRadius: '4px', cursor: 'pointer', fontWeight: 'bold' }}>Save Event</button>
                     <button onClick={() => setActiveDateModal(null)} style={{ flex: 1, background: 'transparent', border: '1px solid #555', color: '#aaa', fontSize: '0.9rem', padding: '0.6rem', borderRadius: '4px', cursor: 'pointer' }}>Close</button>
                  </div>
               </div>
            </div>
         </div>
      );})()}
    </div>
  );
}
