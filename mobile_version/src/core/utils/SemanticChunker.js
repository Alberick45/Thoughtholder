/**
 * Semantic Chunker for Document processing
 * Pipeline: Paragraph split -> Sentence boundary detection -> soft token budget -> small overlap
 */

export class SemanticChunker {
    constructor(targetTokens = 200, overlapTokens = 30) {
        this.targetTokens = targetTokens;
        this.overlapTokens = overlapTokens;
        // Roughly 4 chars per token as a quick approximation for english text
        this.charsPerToken = 4; 
    }

    /**
     * Splits text into semantic chunks while respecting boundaries
     */
    chunk(text) {
        if (!text) return [];
        
        // 1. Paragraph Split
        const paragraphs = text.split(/\n\s*\n/);
        
        const chunks = [];
        let currentChunk = [];
        let currentTokenCount = 0;

        for (const para of paragraphs) {
            // 2. Sentence boundary detection (naive regex for English)
            const sentences = para.match(/[^.!?]+[.!?]+|\s+$/g) || [para];
            
            for (const sentence of sentences) {
                const cleanSentence = sentence.trim();
                if (!cleanSentence) continue;
                
                const sentenceTokens = Math.ceil(cleanSentence.length / this.charsPerToken);
                
                // 3. Soft token budget enforcement
                if (currentTokenCount + sentenceTokens > this.targetTokens && currentChunk.length > 0) {
                    // Finalize current chunk
                    chunks.push(currentChunk.join(' '));
                    
                    // 4. Create overlap for the next chunk
                    // Walk backwards to gather sentences for overlap
                    let overlapTokensCount = 0;
                    const overlapBuffer = [];
                    for (let i = currentChunk.length - 1; i >= 0; i--) {
                        const prevSentence = currentChunk[i];
                        const prevTokens = Math.ceil(prevSentence.length / this.charsPerToken);
                        if (overlapTokensCount + prevTokens <= this.overlapTokens) {
                            overlapBuffer.unshift(prevSentence);
                            overlapTokensCount += prevTokens;
                        } else {
                            break;
                        }
                    }
                    
                    currentChunk = [...overlapBuffer, cleanSentence];
                    currentTokenCount = overlapTokensCount + sentenceTokens;
                } else {
                    currentChunk.push(cleanSentence);
                    currentTokenCount += sentenceTokens;
                }
            }
        }
        
        if (currentChunk.length > 0) {
            chunks.push(currentChunk.join(' '));
        }
        
        return chunks;
    }
}
