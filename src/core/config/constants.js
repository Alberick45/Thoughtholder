/**
 * Strategist Arsenal: Universal Constants
 * System-wide configuration for AI, Network, and Security layers.
 */

export const SYSTEM_CONFIG = {
  VERSION: '4.0.0-PRO',
  CODENAME: 'STRATEGIST',
  RELEASE_DATE: '2026-05-09',
};

export const AI_CONFIG = {
  OLLAMA_BASE_URL: 'http://localhost:11434',
  DEFAULT_MODEL: 'llama3', // Fallback if dynamic detection fails
  LEASH_LEVELS: {
    MUTED: '0',
    REACTIVE: '1',
    PROACTIVE: '2'
  },
  DAEMON_CHECK_INTERVAL: 10 * 60 * 1000, // 10 minutes
  PSYCHO_ANALYSIS_INTERVAL: 24 * 60 * 60 * 1000, // 24 hours
};

export const SECURITY_CONFIG = {
  VAULT_LEVELS: {
    DECK: 1,
    WINE_CELLAR: 2,
    STRATEGIST_MAP: 3,
    ARSENAL: 4
  },
  ENCRYPTION_ALGO: 'AES-GCM',
  HASH_ALGO: 'SHA-256',
  PBKDF2_ITERATIONS: 100000,
};

export const DB_CONFIG = {
  NAME: 'ThoughtHolderDB',
  VERSION: 6,
  ATTENTION_REFRESH_INTERVAL: 60 * 60 * 1000, // 1 hour
};
