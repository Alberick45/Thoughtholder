/**
 * JAOS Cognitive Stream (The "Alive System" UX)
 * Visualizes the internal monologue and background async operations in real-time.
 */

import React, { useState, useEffect } from 'react';
import { bus } from '../engines/CognitiveEventBus';
import { stateManager } from '../engines/CognitiveStateManager';
import { Activity, Brain, Database, Shield, Zap } from 'lucide-react';

export default function CognitiveStream() {
    const [stream, setStream] = useState([]);
    const [activeState, setActiveState] = useState(stateManager.currentState);
    const [config, setConfig] = useState(stateManager.getStateConfig(stateManager.currentState));

    useEffect(() => {
        // 1. Listen for State Changes
        const unsubState = bus.subscribe('STATE_CHANGED', (data) => {
            setActiveState(data.current);
            setConfig(data.config);
            addLog(`Shifted to ${data.current}`, data.config.uiIndicator);
        });

        // 2. Listen for Model Thinking (Internal Monologue)
        const unsubThinking = bus.subscribe('MODEL_THINKING', (data) => {
            if (data.step === 'MONOLOGUE') {
                addLog(data.content, 'thinking');
            } else {
                addLog(data.message, 'system');
            }
        });

        // 3. Listen for Background Tasks
        const unsubMemory = bus.subscribe('MEMORY_LINKED', () => addLog('Linking memory continuity...', 'memory'));
        const unsubEmotion = bus.subscribe('UPDATE_RELATIONAL_MODEL', () => addLog('Analyzing emotional trajectory...', 'emotion'));

        return () => {
            unsubState();
            unsubThinking();
            unsubMemory();
            unsubEmotion();
        };
    }, []);

    const addLog = (message, type) => {
        setStream(prev => {
            const newStream = [...prev, { id: Date.now(), message, type }];
            return newStream.slice(-3); // Keep only the last 3 visible
        });
    };

    const getIcon = (type) => {
        switch(type) {
            case 'memory': return <Database size={14} color="#eab308" />;
            case 'emotion': return <Shield size={14} color="#a855f7" />;
            case 'thinking': return <Brain size={14} color="#3b82f6" />;
            case 'system': return <Activity size={14} color="#f97316" />;
            default: return <Zap size={14} color="#22c55e" />;
        }
    };

    return (
        <div style={{
            position: 'fixed',
            bottom: '80px',
            right: '20px',
            width: '320px',
            pointerEvents: 'none',
            zIndex: 9999,
            display: 'flex',
            flexDirection: 'column',
            gap: '8px'
        }}>
            {/* Live State Indicator */}
            <div style={{
                padding: '8px 12px',
                background: 'rgba(10,10,15,0.8)',
                borderRadius: '12px',
                border: `1px solid ${config.uiIndicator.includes('Blue') ? '#3b82f6' : 'rgba(255,255,255,0.1)'}`,
                display: 'flex',
                alignItems: 'center',
                gap: '8px',
                color: 'white',
                fontSize: '0.75rem',
                fontWeight: 'bold',
                backdropFilter: 'blur(10px)'
            }}>
                <div style={{
                    width: '8px', height: '8px', borderRadius: '50%',
                    background: config.uiIndicator.includes('Blue') ? '#3b82f6' : (config.uiIndicator.includes('Orange') ? '#f97316' : '#22c55e'),
                    boxShadow: `0 0 8px ${config.uiIndicator.includes('Blue') ? '#3b82f6' : '#22c55e'}`
                }} />
                [{activeState}] - {config.modelUsage}
            </div>

            {/* Micro-Updates Stream */}
            {stream.map((log) => (
                <div key={log.id} style={{
                    padding: '8px 12px',
                    background: 'rgba(255,255,255,0.03)',
                    borderRadius: '8px',
                    borderLeft: '2px solid rgba(255,255,255,0.2)',
                    color: 'rgba(255,255,255,0.6)',
                    fontSize: '0.7rem',
                    fontStyle: log.type === 'thinking' ? 'italic' : 'normal',
                    display: 'flex',
                    alignItems: 'flex-start',
                    gap: '8px',
                    animation: 'fadeUp 0.3s ease-out forwards'
                }}>
                    <div style={{ marginTop: '2px' }}>{getIcon(log.type)}</div>
                    <div style={{ lineHeight: '1.4' }}>{log.message}</div>
                </div>
            ))}

            <style>{`
                @keyframes fadeUp {
                    from { opacity: 0; transform: translateY(10px); }
                    to { opacity: 1; transform: translateY(0); }
                }
            `}</style>
        </div>
    );
}
