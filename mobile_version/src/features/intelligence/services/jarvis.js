import { AI_CONFIG } from '../../../core/config/constants';

export async function askJarvis(promptStr, systemPrompt = 'You are Jarvis, a brilliant localized AI assistant. Keep responses extremely concise.') {
  try {
    const remoteIp = localStorage.getItem('remote_jarvis_ip') || 'localhost';
    const baseUrl = localStorage.getItem('remote_jarvis_ip') ? `http://${localStorage.getItem('remote_jarvis_ip')}:11434` : AI_CONFIG.OLLAMA_BASE_URL;

    // 1. Detect downloaded model dynamically
    const tagsRes = await fetch(`${baseUrl}/api/tags`);
    if (!tagsRes.ok) throw new Error('Ollama not running');
    const tagsData = await tagsRes.json();
    if (!tagsData.models || tagsData.models.length === 0) {
       throw new Error('JARVIS_NO_MODELS');
    }
    const detectedModel = tagsData.models[0].name;

    // 2. Send payload to detected model
    const response = await fetch(`${baseUrl}/api/generate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: detectedModel, 
        prompt: promptStr,
        system: systemPrompt,
        stream: false
      })
    });
    
    if (!response.ok) throw new Error('Local LLM returned an error');
    const data = await response.json();
    return data.response.trim();
  } catch (error) {
    console.warn('[JARVIS] Ollama unreachable. Escalating to Local WASM Intelligence...', error);
    try {
      const { askLocalAI } = await import('./localAi');
      return await askLocalAI(promptStr, systemPrompt);
    } catch (localErr) {
      console.error('[JARVIS] Critical AI Failure (Ollama & Local WASM):', localErr);
      throw new Error('JARVIS_OFFLINE');
    }
  }
}

export async function processOCR(rawText) {
  const { OCR_CLEANING_PROMPT } = await import('../prompts/jarvisPrompts');
  return await askJarvis(rawText, OCR_CLEANING_PROMPT);
}

export async function askJarvisWithContext(query, db, inVault = false) {
  try {
    const remoteIp = localStorage.getItem('remote_jarvis_ip') || 'localhost';
    const baseUrl = `http://${remoteIp}:11434`;

  // 1. Detect downloaded model dynamically
  const tagsRes = await fetch(`${baseUrl}/api/tags`);
  if (!tagsRes.ok) throw new Error('Ollama not running');
  const tagsData = await tagsRes.json();
  if (!tagsData.models || tagsData.models.length === 0) {
     throw new Error('JARVIS_NO_MODELS');
  }
  const detectedModel = tagsData.models[0].name;

  // 2. 🏗️ COGNITIVE PIPELINE (LAYERS 1-4)
  const allThoughts = await db.thoughts.toArray();
  const nowMs = Date.now();
  
  // Layer 2: Thought Analyzer
  const { ThoughtAnalyzer } = await import('../runtime/ThoughtAnalyzer');
  const recentThoughts = allThoughts.filter(t => (nowMs - t.created_at) < (72 * 60 * 60 * 1000) && t.type !== 'jarvis_log' && t.status !== 'trash' && t.status !== 'vaulted_trash');
  const analyzed = ThoughtAnalyzer.analyzeBatch(recentThoughts);

  // Layer 3: Cognitive State Engine
  const { CognitiveStateEngine } = await import('../runtime/CognitiveStateEngine');
  
  let awareness = {};
  let lifeModel = {};
  try {
      const awarenessStore = await db.settings.get('jaos_awareness_state');
      awareness = awarenessStore ? awarenessStore.value : JSON.parse(localStorage.getItem('jaos_awareness_state') || '{}');
      
      const lifeModelStore = await db.settings.get('jaos_life_model');
      lifeModel = lifeModelStore ? lifeModelStore.value : JSON.parse(localStorage.getItem('jaos_life_model') || '{}');
  } catch(e) {
      awareness = JSON.parse(localStorage.getItem('jaos_awareness_state') || '{}');
      lifeModel = JSON.parse(localStorage.getItem('jaos_life_model') || '{}');
  }

  const cognitiveState = CognitiveStateEngine.construct(analyzed, awareness, lifeModel);

  // Layer 4: Environment Snapshot Builder
  const { SnapshotBuilder } = await import('../runtime/SnapshotBuilder');
  const events = allThoughts.filter(t => t.type === 'event' && t.status !== 'trash').map(t => ({
      title: t.content.replace(/\[EVENT:.*?\]/i, '').trim(),
      start: t.content.match(/\[EVENT:(.*?)\]/)?.[1]
  }));
  const snapshot = SnapshotBuilder.build(cognitiveState, events, { focus: lifeModel.focus });

  // Layer 5: AI Cognition
  const { buildSystemPrompt } = await import('../prompts/buildSystemPrompt');
  let jaosIdentity = { ai_name: 'Jarvis', user_name: 'User' };
  try {
      const idStore = await db.settings.get('jaos_identity');
      if (idStore && idStore.value) jaosIdentity = idStore.value;
  } catch(e) {}

  let reflection = null;
  try {
      const { runReflectionLoop } = await import('../reasoning/reflectionLoop');
      reflection = await runReflectionLoop({ momentum: cognitiveState.urgency_map.task_pressure });
  } catch(e) {}

  const systemPrompt = buildSystemPrompt(jaosIdentity, snapshot, reflection);

  // 3. Build Conversational History Matrix
  const rawLogs = allThoughts.filter(t => t.type === 'jarvis_log').sort((a,b) => a.created_at - b.created_at);
  const recentLogs = rawLogs.slice(-10);
  const messages = [ { role: 'system', content: systemPrompt } ];
  
  for (const log of recentLogs) {
     if (log.content.startsWith('**You:**')) {
         messages.push({ role: 'user', content: log.content.replace(/^\*\*You:\*\*\s*/i, '') });
     } else if (log.content.startsWith('**Jarvis:**') || log.content.startsWith('**Jarvis (Autonomous Query):**')) {
         messages.push({ role: 'assistant', content: log.content.replace(/^\*\*Jarvis.*?\*\*\s*/i, '') });
     }
  }
  messages.push({ role: 'user', content: query });

  // 4. Direct Chat Request
  const response = await fetch(`${baseUrl}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: detectedModel,
      messages: messages,
      stream: false,
      options: { num_predict: 150, temperature: 0.5 }
    })
  });
  
  if (!response.ok) throw new Error('Local LLM returned an error');
  const data = await response.json();
  const rawReply = data.message.content.trim();

  // Layer 6 & 7: Abstraction & Compression
  const { ResponseRefiner } = await import('../runtime/ResponseRefiner');
  const debugMode = localStorage.getItem('jaos_debug') === 'true';
  return ResponseRefiner.refine(rawReply, snapshot, debugMode);
} catch (error) {
  console.warn('[JARVIS] Hybrid Context Sync failed. Falling back to Local WASM Intelligence...');
  try {
    const { askLocalAI } = await import('./localAi');
    return await askLocalAI(query, 'You are Jarvis, operating in local fallback mode. Keep it short.');
  } catch (localErr) {
    throw new Error('JARVIS_OFFLINE');
  }
  }
}
