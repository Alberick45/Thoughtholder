// Web Crypto API utility for AES-GCM encryption

// Helper: Convert string to ArrayBuffer
const str2ab = (str) => new TextEncoder().encode(str);
// Helper: Convert ArrayBuffer to Hex String
const ab2hex = (ab) => Array.from(new Uint8Array(ab)).map(b => b.toString(16).padStart(2, '0')).join('');
// Helper: Convert Hex String to ArrayBuffer
const hex2ab = (hex) => new Uint8Array(hex.match(/.{1,2}/g).map(byte => parseInt(byte, 16))).buffer;

const deriveKey = async (password, salt) => {
  const keyMaterial = await window.crypto.subtle.importKey(
    'raw', str2ab(password), { name: 'PBKDF2' }, false, ['deriveBits', 'deriveKey']
  );
  return window.crypto.subtle.deriveKey(
    { name: 'PBKDF2', salt: salt, iterations: 100000, hash: 'SHA-256' },
    keyMaterial,
    { name: 'AES-GCM', length: 256 },
    true,
    ['encrypt', 'decrypt']
  );
};

export const encryptData = async (password, plainText) => {
  const salt = window.crypto.getRandomValues(new Uint8Array(16));
  const iv = window.crypto.getRandomValues(new Uint8Array(12));
  const key = await deriveKey(password, salt);
  
  const encrypted = await window.crypto.subtle.encrypt(
    { name: 'AES-GCM', iv: iv },
    key,
    str2ab(plainText)
  );

  return JSON.stringify({
    cipher: ab2hex(encrypted),
    iv: ab2hex(iv),
    salt: ab2hex(salt)
  });
};

export const decryptData = async (password, encryptedJson) => {
  try {
    const { cipher, iv, salt } = JSON.parse(encryptedJson);
    const key = await deriveKey(password, hex2ab(salt));
    const decrypted = await window.crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: new Uint8Array(hex2ab(iv)) },
      key,
      hex2ab(cipher)
    );
    return new TextDecoder().decode(decrypted);
  } catch (error) {
    throw new Error('Decryption failed: Invalid password or corrupted data');
  }
};
