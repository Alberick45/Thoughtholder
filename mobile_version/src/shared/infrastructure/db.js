import Dexie from 'dexie';

export const generateUUID = () => {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID();
  return Math.random().toString(36).substring(2, 15) + Math.random().toString(36).substring(2, 15);
};

export const db = new Dexie('ThoughtHolderDB');

export const getDeviceId = () => {
  let devId = localStorage.getItem('th_device_id');
  if (!devId) {
      const adjs = ['Phantom', 'Ghost', 'Spectre', 'Shadow', 'Cipher', 'Void'];
      const nouns = ['Node', 'Rig', 'Terminal', 'Core', 'Link', 'Key'];
      devId = `${adjs[Math.floor(Math.random()*adjs.length)]}-${nouns[Math.floor(Math.random()*nouns.length)]}-${Math.floor(100+Math.random()*900)}`;
      localStorage.setItem('th_device_id', devId);
  }
  return devId;
};

db.version(6).stores({
  thoughts: 'id, thought_id, type, key, status, created_at, last_viewed_at, stale_score',
  settings: 'key, value',
  documents: 'id, title, type, author, date'
});

// A thought structure:
// {
//    id: string (uuid),
//    thought_id: string (e.g. Drone-Idea-482),
//    content: string,
//    type: 'idea' | 'task' | 'note' | 'thought',
//    status: 'fresh' | 'ignored' | 'active' | 'archived',
//    tags: string[],
//    summary: string,
//    created_at: number (timestamp),
//    last_viewed_at: number (timestamp),
//    stale_score: number,
//    linked_thoughts: string[]
// }

export let hiveSocket = null;

export async function intelligentMerge(importedData) {
  const localDataMap = new Map();
  const localArr = await db.thoughts.toArray();
  localArr.forEach(t => localDataMap.set(t.id, t));

  const resolved = [];
  for (const item of importedData) {
    if (localDataMap.has(item.id)) {
      const local = localDataMap.get(item.id);
      const localTime = local.updated_at || local.last_viewed_at || local.created_at || 0;
      const remoteTime = item.updated_at || item.last_viewed_at || item.created_at || 0;
      if (remoteTime > localTime) {
        resolved.push(item);
      } else {
        resolved.push(local);
      }
    } else {
      resolved.push(item);
    }
  }
  if (resolved.length > 0) {
    await db.thoughts.bulkPut(resolved);
  }
}

export function connectHive(targetHost = null) {
  if (hiveSocket) return;
  const host = targetHost || window.location.hostname || 'localhost';
  hiveSocket = new WebSocket(`ws://${host}:8080`);
  
  hiveSocket.onopen = () => console.log(`[HIVE SYNC] Local Relay connected to ${host}`);
  
  hiveSocket.onmessage = async (e) => {
    try {
      const msg = JSON.parse(e.data);
      if (msg.action === 'SYNC_THOUGHT') {
        const payload = msg.data;
        await intelligentMerge([payload]);
      } else if (msg.action === 'SYNC_ENCRYPTED_BULK') {
        // Dispatch to UI for decryption prompt
        window.dispatchEvent(new CustomEvent('hiveEncryptedBulk', { detail: msg.data }));
      }
    } catch (err) {
      console.error('[HIVE SYNC] Incoming Error:', err);
    }
  };
}

// Auto-connect on load
connectHive();

export async function addThought(thought) {
  if (!thought.id) thought.id = generateUUID();
  const res = await db.thoughts.add(thought);
  
  import('../../features/intelligence/services/embeddings.js').then((mod) => {
     const generateEmbedding = mod.generateEmbedding || mod.default?.generateEmbedding || mod.default || (typeof mod === 'function' ? mod : null);
     if (typeof generateEmbedding === 'function') {
        generateEmbedding(thought.content).then(vector => {
           if (vector) db.thoughts.update(thought.id, { embedding: vector });
        }).catch(err => console.warn("[DB] Embedding generation failed:", err));
     } else {
        console.warn("[DB] generateEmbedding function not found in module.");
     }
  }).catch(err => console.warn("[DB] Embeddings module load failed:", err));

  if (hiveSocket && hiveSocket.readyState === WebSocket.OPEN) {
    hiveSocket.send(JSON.stringify({ action: 'SYNC_THOUGHT', data: thought }));
  }
  return res;
}

export async function updateThought(id, changes) {
  const res = await db.thoughts.update(id, changes);
  const fresh = await db.thoughts.get(id);
  if (fresh && hiveSocket && hiveSocket.readyState === WebSocket.OPEN) {
    hiveSocket.send(JSON.stringify({ action: 'SYNC_THOUGHT', data: fresh }));
  }
  return res;
}

export async function deleteThought(id) {
  return await db.thoughts.delete(id);
}

export async function getThoughts() {
  return await db.thoughts.orderBy('created_at').reverse().toArray();
}

// Automatically recalculate states based on Attention Engine rules
export async function refreshAttentionStates() {
  const thoughts = await db.thoughts.toArray();
  const now = Date.now();
  const ONE_DAY = 24 * 60 * 60 * 1000;
  
  thoughts.forEach(async (t) => {
    let newStatus = t.status;
    let newScore = t.stale_score;
    
    // If not archived, vaulted, or trash explicitly..
    if (t.status !== 'archived' && t.status !== 'vaulted' && t.status !== 'trash' && t.status !== 'vaulted_trash') {
      const msSinceCreation = now - t.created_at;
      const msSinceViewed = now - t.last_viewed_at;
      
      if (msSinceViewed > ONE_DAY && t.last_viewed_at === t.created_at) {
        newStatus = 'ignored';
        newScore = Math.floor(msSinceCreation / ONE_DAY); // +1 stale score per day
      } else if (msSinceViewed < ONE_DAY && t.last_viewed_at > t.created_at) {
        newStatus = 'active';
        newScore = 0;
      } else if (msSinceCreation < ONE_DAY) {
        newStatus = 'fresh';
        newScore = 0;
      } else {
        newScore = Math.floor(msSinceViewed / ONE_DAY);
      }
    }
    
    // Update if changed
    if (newStatus !== t.status || newScore !== t.stale_score) {
      await db.thoughts.update(t.id, { status: newStatus, stale_score: newScore });
    }
  });
}

// Ensure old text-links are converted to immutable UUIDs
export async function migrateLegacyLinks() {
  try {
    const thoughts = await db.thoughts.toArray();
    
    thoughts.forEach(async (t) => {
      if (t.linked_thoughts && t.linked_thoughts.length > 0) {
        let changed = false;
        const newLinks = t.linked_thoughts.map(link => {
          // If it's not a UUID (i.e. contains no dashes or is just a shorter text like "Thought-Idea-123")
          if (link.length < 30) {
            const target = thoughts.find(targetNode => targetNode.thought_id === link);
            if (target) {
              changed = true;
              return target.id;
            }
          }
          return link; // Already UUID or dead link
        });
        
        if (changed) {
          await db.thoughts.update(t.id, { linked_thoughts: newLinks });
        }
      }
    });
  } catch (err) {
    console.error("[DB] Migration Error:", err);
  }
}

// Fire migration silently
migrateLegacyLinks();
