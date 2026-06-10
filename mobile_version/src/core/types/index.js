/**
 * @typedef {Object} Thought
 * @property {string} id - UUID
 * @property {string} thought_id - Human readable ID
 * @property {string} content - Main text
 * @property {'thought'|'idea'|'task'|'note'|'suggestion'|'event'|'jarvis_log'} type
 * @property {'fresh'|'active'|'ignored'|'archived'|'trash'|'vaulted'|'vaulted_trash'} status
 * @property {string[]} tags
 * @property {number} created_at - Timestamp
 * @property {number} last_viewed_at - Timestamp
 * @property {number} stale_score
 * @property {string[]} linked_thoughts - Array of UUIDs
 */

export const EMPTY_THOUGHT = {
  content: '',
  type: 'thought',
  status: 'fresh',
  tags: [],
  linked_thoughts: []
};
