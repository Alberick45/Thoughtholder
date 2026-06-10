import { db } from '../../../shared/infrastructure/db';
import { encryptData, decryptData } from '../../../shared/utils/crypto';

/**
 * CredentialManager - Secure storage for service credentials.
 * Encrypts data using the primary vault password.
 */
export const credentialManager = {
  /**
   * Save a credential for a specific service.
   * @param {string} service Name of the service (e.g., 'GMAIL', 'TELEGRAM').
   * @param {object} creds Object containing credential data.
   * @param {string} vaultPassword The primary arsenal password for encryption.
   */
  async saveCredential(service, creds, vaultPassword) {
    const dataStr = JSON.stringify(creds);
    const encrypted = await encryptData(vaultPassword, dataStr);
    
    const store = await db.settings.get('credentials') || { key: 'credentials', value: {} };
    const allCreds = store.value;
    allCreds[service] = encrypted;
    
    await db.settings.put({ key: 'credentials', value: allCreds });
  },

  /**
   * Retrieve a credential for a specific service.
   * @param {string} service Name of the service.
   * @param {string} vaultPassword The primary arsenal password for decryption.
   */
  async getCredential(service, vaultPassword) {
    const store = await db.settings.get('credentials');
    if (!store || !store.value[service]) return null;
    
    const encrypted = store.value[service];
    const decrypted = await decryptData(vaultPassword, encrypted);
    return JSON.parse(decrypted);
  },

  /**
   * List all configured services (without revealing credentials).
   */
  async listServices() {
    const store = await db.settings.get('credentials');
    if (!store) return [];
    return Object.keys(store.value);
  }
};
