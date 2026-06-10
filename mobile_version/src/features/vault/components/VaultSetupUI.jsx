import React from 'react';

export default function VaultSetupUI({
  showVaultSetup, setShowVaultSetup,
  isReconfiguringMode, setIsReconfiguringMode,
  vaultType, setVaultType,
  vaultPassword, setVaultPassword,
  pictureFiles, setPictureFiles,
  pictureSequence, setPictureSequence,
  decryptSequence, setDecryptSequence,
  hasConfig, setHasConfig,
  activeTargetLayer,
  setAppLevel,
  db,
  jarvisOfflineAlert,
  setJarvisOfflineAlert
}) {
  if (!showVaultSetup) return null;

  const handleVerify = async () => {
    const store = await db.settings.get('hydraConfigs');
    const configs = store ? store.value : {};
    const config = configs[activeTargetLayer];
    
    let isAuthorized = false;
    if (config && config.type === 'picture') {
       if (JSON.stringify(config.sequence) === JSON.stringify(decryptSequence)) isAuthorized = true;
    } else if (config && config.password === vaultPassword) {
       isAuthorized = true;
    }

    if (isAuthorized) {
      if (isReconfiguringMode) {
        setHasConfig(false);
        setIsReconfiguringMode(false);
        setVaultPassword('');
        setPictureFiles([]);
        setPictureSequence([]);
        setDecryptSequence([]);
      } else {
        setAppLevel(4);
        setShowVaultSetup(false);
        setVaultPassword('');
        setDecryptSequence([]);
      }
    } else {
      alert(isReconfiguringMode ? 'Verification Failed.' : 'CRITICAL: Sequence Invalid. Attempt logged.');
      setDecryptSequence([]);
    }
  };

  const handleEncryptAndLock = async () => {
    const store = await db.settings.get('hydraConfigs');
    const configs = store ? store.value : {};
    configs[activeTargetLayer] = { type: vaultType, password: vaultPassword, images: pictureFiles, sequence: pictureSequence };
    await db.settings.put({ key: 'hydraConfigs', value: configs });
    
    setAppLevel(4);
    setShowVaultSetup(false);
  };

  return (
    <div className="app-container" style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', background: 'var(--bg-primary)' }}>
      {jarvisOfflineAlert && (
        <div className="animate-slide-up" style={{ position: 'fixed', top: '1rem', left: '50%', transform: 'translateX(-50%)', background: 'rgba(239, 68, 68, 0.1)', border: '1px solid #ef4444', color: '#f87171', padding: '0.8rem 1.5rem', borderRadius: '8px', zIndex: 100, backdropFilter: 'blur(10px)', display: 'flex', alignItems: 'center', gap: '1rem', fontSize: '0.9rem', boxShadow: '0 4px 12px rgba(0,0,0,0.5)' }}>
          <span><strong>Jarvis is Offline.</strong> Ollama daemon is not running on port 11434.</span>
          <button style={{ background: '#ef4444', color: 'white', border: 'none', padding: '0.3rem 0.8rem', borderRadius: '4px', cursor: 'pointer' }} onClick={() => { localStorage.setItem('dismiss_jarvis_alert', 'true'); setJarvisOfflineAlert(false); }}>Dismiss</button>
        </div>
      )}
      <main style={{ flex: 1, padding: '2rem', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'flex-start', overflowY: 'auto' }}>
        
        {isReconfiguringMode ? (
          <>
            <h2 style={{ color: 'var(--neon-purple)', fontSize: '2.5rem', marginBottom: '1rem' }}>Reconfigure Security</h2>
            <p style={{ color: 'var(--text-muted)', marginBottom: '2rem' }}>Authenticate past sequence to alter Deep Guard lock.</p>
            
            {vaultType === 'password' && (
              <input type="password" value={vaultPassword} onChange={e => setVaultPassword(e.target.value)} placeholder="Verify sequence..." style={{ background: 'black', border: '1px solid var(--neon-purple)', maxWidth: '300px', marginBottom: '2rem', textAlign: 'center' }} />
            )}
            {vaultType === 'pin' && (
              <input type="password" value={vaultPassword} onChange={e => setVaultPassword(e.target.value)} placeholder="* * * *" style={{ background: 'black', border: '1px solid var(--neon-purple)', maxWidth: '300px', marginBottom: '2rem', textAlign: 'center', letterSpacing: '8px' }} />
            )}
            {vaultType === 'picture' && (
              <div style={{ marginBottom: '2rem', textAlign: 'center' }}>
                 <p style={{ color: 'var(--text-muted)', marginBottom: '1rem' }}>Select matching sequence ({decryptSequence.length} clicks)</p>
                 <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(100px, 1fr))', gap: '0.5rem', maxWidth: '500px' }}>
                    {pictureFiles.map((file, i) => (
                      <img 
                        key={i} 
                        src={URL.createObjectURL(file)} 
                        onClick={() => setDecryptSequence(prev => [...prev, i])}
                        style={{ width: '100px', height: '100px', objectFit: 'cover', borderRadius: '8px', cursor: 'pointer', border: decryptSequence.includes(i) ? '3px solid var(--neon-purple)' : '2px solid #333' }} 
                      />
                    ))}
                 </div>
                 <button onClick={() => setDecryptSequence([])} style={{ marginTop: '1rem', background: 'transparent', color: '#ef4444', border: '1px solid #ef4444', padding: '0.5rem' }}>Clear Inputs</button>
              </div>
            )}
            
            <div style={{ display: 'flex', gap: '1rem' }}>
              <button style={{ background: 'var(--neon-purple)', color: 'white', fontWeight: 'bold', padding: '1rem 3rem', fontSize: '1.2rem', borderRadius: '8px', border: 'none', cursor: 'pointer' }} onClick={handleVerify}>Verify</button>
              <button style={{ background: 'transparent', color: 'var(--text-muted)', border: '1px solid var(--border-subtle)', padding: '1rem', borderRadius: '8px', cursor: 'pointer' }} onClick={async () => { 
                setIsReconfiguringMode(false); 
                setShowVaultSetup(false); 
                const store = await db.settings.get('hydraConfigs');
                const configs = store ? store.value : {};
                if (configs[activeTargetLayer]) setHasConfig(true); 
              }}>Abort</button>
            </div>
          </>
        ) : hasConfig ? (
          <>
            <h2 style={{ color: 'var(--neon-purple)', fontSize: '2.5rem', marginBottom: '1rem' }}>Deep Guard Initiated</h2>
            <p style={{ color: 'var(--text-muted)', marginBottom: '2rem' }}>Level 3 Sequence Prompt. Target confirmed.</p>
            
            {vaultType === 'password' && (
              <input type="password" value={vaultPassword} onChange={e => setVaultPassword(e.target.value)} placeholder="Enter sequence..." style={{ background: 'black', border: '1px solid var(--neon-purple)', maxWidth: '300px', marginBottom: '2rem', textAlign: 'center' }} />
            )}
            {vaultType === 'pin' && (
              <input type="password" value={vaultPassword} onChange={e => setVaultPassword(e.target.value)} placeholder="* * * *" style={{ background: 'black', border: '1px solid var(--neon-purple)', maxWidth: '300px', marginBottom: '2rem', textAlign: 'center', letterSpacing: '8px' }} />
            )}
            {vaultType === 'picture' && (
              <div style={{ marginBottom: '2rem', textAlign: 'center' }}>
                 <p style={{ color: 'var(--text-muted)', marginBottom: '1rem' }}>Select matching sequence ({decryptSequence.length} clicks)</p>
                 <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(100px, 1fr))', gap: '0.5rem', maxWidth: '500px' }}>
                    {pictureFiles.map((file, i) => (
                      <img 
                        key={i} 
                        src={URL.createObjectURL(file)} 
                        onClick={() => setDecryptSequence(prev => [...prev, i])}
                        style={{ width: '100px', height: '100px', objectFit: 'cover', borderRadius: '8px', cursor: 'pointer', border: decryptSequence.includes(i) ? '3px solid var(--neon-purple)' : '2px solid #333' }} 
                      />
                    ))}
                 </div>
                 <button onClick={() => setDecryptSequence([])} style={{ marginTop: '1rem', background: 'transparent', color: '#ef4444', border: '1px solid #ef4444', padding: '0.5rem' }}>Clear Inputs</button>
              </div>
            )}
            
            <div style={{ display: 'flex', gap: '1rem' }}>
              <button style={{ background: 'var(--neon-purple)', color: 'white', fontWeight: 'bold', padding: '1rem 3rem', fontSize: '1.2rem', borderRadius: '8px', border: 'none', cursor: 'pointer' }} onClick={handleVerify}>Decrypt Payload</button>
              <button style={{ background: 'transparent', color: 'var(--text-muted)', border: '1px solid var(--border-subtle)', padding: '1rem', borderRadius: '8px', cursor: 'pointer' }} onClick={() => { setShowVaultSetup(false); setAppLevel(1); }}>Abort</button>
            </div>
          </>
        ) : (
          <>
            <h2 style={{ color: 'var(--neon-purple)', fontSize: '2.5rem', marginBottom: '1rem' }}>Arsenal Configuration</h2>
            <p style={{ color: 'var(--text-muted)', marginBottom: '2rem', textAlign: 'center', maxWidth: '600px', fontSize: '1.1rem' }}>
              Level 1 & 2 bypassed. <br/> 
              Configure Level 4 Deep Guard. This lock restricts the Arsenal.
            </p>
            
            <div style={{ display: 'flex', gap: '2rem', marginBottom: '2rem', flexWrap: 'wrap', justifyContent: 'center' }}>
              <div onClick={() => setVaultType('password')} className="glass-panel" style={{ padding: '2rem', width: '250px', display: 'flex', flexDirection: 'column', gap: '1rem', cursor: 'pointer', border: vaultType === 'password' ? '2px solid var(--neon-purple)' : '1px solid transparent', background: vaultType === 'password' ? 'rgba(139, 92, 246, 0.1)' : 'rgba(20,20,22,0.6)' }}>
                <h3>Text Password</h3>
                <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>Standard passphrase.</p>
              </div>
              
              <div onClick={() => setVaultType('pin')} className="glass-panel" style={{ padding: '2rem', width: '250px', display: 'flex', flexDirection: 'column', gap: '1rem', cursor: 'pointer', border: vaultType === 'pin' ? '2px solid var(--neon-purple)' : '1px solid transparent', background: vaultType === 'pin' ? 'rgba(139, 92, 246, 0.1)' : 'rgba(20,20,22,0.6)' }}>
                <h3>Numeric PIN</h3>
                <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>4 to 8 digit combination.</p>
              </div>
              
              <div onClick={() => setVaultType('picture')} className="glass-panel" style={{ padding: '2rem', width: '250px', display: 'flex', flexDirection: 'column', gap: '1rem', cursor: 'pointer', border: vaultType === 'picture' ? '2px solid var(--neon-purple)' : '1px solid transparent', background: vaultType === 'picture' ? 'rgba(139, 92, 246, 0.1)' : 'rgba(20,20,22,0.6)' }}>
                <h3>Picture Sequence</h3>
                <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>Upload decoys and select a hidden numerical pattern to unlock.</p>
              </div>
            </div>

            <div style={{ marginBottom: '2rem', textAlign: 'center' }}>
              <p style={{ marginBottom: '0.5rem', color: 'var(--text-muted)' }}>Set Sequence for {vaultType.toUpperCase()}:</p>
              {vaultType === 'password' && <input type="password" value={vaultPassword} onChange={e => setVaultPassword(e.target.value)} placeholder="Enter secure phrase..." style={{ background: 'black', border: '1px solid var(--text-muted)' }} />}
              {vaultType === 'pin' && <input type="password" value={vaultPassword} onChange={e => setVaultPassword(e.target.value)} placeholder="e.g. 1 3 3 7 9" style={{ background: 'black', border: '1px solid var(--text-muted)', textAlign: 'center', letterSpacing: '4px' }} />}
              {vaultType === 'picture' && (
                <div style={{ padding: '1rem', border: '1px dashed #666', background: 'rgba(255,255,255,0.05)' }}>
                  <input type="file" multiple accept="image/*" onChange={(e) => setPictureFiles(Array.from(e.target.files))} style={{ color: 'var(--text-muted)', marginBottom: '1rem' }} />
                  <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>Upload decoys, then click them below to set sequence.</p>
                  
                  {pictureFiles.length > 0 && (
                    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(100px, 1fr))', gap: '0.5rem', marginTop: '1rem', maxWidth: '500px' }}>
                      {pictureFiles.map((file, i) => (
                        <div key={i} onClick={() => setPictureSequence(prev => prev.includes(i) ? prev : [...prev, i])} style={{ position: 'relative', cursor: 'pointer' }}>
                          <img src={URL.createObjectURL(file)} style={{ width: '100px', height: '100px', objectFit: 'cover', borderRadius: '8px', border: pictureSequence.includes(i) ? '3px solid var(--neon-purple)' : '2px solid #333' }} />
                          {pictureSequence.includes(i) && <div style={{ position: 'absolute', top: 0, left: 0, background: 'var(--neon-purple)', color: 'white', width: '20px', height: '20px', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '0.8rem', fontWeight: 'bold' }}>{pictureSequence.indexOf(i) + 1}</div>}
                        </div>
                      ))}
                    </div>
                  )}
                  {pictureSequence.length > 0 && <button onClick={() => setPictureSequence([])} style={{ marginTop: '1rem', background: 'transparent', color: 'var(--text-muted)', border: '1px solid #666', padding: '0.3rem 0.6rem' }}>Reset Sequence</button>}
                </div>
              )}
            </div>

            <button style={{ background: 'var(--neon-purple)', color: 'white', fontWeight: 'bold', padding: '1rem 3rem', fontSize: '1.2rem', borderRadius: '8px', border: 'none', cursor: 'pointer', boxShadow: '0 0 20px rgba(139, 92, 246, 0.4)' }} onClick={handleEncryptAndLock}>Encrypt & Lock Arsenal</button>
          </>
        )}
      </main>
    </div>
  );
}
