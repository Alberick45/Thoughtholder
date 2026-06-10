import React, { useState, useEffect } from 'react';
import { useRegisterSW } from 'virtual:pwa-register/react';

export default function PwaAlerts() {
  const {
    offlineReady: [offlineReady, setOfflineReady],
    needRefresh: [needRefresh, setNeedRefresh],
    updateServiceWorker,
  } = useRegisterSW({
    onRegistered(r) {
      console.log('SW Registered: ' + r);
    },
    onRegisterError(error) {
      console.log('SW registration error', error);
    },
  });

  const [installPrompt, setInstallPrompt] = useState(null);
  const [showInstallBanner, setShowInstallBanner] = useState(false);

  useEffect(() => {
    const handleBeforeInstallPrompt = (e) => {
      e.preventDefault();
      setInstallPrompt(e);
      // Don't show if they've dismissed it recently
      if (localStorage.getItem('jaos_pwa_dismissed') !== 'true') {
        setShowInstallBanner(true);
      }
    };
    window.addEventListener('beforeinstallprompt', handleBeforeInstallPrompt);
    return () => window.removeEventListener('beforeinstallprompt', handleBeforeInstallPrompt);
  }, []);

  const handleInstallClick = async () => {
    if (!installPrompt) return;
    installPrompt.prompt();
    const { outcome } = await installPrompt.userChoice;
    if (outcome === 'accepted') {
      setShowInstallBanner(false);
    }
    setInstallPrompt(null);
  };

  const dismissInstall = () => {
    setShowInstallBanner(false);
    localStorage.setItem('jaos_pwa_dismissed', 'true');
  };

  const closeSwBanner = () => {
    setOfflineReady(false);
    setNeedRefresh(false);
  };

  if (!offlineReady && !needRefresh && !showInstallBanner) return null;

  return (
    <div style={{
      position: 'fixed',
      bottom: '100px', // Above bottom input bar on mobile
      left: '50%',
      transform: 'translateX(-50%)',
      zIndex: 9999,
      display: 'flex',
      flexDirection: 'column',
      gap: '0.5rem',
      width: '90%',
      maxWidth: '400px'
    }}>
      {(offlineReady || needRefresh) && (
        <div className="glass-panel" style={{
          padding: '1rem',
          border: '1px solid var(--accent-blue)',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          boxShadow: '0 4px 20px rgba(0,0,0,0.5)',
          borderRadius: '8px'
        }}>
          <div>
            {offlineReady
              ? <span style={{ color: 'white', fontSize: '0.9rem' }}>App ready to work offline</span>
              : <span style={{ color: 'white', fontSize: '0.9rem' }}>New content available, click on reload button to update.</span>}
          </div>
          <div style={{ display: 'flex', gap: '0.5rem' }}>
            {needRefresh && <button onClick={() => updateServiceWorker(true)} style={{ background: 'var(--accent-blue)', color: 'white', border: 'none', padding: '0.4rem 0.8rem', borderRadius: '4px', cursor: 'pointer', fontSize: '0.8rem' }}>Reload</button>}
            <button onClick={closeSwBanner} style={{ background: 'transparent', border: '1px solid #555', color: 'white', padding: '0.4rem 0.8rem', borderRadius: '4px', cursor: 'pointer', fontSize: '0.8rem' }}>Close</button>
          </div>
        </div>
      )}

      {showInstallBanner && (
        <div className="glass-panel" style={{
          padding: '1rem',
          border: '1px solid var(--neon-purple)',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          boxShadow: '0 4px 20px rgba(0,0,0,0.5)',
          borderRadius: '8px'
        }}>
          <span style={{ color: 'white', fontSize: '0.9rem' }}>Install ThoughtHolder for a better experience</span>
          <div style={{ display: 'flex', gap: '0.5rem' }}>
            <button onClick={handleInstallClick} style={{ background: 'var(--neon-purple)', color: 'white', border: 'none', padding: '0.4rem 0.8rem', borderRadius: '4px', cursor: 'pointer', fontSize: '0.8rem' }}>Install</button>
            <button onClick={dismissInstall} style={{ background: 'transparent', border: '1px solid #555', color: 'white', padding: '0.4rem 0.8rem', borderRadius: '4px', cursor: 'pointer', fontSize: '0.8rem' }}>Close</button>
          </div>
        </div>
      )}
    </div>
  );
}
