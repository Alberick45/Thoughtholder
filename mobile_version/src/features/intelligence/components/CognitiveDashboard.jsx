import React, { useState, useEffect } from 'react';
import { Brain, Zap, Activity, Eye, Shield, Target, MessageSquare, ArrowLeft, Cpu } from 'lucide-react';

/**
 * JAOS Diagnostic Dashboard
 * Visualizes the internal cognitive state, attention metrics, and evolutionary data.
 */
export default function CognitiveDashboard({ onBack }) {
  const [state, setState] = useState({
    mode: 'IDLE',
    fatigue: '0.10',
    evolution: 'STRANGER',
    momentum: 'Stable',
    confidence: '0.00',
    unresolvedLoops: 0,
    ollamaStatus: 'CHECKING'
  });

  useEffect(() => {
    const updateStats = async () => {
      let evolution = { depth: "STRANGER" };
      try {
        const stored = localStorage.getItem('jaos_evolution_state');
        if (stored) evolution = JSON.parse(stored);
      } catch (e) {
        console.warn("[COGNITIVE] Failed to parse evolution state, using default.");
      }
      
      let ollamaStatus = 'OFFLINE';
      try {
        const resp = await fetch('http://localhost:11434/api/tags');
        if (resp.ok) ollamaStatus = 'ONLINE';
      } catch(e) {}

      setState({
        mode: localStorage.getItem('jaos_current_state') || 'IDLE',
        fatigue: localStorage.getItem('jaos_fatigue_level') || '0.10',
        evolution: evolution,
        ollamaStatus,
        awareness: JSON.parse(localStorage.getItem('jaos_awareness_state') || '{}'),
        continuity: JSON.parse(localStorage.getItem('jaos_continuity_state') || '{}'),
        forecast: JSON.parse(localStorage.getItem('jaos_behavioral_forecast') || '{}')
      });
    };

    updateStats();
    const interval = setInterval(updateStats, 5000);
    return () => clearInterval(interval);
  }, []);

  const metrics = [
    { label: 'Cognitive Mode', value: state.mode, icon: Brain, color: '#3b82f6' },
    { label: 'Fatigue Level', value: state.fatigue, icon: Activity, color: '#f97316' },
    { label: 'Cognitive Density', value: ((state.awareness?.density || 0) * 100).toFixed(0) + '%', icon: MessageSquare, color: '#06b6d4' },
    { label: 'Task Momentum', value: ((state.awareness?.momentum || 0) * 100).toFixed(0) + '%', icon: Zap, color: '#eab308' },
    { label: 'Project Continuity', value: state.continuity?.momentumStatus || 'Healthy', icon: Target, color: '#10b981' },
    { label: 'Energy Phase', value: state.forecast?.predictedState || 'Moderate', icon: Zap, color: '#ec4899' },
  ];

  return (
    <div style={{ padding: '2rem', color: 'white', background: 'rgba(10, 10, 15, 0.95)', minHeight: '100vh' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '2.5rem' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '1rem' }}>
          <button 
            onClick={onBack}
            style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)', color: 'rgba(255,255,255,0.6)', padding: '0.6rem', borderRadius: '12px', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center' }}
          >
            <ArrowLeft size={18} />
          </button>
          <div>
            <h2 style={{ fontSize: '1.5rem', fontWeight: '800', margin: 0, letterSpacing: '-0.02em' }}>Cognitive Infrastructure</h2>
            <p style={{ fontSize: '0.75rem', color: 'rgba(255,255,255,0.4)', margin: '0.2rem 0 0 0' }}>JAOS v4.0 Evolution Monitor</p>
          </div>
        </div>

        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '0.8rem', justifyContent: 'flex-end' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '0.6rem', background: 'rgba(255,255,255,0.05)', padding: '0.6rem 1rem', borderRadius: '16px', border: '1px solid rgba(255,255,255,0.1)' }}>
            <Cpu size={14} color={state.ollamaStatus === 'ONLINE' ? '#22c55e' : '#ef4444'} />
            <span style={{ fontSize: '0.7rem', fontWeight: 'bold' }}>
              OLLAMA: <span style={{ color: state.ollamaStatus === 'ONLINE' ? '#22c55e' : '#ef4444' }}>{state.ollamaStatus}</span>
            </span>
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: '0.6rem', background: 'rgba(255,255,255,0.05)', padding: '0.6rem 1rem', borderRadius: '16px', border: '1px solid rgba(255,255,255,0.1)' }}>
            <Activity size={14} color="#f97316" />
            <span style={{ fontSize: '0.7rem', fontWeight: 'bold' }}>
              DECAY: <span style={{ color: '#f97316' }}>{state.evolution?.axes?.decayFactor || '1.00'}x</span>
            </span>
          </div>
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: '1.5rem', marginBottom: '2rem' }}>
        {metrics.map((m) => (
          <div
            key={m.label}
            style={{ padding: '1.5rem', borderRadius: '24px', background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.08)', transition: 'all 0.3s' }}
          >
            <div style={{ padding: '0.6rem', borderRadius: '12px', background: `${m.color}15`, width: 'fit-content', marginBottom: '1rem', color: m.color }}>
              <m.icon size={20} />
            </div>
            <div style={{ fontSize: '0.7rem', color: 'rgba(255,255,255,0.4)', fontWeight: 'bold', marginBottom: '0.4rem', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
              {m.label}
            </div>
            <div style={{ fontSize: '1.25rem', fontVariantNumeric: 'tabular-nums', fontWeight: '700' }}>
              {m.value}
            </div>
          </div>
        ))}
      </div>

      <div style={{ padding: '2rem', borderRadius: '24px', background: 'linear-gradient(145deg, rgba(59, 130, 246, 0.05), rgba(37, 99, 235, 0.02))', border: '1px solid rgba(59, 130, 246, 0.1)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.8rem', marginBottom: '1rem' }}>
          <Target size={18} color="#3b82f6" />
          <h3 style={{ fontSize: '0.75rem', fontWeight: '800', color: '#3b82f6', textTransform: 'uppercase', letterSpacing: '0.1em', margin: 0 }}>Internal Monologue Strategy</h3>
        </div>
        <p style={{ fontSize: '0.9rem', color: 'rgba(255,255,255,0.7)', lineHeight: '1.6', margin: 0, fontStyle: 'italic', fontWeight: '450' }}>
          "User currently in {state.mode} state with {parseFloat(state.fatigue) > 0.5 ? 'elevated' : 'stable'} fatigue. 
          Prioritizing {state.mode === 'DEEP_WORK' ? 'minimalist' : 'supportive'} ambient presence. 
          Relational depth is {state.evolution?.depth || 'STRANGER'}; maintaining peer-level communication density."
        </p>
      </div>
    </div>
  );
}

