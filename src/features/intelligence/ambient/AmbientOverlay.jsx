import React, { useState, useEffect } from 'react';
import { Sparkles, X, Volume2 } from 'lucide-react';

/**
 * JAOS Phase 7: Ambient Overlay
 * A non-intrusive, glassmorphic UI for displaying proactive insights and alerts.
 */
export default function AmbientOverlay({ insight, onDismiss, onAction }) {
  if (!insight) return null;

  return (
    <div
      className="fixed bottom-24 right-6 w-80 p-4 rounded-2xl border border-white/10 shadow-2xl backdrop-blur-xl bg-black/40 z-50 overflow-hidden animate-in fade-in slide-in-from-bottom-5 duration-500"
    >
      {/* Glow Effect */}
      <div className="absolute -top-10 -right-10 w-32 h-32 bg-blue-500/20 rounded-full blur-3xl pointer-events-none" />
      
      <div className="flex items-start gap-3 relative z-10">
        <div className="p-2 rounded-xl bg-blue-500/20 text-blue-400">
          <Brain size={18} />
        </div>
        
        <div className="flex-1 min-w-0">
          <h4 className="text-xs font-bold text-blue-400 uppercase tracking-widest mb-1">
            Ambient Insight
          </h4>
          <p className="text-sm text-white/90 leading-relaxed line-clamp-3">
            {insight}
          </p>
        </div>

        <button 
          onClick={onDismiss}
          className="p-1 hover:bg-white/10 rounded-lg text-white/40 hover:text-white/80 transition-colors"
        >
          <X size={16} />
        </button>
      </div>

      <div className="mt-4 flex gap-2 relative z-10">
        <button 
          onClick={() => onAction('explore')}
          className="flex-1 py-1.5 rounded-xl bg-white/10 hover:bg-white/20 text-xs font-medium text-white transition-all border border-white/5"
        >
          Explore
        </button>
        <button 
          onClick={() => onAction('voice')}
          className="p-1.5 rounded-xl bg-blue-500/20 hover:bg-blue-500/30 text-blue-400 transition-all border border-blue-500/20"
        >
          <Volume2 size={16} />
        </button>
      </div>
    </div>
  );
}
