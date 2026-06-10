import { useEffect } from 'react';
import { encryptData } from '../../shared/utils/crypto';

export function useAutoBackup(db) {
  useEffect(() => {
    const backupRoutine = async () => {
      const now = new Date();
      // Runs at 8 PM (20:00)
      if (now.getHours() === 20) { 
        const lastBackupDate = localStorage.getItem('last_auto_backup');
        const today = now.toISOString().split('T')[0];
        if (lastBackupDate !== today) {
          try {
            const allData = await db.thoughts.toArray();
            const dataStr = JSON.stringify(allData, null, 2);
            let payload = dataStr;
            
            // Attempt to encrypt with base Arsenal password if available
            const store = await db.settings.get('hydraConfigs');
            const configs = store ? store.value : {};
            const baseConfig = configs['']; 
            if (baseConfig && baseConfig.type === 'password' && baseConfig.password) {
               payload = await encryptData(baseConfig.password, dataStr);
               console.log("encrypting auto-backup with vault phase...");
            }
            
            if (window.electronAPI && window.electronAPI.saveBackup) {
               await window.electronAPI.saveBackup(payload);
               localStorage.setItem('last_auto_backup', today);
               console.log('[AUTO-BACKUP] Payload secured to OS.');
            }
          } catch (e) { console.error('Auto backup failed', e); }
        }
      }
    };
    const timer = setInterval(backupRoutine, 60 * 1000); // Check every minute
    return () => clearInterval(timer);
  }, [db]);
}
