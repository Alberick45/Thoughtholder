import Dexie from 'dexie';
import { DB_CONFIG } from '../../core/config/constants';
import { normalizeThought, safeStringify, sanitizeObject } from '../utils/normalization';

export const db = new Dexie(DB_CONFIG.NAME);

export const getDeviceId = () => {
  let devId = localStorage.getItem('th_device_id');
  if (!devId) {
    const adjs = ['Phantom', 'Ghost', 'Spectre', 'Shadow', 'Cipher', 'Void'];
    const nouns = ['Node', 'Rig', 'Terminal', 'Core', 'Link', 'Key'];
    devId = `${adjs[Math.floor(Math.random() * adjs.length)]}-${nouns[Math.floor(Math.random() * nouns.length)]}-${Math.floor(100 + Math.random() * 900)}`;
    localStorage.setItem('th_device_id', devId);
  }
  return devId;
};

export const generateUUID = () => {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID();
  return Math.random().toString(36).substring(2, 15) + Math.random().toString(36).substring(2, 15);
};

// Version 5 is the current operational schema
db.version(DB_CONFIG.VERSION).stores({
  thoughts: 'id, thought_id, type, key, status, created_at, last_viewed_at, stale_score, parent_project, dependency_id',
  settings: 'key, value',
  documents: 'id, title, type, author, date'
});

// Explicitly handle opening to catch "Internal Error" or "DatabaseClosedError"
async function initDB() {
  try {
    await db.open();
    console.log("[DB] Database opened successfully.");
  } catch (err) {
    console.error("[DB] Critical error opening database:", err);
  }
}
initDB();

db.on('blocked', () => {
  console.warn("[DB] Database is blocked by another tab or window. Please close other instances.");
});

/**
 * Robust "Nuclear" reset to fix 'Internal Error' / corruption
 */
export async function nuclearReset() {
  try {
    console.log("[DB] Starting Nuclear Reset...");
    if (db.isOpen()) db.close();
    await Dexie.delete('ThoughtHolderDB');
    Object.keys(localStorage).forEach(key => {
        if (key.startsWith('jaos_')) {
            localStorage.removeItem(key);
        }
    });
    window.location.reload();
  } catch (err) {
    console.error("[DB] Nuclear Reset failed.", err);
    alert("CRITICAL: Failed to wipe database.");
  }
}

/**
 * Log storage quota for diagnostics
 */
export async function logStorageQuota() {
  if (navigator.storage && navigator.storage.estimate) {
    const estimate = await navigator.storage.estimate();
    console.log(`[STORAGE] Usage: ${(estimate.usage / 1024 / 1024).toFixed(2)} MB`);
    console.log(`[STORAGE] Quota: ${(estimate.quota / 1024 / 1024).toFixed(2)} MB`);
  }
}
logStorageQuota();

export let hiveSocket = null;

export async function intelligentMerge(importedData) {
  if (!Array.isArray(importedData)) return;
  const localArr = await db.thoughts.toArray();
  const localDataMap = new Map(localArr.map(t => [t.id, t]));

  const toUpdate = [];
  for (const item of importedData) {
    if (!item.id) continue;
    const normalized = normalizeThought(item);
    if (localDataMap.has(normalized.id)) {
      const local = localDataMap.get(normalized.id);
      const localTime = Math.max(local.updated_at || 0, local.last_viewed_at || 0, local.created_at || 0);
      const remoteTime = Math.max(normalized.updated_at || 0, normalized.last_viewed_at || 0, normalized.created_at || 0);
      if (remoteTime > localTime) toUpdate.push(normalized);
    } else {
      toUpdate.push(normalized);
    }
  }

  if (toUpdate.length > 0) {
    await db.thoughts.bulkPut(toUpdate);
    console.log(`[DB] Merged ${toUpdate.length} nodes into local state.`);
  }
  return toUpdate.length;
}

export function connectHive(targetHost = null) {
  if (hiveSocket) return;
  const host = targetHost || window.location.hostname || 'localhost';
  try {
    hiveSocket = new WebSocket(`ws://${host}:8080`);
    hiveSocket.onopen = () => console.log(`[HIVE SYNC] Local Relay connected to ${host}`);
    hiveSocket.onerror = () => { hiveSocket = null; };
    hiveSocket.onclose = () => { hiveSocket = null; };
    hiveSocket.onmessage = async (e) => {
      try {
        const msg = JSON.parse(e.data);
        if (msg.action === 'SYNC_THOUGHT') {
          await intelligentMerge([msg.data]);
        }
      } catch (err) { console.error('[HIVE SYNC] Incoming Error:', err); }
    };
  } catch (e) { hiveSocket = null; }
}

