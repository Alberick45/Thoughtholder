import React, { useMemo } from 'react';
import { architectureEngine } from '../services/architectureEngine';

/**
 * ArchitectureVisualizer - Graph-style view of project ecosystem.
 */
export default function ArchitectureVisualizer({ thoughts, onNodeClick }) {
  // Simple layout logic: group by type and display in a grid/flow
  const nodes = useMemo(() => {
    return thoughts.filter(t => t.status !== 'trash');
  }, [thoughts]);

  const links = useMemo(() => {
    const l = [];
    nodes.forEach(node => {
      if (node.linked_thoughts) {
        node.linked_thoughts.forEach(targetId => {
          const target = nodes.find(n => n.id === targetId);
          if (target) {
            l.push({ source: node, target });
          }
        });
      }
    });
    return l;
  }, [nodes]);

  const getTypeColor = (type) => {
    switch (type) {
      case 'idea': return 'var(--neon-purple)';
      case 'task': return 'var(--accent-blue)';
      case 'note': return '#10b981';
      default: return 'var(--text-muted)';
    }
  };

  return (
    <div className="glass-panel" style={{ width: '100%', height: '100%', padding: '2rem', overflow: 'hidden', position: 'relative', background: 'rgba(5, 5, 10, 0.9)' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '2rem' }}>
        <h2 style={{ color: 'var(--neon-purple)', letterSpacing: '2px', textTransform: 'uppercase' }}>Architecture Visualizer</h2>
        <div style={{ display: 'flex', gap: '1rem', fontSize: '0.8rem' }}>
          <span style={{ color: 'var(--neon-purple)' }}>● Ideas</span>
          <span style={{ color: 'var(--accent-blue)' }}>● Tasks</span>
          <span style={{ color: '#10b981' }}>● Notes</span>
        </div>
      </div>

      <div style={{ position: 'relative', width: '100%', height: 'calc(100% - 4rem)', border: '1px solid #222', borderRadius: '12px', background: '#000' }}>
        {/* SVG and Nodes share the same coordinate space */}
        <div style={{ position: 'relative', width: '100%', height: '100%', overflow: 'auto' }}>
          <div style={{ position: 'relative', width: '1000px', height: `${Math.max(100, Math.ceil(nodes.length / 5) * 150)}px`, minHeight: '100%' }}>
            {/* Lines Layer */}
            <svg style={{ position: 'absolute', top: 0, left: 0, width: '100%', height: '100%', pointerEvents: 'none', zIndex: 1 }}>
              <defs>
                <marker id="arrowhead" markerWidth="10" markerHeight="7" refX="9" refY="3.5" orient="auto">
                  <polygon points="0 0, 10 3.5, 0 7" fill="rgba(139, 92, 246, 0.8)" />
                </marker>
              </defs>
              {links.map((link, i) => {
                const sourceIndex = nodes.indexOf(link.source);
                const targetIndex = nodes.indexOf(link.target);
                // Center coordinates for nodes
                const x1 = (sourceIndex % 5) * 180 + 90;
                const y1 = Math.floor(sourceIndex / 5) * 150 + 75;
                const x2 = (targetIndex % 5) * 180 + 90;
                const y2 = Math.floor(targetIndex / 5) * 150 + 75;
                
                // Adjust end point so arrow doesn't hide under the box (box is ~140px wide, 80px tall)
                // Radius approximation: ~70px horizontally, ~40px vertically
                const angle = Math.atan2(y2 - y1, x2 - x1);
                const adjustedX2 = x2 - Math.cos(angle) * 75;
                const adjustedY2 = y2 - Math.sin(angle) * 45;

                return (
                  <line key={i} x1={x1} y1={y1} x2={adjustedX2} y2={adjustedY2} stroke="rgba(139, 92, 246, 0.6)" strokeWidth="2" markerEnd="url(#arrowhead)" />
                );
              })}
            </svg>

            {/* Nodes Layer */}
            {nodes.map((node, i) => {
              const x = (i % 5) * 180 + 90;
              const y = Math.floor(i / 5) * 150 + 75;
              return (
                <div 
                  key={node.id} 
                  onClick={() => onNodeClick && onNodeClick(node)}
                  className="node-pulse"
                  style={{ 
                    position: 'absolute',
                    left: `${x - 70}px`, // Centered (assuming 140px width)
                    top: `${y - 40}px`,  // Centered (assuming 80px height)
                    width: '140px',
                    height: '80px',
                    background: '#111', 
                    border: `2px solid ${getTypeColor(node.type)}`, 
                    borderRadius: '12px', 
                    padding: '0.8rem', 
                    textAlign: 'center', 
                    cursor: 'pointer',
                    boxShadow: `0 0 15px ${getTypeColor(node.type)}44`,
                    transition: 'all 0.3s',
                    zIndex: 2,
                    display: 'flex',
                    flexDirection: 'column',
                    justifyContent: 'center'
                  }}
                >
                  <div style={{ fontSize: '0.7rem', color: getTypeColor(node.type), fontWeight: 'bold', marginBottom: '0.3rem' }}>{node.thought_id}</div>
                  <div style={{ fontSize: '0.75rem', color: 'white', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{node.content.replace(/\n/g, ' ')}</div>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}
