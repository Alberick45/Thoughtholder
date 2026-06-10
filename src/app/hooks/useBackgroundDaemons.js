import { useEffect } from 'react';
import { refreshAttentionStates } from '../../shared/infrastructure/db';

export function useBackgroundDaemons(db, addThought, generateUUID, setUnreadJarvis, setJarvisPreview, setJarvisOfflineAlert) {
  useEffect(() => {
    refreshAttentionStates();
    const interval = setInterval(refreshAttentionStates, 60 * 60 * 1000);
    
    // Ephemeral Cleanup Routine (Check every minute)
    const ephemeralCleanup = async () => {
      const allT = await db.thoughts.toArray();
      const now = Date.now();
      allT.forEach(t => {
        const isEphemeral = (t.tags?.includes('net-result') || t.tags?.includes('siphoned')) && !t.tags?.includes('kept');
        if (isEphemeral && (now - t.created_at) > 30 * 60 * 1000) {
          db.thoughts.delete(t.id);
        }
      });
    };
    const ephemeralInterval = setInterval(ephemeralCleanup, 60 * 1000);
    
    // Awareness Signal Aggregator (Every 5 minutes)
    const awarenessInterval = setInterval(async () => {
        try {
            const { EnvironmentalSignalAggregator } = await import('../../features/intelligence/awareness/EnvironmentalSignalAggregator');
            const aggregator = new EnvironmentalSignalAggregator(db);
            await aggregator.persist();
            
            const { LifeContextModel } = await import('../../features/intelligence/memory/LifeContextModel');
            const lifeModel = new LifeContextModel(db);
            await lifeModel.update();
            
            const { TemporalMemoryEngine } = await import('../../features/intelligence/memory/TemporalMemoryEngine');
            const temporalEngine = new TemporalMemoryEngine(db);
            await temporalEngine.analyzeRhythms();
            
            const { GoalContinuityTracker } = await import('../../features/intelligence/awareness/GoalContinuityTracker');
            const continuityTracker = new GoalContinuityTracker(db);
            await continuityTracker.analyzeContinuity(lifeModel, aggregator.state || {});
            
            const { BehavioralForecaster } = await import('../../features/intelligence/awareness/BehavioralForecaster');
            const forecaster = new BehavioralForecaster(db);
            await forecaster.forecast();
        } catch (e) {
            console.warn("[AWARENESS] Aggregation failed:", e);
        }
    }, 5 * 60 * 1000);

    // Environment Reasoning Loop (Every 1 minute)
    const envInterval = setInterval(async () => {
        try {
            const { reasonAboutEnvironment } = await import('../../features/intelligence/environment/environmentReasoner');
            
            // Manage state history for fatigue estimation
            let history = JSON.parse(localStorage.getItem('jaos_state_history') || '[]');
            const result = reasonAboutEnvironment(history);
            
            // Update history (keep last 20 entries)
            history.push([result.currentState, Date.now()]);
            if (history.length > 20) history.shift();
            
            localStorage.setItem('jaos_state_history', JSON.stringify(history));
            localStorage.setItem('jaos_current_state', result.currentState);
            localStorage.setItem('jaos_fatigue_level', result.fatigue.toFixed(2));
            
            try {
                await db.settings.put({ key: 'jaos_state_history', value: history });
                await db.settings.put({ key: 'jaos_current_state', value: result.currentState });
                await db.settings.put({ key: 'jaos_fatigue_level', value: result.fatigue });
            } catch (e) {
                console.warn("[ENV] DB persistence failed:", e);
            }
            
            if (result.isOverloaded) {
                console.log("[ENV] User stress/overload detected. Recalibrating attention policy.");
            }
        } catch (e) {
            console.warn("[ENV] Reasoning failed:", e);
        }
    }, 60 * 1000);
    
    // Evolution Loop (Every 1 hour)
    const evolutionInterval = setInterval(async () => {
        try {
            const { forecastFutureNeeds } = await import('../../features/intelligence/evolution/predictiveEngine');
            const { analyzeHabits } = await import('../../features/intelligence/evolution/habitModeler');
            const { calculateEvolutionState } = await import('../../features/intelligence/evolution/personalityEvolution');
            
            const forecast = await forecastFutureNeeds();
            const habits = await analyzeHabits();
            const evolution = await calculateEvolutionState();
            
            localStorage.setItem('jaos_forecast', JSON.stringify(forecast));
            localStorage.setItem('jaos_habits', JSON.stringify(habits));
            localStorage.setItem('jaos_evolution_state', JSON.stringify(evolution));
            
            try {
                await db.settings.put({ key: 'jaos_forecast', value: forecast });
                await db.settings.put({ key: 'jaos_habits', value: habits });
                await db.settings.put({ key: 'jaos_evolution_state', value: evolution });
            } catch (e) {
                console.warn("[EVOLUTION] DB persistence failed:", e);
            }
            
            console.log("[EVOLUTION] Cognitive model evolved. Relational Depth:", evolution.depth);
        } catch (e) {
            console.warn("[EVOLUTION] Model evolution failed:", e);
        }
    }, 60 * 60 * 1000);
    
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
          
          // PHASE 3: ATTENTIONAL INTELLIGENCE
          const { getWorkingMemory } = await import('../../features/intelligence/memory/workingMemory');
          const workingMem = await getWorkingMemory();
          const { analyzeCognitiveLoad } = await import('../../features/intelligence/attention/cognitiveLoadAnalyzer');
          const cogLoad = analyzeCognitiveLoad(allT, workingMem.activeFocus);
          
          const { LifeContextModel } = await import('../../features/intelligence/memory/LifeContextModel');
          const lifeModel = LifeContextModel.getModel();
          
          const { evaluateInterruption } = await import('../../features/intelligence/attention/interruptionEngine');
          const { classifyUrgency } = await import('../../features/intelligence/attention/urgencyClassifier');
          
          const { GoalContinuityTracker } = await import('../../features/intelligence/awareness/GoalContinuityTracker');
          const continuity = GoalContinuityTracker.getContinuity();
          
          const { BehavioralForecaster } = await import('../../features/intelligence/awareness/BehavioralForecaster');
          const forecast = BehavioralForecaster.getForecast();
          
          const urgency = upcoming.length > 0 ? classifyUrgency({ content: `Upcoming: ${upcoming[0].e}` }) : 0.1;
          const continuityValue = (continuity.stalledPillars?.length > 0) ? 0.6 : 0.0;
          
          const decision = evaluateInterruption({
             urgency: Math.max(urgency, continuityValue),
             relevance: (upcoming.length > 0 || (lifeModel.focus && upcoming.some(u => u.e.toLowerCase().includes(lifeModel.focus)))) ? 0.9 : 0.3,
             confidence: 1.0,
             cognitiveLoad: cogLoad,
             userState: forecast.predictedState === 'Peak Activity' ? 'DEEP_WORK' : 'IDLE'
          });

          if (!decision.shouldInterrupt) {
             console.log("[ORCHESTRATION] Silence maintained. Cost:", decision.interruptionCost.toFixed(2), "Value:", decision.infoValue.toFixed(2));
             return;
          }

          let promptObj;
          if (upcoming.length > 0) {
              const evInfo = upcoming.map(x => `${x.e} (in ${x.d} days)`).join(', ');
              promptObj = `[AMBIENT SIGNAL: UPCOMING EVENT] ${evInfo}. Gently resurface this. Keep it under 2 sentences. No pressure.`;
          } else if (continuity.stalledPillars?.length > 0) {
              const pillar = continuity.stalledPillars[0].name;
              promptObj = `[AMBIENT SIGNAL: STALLED PROJECT] You noticed activity on "${pillar}" has drifted for ${continuity.stalledPillars[0].daysIdle} days. Mention this as a soft anchor. Do not sound like a productivity bot.`;
          } else {
              promptObj = `[AMBIENT SIGNAL: LOW PRESSURE] Act as a social companion. If I have no tasks, just spark a casual 1-sentence conversation checking how I feel. Output 'NO' if nothing useful to say.`;
          }
          
          const { askJarvisWithContext } = await import('../../features/intelligence/services/jarvis');
          try {
            const reply = await askJarvisWithContext(promptObj, db);
            if (reply && !reply.toUpperCase().includes('NO') && reply.length > 5) {
                // Clean the reply for the preview (strip markdown and newlines)
                const cleanPreview = reply.replace(/[*_`#]/g, '').replace(/\n/g, ' ').trim();
                const words = cleanPreview.split(/\s+/).filter(Boolean);
                
                if (words.length > 0) {
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
                    setJarvisPreview(words.slice(0, 10).join(' ') + (words.length > 10 ? '...' : ''));
                }
            }
          } catch (e) {}
       }
    }, 10 * 60 * 1000);
    
    // Psychoanalysis Background Routine (24-hour cycle)
    const psychoInterval = setInterval(async () => {
       const lastPsycho = localStorage.getItem('last_psycho_analysis') || 0;
       const now = Date.now();
       if (now - parseInt(lastPsycho) > 24 * 60 * 60 * 1000 && localStorage.getItem('jarvis_leash') === '2') {
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
                 console.log("[DEEP MIND] Psychoanalysis successfully calculated and saved to DB");
              }
           } catch (e) {
              console.log("[DEEP MIND] Analysis skipped due to offline engine.");
           }
       }
    }, 60 * 60 * 1000);

    return () => {
      clearInterval(interval);
      clearInterval(ephemeralInterval);
      clearInterval(awarenessInterval);
      clearInterval(envInterval);
      clearInterval(evolutionInterval);
      clearInterval(daemonInterval);
      clearInterval(psychoInterval);
    };
  }, [db, addThought, generateUUID]);
}
