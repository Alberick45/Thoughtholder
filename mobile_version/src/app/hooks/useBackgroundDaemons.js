import { useEffect } from 'react';
import { refreshAttentionStates, generateUUID } from '../../shared/infrastructure/db';
import { AI_CONFIG } from '../../core/config/constants';

export function useBackgroundDaemons(db, addThought, setUnreadJarvis, setJarvisPreview, setJarvisOfflineAlert) {
  useEffect(() => {
    refreshAttentionStates();
    const interval = setInterval(refreshAttentionStates, AI_CONFIG.DB_ATTENTION_INTERVAL || 60 * 60 * 1000);
    
    // Jarvis Offline Alert Check
    if (localStorage.getItem('dismiss_jarvis_alert') !== 'true') {
       fetch(`${AI_CONFIG.OLLAMA_BASE_URL}/api/tags`).catch(() => setJarvisOfflineAlert(true));
    }
    
    // Proactive Daemon Hook (10 Minute checks)
    const daemonInterval = setInterval(async () => {
       if (localStorage.getItem('jarvis_leash') === '2') {
          const allT = await db.thoughts.toArray();
          const now = new Date();
          
          const upcoming = allT.filter(t => t.type === 'event').map(t => { 
             const dStr = t.content.match(/\[EVENT:(.*?)\]/)?.[1];
             if (dStr) {
                const ed = new Date(dStr);
                const daysLeft = (ed - now) / (1000 * 60 * 60 * 24);
                if (daysLeft >= 0 && daysLeft <= 3) return { e: t.content.replace(/\[EVENT:.*?\]/,''), d: Math.ceil(daysLeft) };
             }
             return null;
          }).filter(Boolean);
          
          let promptObj;
          if (upcoming.length > 0) {
              const evInfo = upcoming.map(x => `${x.e} (in ${x.d} days)`).join(', ');
              promptObj = `I have an upcoming event: ${evInfo}. Proactively bring this up to me as a companion. Offer help to prepare or just spark a conversation about it. Keep it under 2 sentences.`;
          } else {
              promptObj = `Act as my social companion. Based on my active tasks and recent actions, is there an important proactive question or motivation you should assert to keep me on track? If I have no tasks, just spark a casual 1-sentence conversation checking how I feel. If you have nothing to say, output strictly only the word 'NO'.`;
          }
          
          const { askJarvisWithContext } = await import('../../features/intelligence/services/jarvis');
          try {
            const reply = await askJarvisWithContext(promptObj, db);
            if (reply && !reply.toUpperCase().includes('NO') && reply.length > 5) {
                await addThought({ 
                  id: generateUUID(), 
                  thought_id: `Daemon-${Math.floor(Math.random()*9000)}`, 
                  content: `**Jarvis (Autonomous Query):**\n${reply}`, 
                  type: 'jarvis_log', 
                  status: 'fresh', 
                  tags: ['jarvis-verified'], 
                  created_at: Date.now(), 
                  last_viewed_at: Date.now(), 
                  stale_score: 0, 
                  linked_thoughts: [] 
                });
                setUnreadJarvis(prev => prev + 1);
                setJarvisPreview(reply.split(' ').slice(0, 8).join(' ') + '...');
            }
          } catch (e) {}
       }
    }, AI_CONFIG.DAEMON_CHECK_INTERVAL);
    
    // Psychoanalysis Background Routine (24-hour cycle)
    const psychoInterval = setInterval(async () => {
       const lastPsycho = localStorage.getItem('last_psycho_analysis') || 0;
       const now = Date.now();
       if (now - parseInt(lastPsycho) > AI_CONFIG.PSYCHO_ANALYSIS_INTERVAL && localStorage.getItem('jarvis_leash') === '2') {
           try {
              const thoughts = await db.thoughts.toArray();
              const valid = thoughts.filter(t => t.status !== 'trash' && t.status !== 'vaulted').slice(0, 50);
              const dataDump = valid.map(t => `[${t.type}] ${t.content}`).join('\n');
              
              if (dataDump.length > 50) {
                 const { askJarvis } = await import('../../features/intelligence/services/jarvis');
                 const psychoPrompt = `You are a clinical psychoanalyst. Read the following brain dump of a user's recent actions, tasks, and notes. Generate a highly concise breakdown of their psychological profile, their obvious strengths, and their weaknesses/procrastination habits. Output ONLY the clinical profile directly.`;
                 
                 const profile = await askJarvis(dataDump, psychoPrompt);
                 await db.settings.put({ key: 'jarvis_profile', value: profile });
                 localStorage.setItem('last_psycho_analysis', now.toString());
              }
           } catch (e) {}
       }
    }, 60 * 60 * 1000);

    return () => {
      clearInterval(interval);
      clearInterval(daemonInterval);
      clearInterval(psychoInterval);
    };
  }, [db, addThought]);
}