export async function addThought(thought) {
  try {
    if (!db.isOpen()) await db.open();
    const cleaned = normalizeThought(thought);
    const res = await db.thoughts.add(cleaned);

    if (cleaned.type !== 'jarvis_log' && cleaned.type !== 'event') {
      setTimeout(async () => {
        try {
          const { generateEmbedding } = await import('../../features/intelligence/services/embeddings.js');
          const vector = await generateEmbedding(cleaned.content);
          if (vector) await db.thoughts.update(cleaned.id, { embedding: vector });
        } catch (e) { console.warn('[DB] Embedding failed:', e); }
      }, 100);
    }

    if (hiveSocket?.readyState === WebSocket.OPEN) {
      hiveSocket.send(JSON.stringify({ action: 'SYNC_THOUGHT', data: cleaned }));
    }
    return res;
  } catch (err) {
    console.error('[DB] addThought failed:', err);
    throw err;
  }
}

export async function updateThought(id, changes) {
  const sanitizedChanges = sanitizeObject(changes);
  const res = await db.thoughts.update(id, sanitizedChanges);
  const fresh = await db.thoughts.get(id);
  if (fresh && hiveSocket?.readyState === WebSocket.OPEN) {
    hiveSocket.send(JSON.stringify({ action: 'SYNC_THOUGHT', data: fresh }));
  }
  return res;
}

export const deleteThought = (id) => db.thoughts.delete(id);
export const getThoughts = () => db.thoughts.orderBy('created_at').reverse().toArray();

// Automatically recalculate states sequentially to avoid hangs
export async function refreshAttentionStates() {
  const thoughts = await db.thoughts.toArray();
  const now = Date.now();
  const ONE_DAY = 24 * 60 * 60 * 1000;

  for (const t of thoughts) {
    let newStatus = t.status;
    let newScore = t.stale_score;

    if (t.status !== 'archived' && t.status !== 'vaulted' && t.status !== 'trash' && t.status !== 'vaulted_trash') {
      const msSinceCreation = now - t.created_at;
      const msSinceViewed = now - t.last_viewed_at;

      if (msSinceViewed > ONE_DAY && t.last_viewed_at === t.created_at) {
        newStatus = 'ignored';
        newScore = Math.floor(msSinceCreation / ONE_DAY);
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

    if (newStatus !== t.status || newScore !== t.stale_score) {
      await db.thoughts.update(t.id, { status: newStatus, stale_score: newScore });
    }
  }
}

export async function migrateLegacyLinks() {
  if (!db.isOpen()) await db.open();
  const thoughts = await db.thoughts.toArray();

  for (const t of thoughts) {
    if (t.linked_thoughts && t.linked_thoughts.length > 0) {
      let changed = false;
      const newLinks = t.linked_thoughts.map(link => {
        if (link.length < 30) {
          const target = thoughts.find(targetNode => targetNode.thought_id === link);
          if (target) {
            changed = true;
            return target.id;
          }
        }
        return link;
      });
      if (changed) await db.thoughts.update(t.id, { linked_thoughts: newLinks });
    }
  }
}

// Deferred background tasks
setTimeout(() => {
  if (db.isOpen()) {
    // connectHive();
    migrateLegacyLinks().catch(err => console.error("[DB] Background migration error:", err));
  }
}, 5000);

// Vault Recovery Codeword Helpers
export async function hashCodeword(word) {
  const encoder = new TextEncoder();
  const data = encoder.encode(word.trim().toLowerCase());
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(hashBuffer)).map(b => b.toString(16).padStart(2, '0')).join('');
}

export async function saveRecoveryCodeHash(hash) {
  await db.settings.put({ key: 'recoveryCodeHash', value: hash });
}

export async function verifyRecoveryCode(word) {
  const stored = await db.settings.get('recoveryCodeHash');
  if (!stored) return false;
  const attempt = await hashCodeword(word);
  return attempt === stored.value;
}

export async function hasRecoveryCode() {
  const stored = await db.settings.get('recoveryCodeHash');
  return !!stored;
}

if (typeof window !== 'undefined') {
  window.db = db;
  window.nuclearReset = nuclearReset;
  window.db.nuclearReset = nuclearReset;
  window.addThought = addThought;
}
