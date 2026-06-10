/**
 * JAOS Global Normalization Utility
 * Ensures deterministic data structures across all layers.
 */

export const THOUGHT_SCHEMA = {
  id: 'string',
  content: 'string',
  type: 'string',
  status: 'string',
  tags: 'array',
  created_at: 'number',
  last_viewed_at: 'number',
  stale_score: 'number',
  linked_thoughts: 'array'
};

/**
 * Normalizes any value to a safe string representation.
 * Prevents [object Object] leaks.
 */
export const safeStringify = (val) => {
  if (val === null || val === undefined) return '';
  if (typeof val === 'string') return val;
  if (typeof val === 'number' || typeof val === 'boolean') return String(val);
  if (Array.isArray(val)) return val.map(item => safeStringify(item)).join(', ');
  try {
    return JSON.stringify(val);
  } catch (e) {
    return String(val);
  }
};

/**
 * Deeply sanitizes an object to ensure no nested raw objects survive.
 */
export const sanitizeObject = (obj) => {
  if (obj === null || obj === undefined) return null;
  if (typeof obj !== 'object') return obj;
  if (Array.isArray(obj)) return obj.map(item => sanitizeObject(item));
  
  const sanitized = {};
  for (const key in obj) {
    const val = obj[key];
    // Preserve arrays and binary blobs (critical for tags and picture vaults)
    if (Array.isArray(val)) {
      sanitized[key] = val.map(item => sanitizeObject(item));
    } else if (val instanceof Blob || val instanceof File) {
      sanitized[key] = val;
    } else if (typeof val === 'object' && val !== null) {
      sanitized[key] = safeStringify(val);
    } else {
      sanitized[key] = val;
    }
  }
  return sanitized;
};

/**
 * Enforces the Thought schema on an input object.
 * Also handles command extraction (e.g., /todo, /buy).
 */
export const normalizeThought = (t) => {
  if (!t) return null;
  
  let content = safeStringify(t.content || t.value || t.text || '');
  let type = String(t.type || 'thought').toLowerCase();

  // Command Extraction Logic
  if (content.startsWith('/todo ')) {
      type = 'task';
      content = content.replace('/todo ', '').trim();
  } else if (content.startsWith('/buy ')) {
      type = 'buy';
      content = content.replace('/buy ', '').trim();
  } else if (content.startsWith('/event ')) {
      type = 'event';
      content = content.replace('/event ', '').trim();
  } else if (content.startsWith('/project ')) {
      type = 'project';
      content = content.replace('/project ', '').trim();
  }

  // Self-Healing Logic for tags (handles previously stringified data)
  let tags = [];
  if (Array.isArray(t.tags)) {
    tags = t.tags.map(String);
  } else if (typeof t.tags === 'string' && t.tags.length > 0) {
    tags = t.tags.split(',').map(s => s.trim()).filter(Boolean);
  }

  // Self-Healing Logic for linked_thoughts
  let links = [];
  if (Array.isArray(t.linked_thoughts)) {
    links = t.linked_thoughts.map(String);
  } else if (typeof t.linked_thoughts === 'string' && t.linked_thoughts.length > 0) {
    links = t.linked_thoughts.split(',').map(s => s.trim()).filter(Boolean);
  }

  return {
    id: String(t.id || ''),
    content: content,
    type: type,
    status: String(t.status || 'fresh').toLowerCase(),
    tags: tags,
    created_at: Number(t.created_at || Date.now()),
    last_viewed_at: Number(t.last_viewed_at || t.created_at || Date.now()),
    stale_score: Number(t.stale_score || 0),
    linked_thoughts: links,
    attachments: t.attachments || []
  };
};

/**
 * Normalizes any value to a safe string representation.
 * Handles objects with 'val', 'value', 'title', 'name', or 'content' keys.
 */
export const normalizeValue = (value) => {
    if (value === null || value === undefined) return "";
    if (typeof value === 'string') return value;
    if (typeof value === 'number' || typeof value === 'boolean') return String(value);

    if (Array.isArray(value)) {
        return value.map(v => normalizeValue(v)).join(', ');
    }

    if (typeof value === 'object') {
        return (
            value.val ||
            value.value ||
            value.title ||
            value.name ||
            value.content ||
            safeStringify(value)
        );
    }

    return String(value);
};

/**
 * Strips runtime-only fields for export.
 */
export const prepareForExport = (data) => {
  const normalized = Array.isArray(data) ? data.map(normalizeThought) : [normalizeThought(data)];
  return normalized.map(t => {
    const { embedding, ...rest } = t; // Strip embeddings
    return rest;
  });
};
