import React from 'react';
import { decryptData } from '../../shared/utils/crypto';
import { db } from '../../shared/infrastructure/db';

export default function Header({ 
  jarvisLeash, setJarvisLeash, 
  fileInputRef,
  setAppLevel,
  requestSecurePrompt,
  notify = (msg) => console.log(msg)
}) {
  return (
    <header className="global-header" style={{ padding: '1rem 2rem', display: 'flex', justifyContent: 'space-between', alignItems: 'center', background: 'rgba(15, 15, 20, 0.9)', borderBottom: '1px solid var(--border-subtle)', zIndex: 1000 }}>
      <div>
        <h1 style={{ fontWeight: '800', fontSize: '1.5rem', background: 'linear-gradient(90deg, #3b82f6, #8b5cf6)', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent', margin: '0 0 0.2rem 0' }}>
          Strategist Arsenal
        </h1>
        <p style={{ color: 'var(--text-muted)', margin: 0, fontSize: '0.75rem' }}>Classified Brain OS</p>
      </div>
      
      <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem 1rem', flexWrap: 'wrap', justifyContent: 'flex-end' }}>
        {/* Intelligence nav */}
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: '0.5rem', background: 'var(--bg-secondary)', padding: '0.4rem 0.8rem', borderRadius: '20px', fontSize: '0.8rem', border: '1px solid var(--border-focus)', cursor: 'pointer', transition: 'all 0.2s' }} onClick={() => setAppLevel(5)}>
           <span style={{ fontWeight: 'bold', color: 'var(--accent-blue)' }}>
             🦾 Intelligence
           </span>
        </div>
        
        {/* Leash toggle */}
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: '0.5rem', background: 'var(--bg-secondary)', padding: '0.4rem 0.8rem', borderRadius: '20px', fontSize: '0.8rem', border: '1px solid var(--border-focus)', cursor: 'pointer', transition: 'all 0.2s' }} onClick={() => {
           const levels = ['0', '1', '2'];
           const next = levels[(levels.indexOf(jarvisLeash) + 1) % 3];
           setJarvisLeash(next);
           localStorage.setItem('jarvis_leash', next);
         }}>
           <span style={{ fontWeight: 'bold', color: jarvisLeash === '0' ? '#666' : (jarvisLeash === '1' ? 'var(--accent-blue)' : 'var(--neon-purple)') }}>
             🧠 <span className="hide-on-mobile">Leash: </span>{jarvisLeash === '0' ? 'Sleeping' : (jarvisLeash === '1' ? 'Reactive' : 'Proactive')}
           </span>
        </div>

        {/* ── Export Button ── */}
        <div
          title="Export & Encrypt Payload"
          style={{ display: 'inline-flex', alignItems: 'center', gap: '0.5rem', background: 'var(--bg-secondary)', padding: '0.4rem 0.8rem', borderRadius: '20px', fontSize: '0.8rem', border: '1px solid var(--border-focus)', cursor: 'pointer', transition: 'all 0.2s' }}
          onClick={async () => {
            const pwd = await requestSecurePrompt('Export Encryption', 'Set a password to protect this backup payload:');
            if (!pwd) return;
            try {
              const { encryptData } = await import('../../shared/utils/crypto');
              const { prepareForExport } = await import('../../shared/utils/normalization');
              const all = await db.thoughts.toArray();
              // Export surface thoughts only (exclude vaulted, trash, jarvis logs)
              const exportable = all.filter(t =>
                t.status !== 'vaulted' &&
                t.status !== 'vaulted_trash' &&
                t.type !== 'jarvis_log'
              );
              const sanitizedPayload = prepareForExport(exportable);
              const payload = JSON.stringify(sanitizedPayload);
              const encrypted = await encryptData(pwd, payload);
              const blob = new Blob([encrypted], { type: 'application/json' });
              const url = URL.createObjectURL(blob);
              const a = document.createElement('a');
              a.href = url;
              a.download = `strategist-backup-${new Date().toISOString().split('T')[0]}.json`;
              a.click();
              URL.revokeObjectURL(url);
              notify(`✓ Exported ${exportable.length} nodes successfully.`);
            } catch (err) {
              notify('Export failed: ' + err.message);
            }
          }}
        >
          <span style={{ fontWeight: 'bold', color: '#10b981' }}>📤 Export</span>
        </div>

        {/* ── Import Button ── */}
        <div
          title="Import Encrypted Payload"
          style={{ display: 'inline-flex', alignItems: 'center', gap: '0.5rem', background: 'var(--bg-secondary)', padding: '0.4rem 0.8rem', borderRadius: '20px', fontSize: '0.8rem', border: '1px solid var(--border-focus)', cursor: 'pointer', transition: 'all 0.2s' }}
          onClick={() => fileInputRef.current && fileInputRef.current.click()}
        >
          <span style={{ fontWeight: 'bold', color: 'var(--accent-blue)' }}>📥 Import</span>
        </div>

        {/* Hidden file input — triggered by the Import button above */}
        <input
          type="file"
          ref={fileInputRef}
          accept=".json"
          onChange={async (e) => {
            const file = e.target.files[0];
            if (!file) return;
            e.target.value = ''; // reset so same file can be re-imported
            const pwd = await requestSecurePrompt('Import Decryption', 'Enter the password used to encrypt this payload:');
            if (!pwd) return;
            const reader = new FileReader();
            reader.onload = async (event) => {
              try {
                const plainText = await decryptData(pwd, event.target.result);
                const imported = JSON.parse(plainText);
                if (Array.isArray(imported)) {
                  const { intelligentMerge } = await import('../../shared/infrastructure/db');
                  const count = await intelligentMerge(imported);
                  notify(`✓ Imported and merged ${count} nodes successfully.`);
                } else {
                  notify('Invalid payload format. Expected an array of thoughts.');
                }
              } catch (err) {
                notify('Failed to decrypt or parse backup. Incorrect password?');
              }
            };
            reader.readAsText(file);
          }}
          style={{ display: 'none' }}
        />
      </div>
    </header>
  );
}
