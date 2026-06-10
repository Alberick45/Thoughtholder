import { db } from '../../../shared/infrastructure/db';

/**
 * ArchitectureEngine - Core logic for understanding system structure and dependencies.
 */
export const architectureEngine = {
  /**
   * Build a recursive dependency tree starting from a specific thought.
   * @param {string} rootId The ID of the root thought.
   * @returns {Promise<object>} The dependency tree.
   */
  async buildDependencyTree(rootId) {
    const allThoughts = await db.thoughts.toArray();
    const thoughtMap = new Map(allThoughts.map(t => [t.id, t]));
    
    const buildNode = (id, visited = new Set()) => {
      if (visited.has(id)) return { id, error: 'Circular Dependency' };
      visited.add(id);
      
      const thought = thoughtMap.get(id);
      if (!thought) return null;
      
      const children = (thought.linked_thoughts || [])
        .map(childId => buildNode(childId, new Set(visited)))
        .filter(Boolean);
        
      return {
        ...thought,
        dependencies: children
      };
    };
    
    return buildNode(rootId);
  },

  /**
   * Analyze the complexity and "bloat" of the current architecture.
   */
  async analyzeComplexity() {
    const thoughts = await db.thoughts.toArray();
    const linkCount = thoughts.reduce((acc, t) => acc + (t.linked_thoughts?.length || 0), 0);
    const avgLinks = thoughts.length > 0 ? linkCount / thoughts.length : 0;
    
    return {
      totalNodes: thoughts.length,
      totalLinks: linkCount,
      averageComplexity: avgLinks.toFixed(2),
      status: avgLinks > 5 ? 'CRITICAL_BLOAT' : (avgLinks > 2 ? 'COMPLEX' : 'OPTIMIZED')
    };
  }
};
