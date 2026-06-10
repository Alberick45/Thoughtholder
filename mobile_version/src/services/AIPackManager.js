/**
 * AI Pack Manager
 * Manages the tiered downloading and storage of AI models to prevent
 * massive initial app downloads.
 */

export const AIPacks = {
    CORE: 'core',       // No LLM, basic notes (default)
    LITE: 'lite',       // Embeddings & Semantic Search (~300MB)
    FULL: 'full'        // Phi-3 generation & Offline Chat (~2.2GB)
};

export class AIPackManagerService {
    constructor() {
        this.currentPack = AIPacks.CORE;
        this.downloadProgress = 0;
        this.isDownloading = false;
        this.listeners = new Set();
    }

    subscribe(callback) {
        this.listeners.add(callback);
        return () => this.listeners.delete(callback);
    }

    notify() {
        for (const listener of this.listeners) {
            listener({
                pack: this.currentPack,
                progress: this.downloadProgress,
                isDownloading: this.isDownloading
            });
        }
    }

    async checkInstalledPacks() {
        // In a real app, use Capacitor Filesystem to check for model files
        // For now, assume CORE.
        this.notify();
        return this.currentPack;
    }

    async downloadPack(packTarget) {
        if (this.isDownloading) {
            throw new Error("A download is already in progress.");
        }
        
        if (packTarget === AIPacks.CORE) return; // Already installed

        this.isDownloading = true;
        this.downloadProgress = 0;
        this.notify();

        console.log(`[AIPackManager] Starting download for ${packTarget} pack...`);

        // Simulate a large file download (e.g. streaming from AWS S3 / HuggingFace)
        // We use setInterval to fake the download progress over time
        return new Promise((resolve) => {
            const interval = setInterval(() => {
                // Slower progress for FULL pack (2.2GB) vs LITE pack (300MB)
                const increment = packTarget === AIPacks.FULL ? 2 : 10;
                
                this.downloadProgress += increment;
                
                if (this.downloadProgress >= 100) {
                    this.downloadProgress = 100;
                    this.isDownloading = false;
                    this.currentPack = packTarget;
                    clearInterval(interval);
                    console.log(`[AIPackManager] ${packTarget} pack download complete.`);
                    this.notify();
                    resolve();
                } else {
                    this.notify();
                }
            }, 500); // Firing every 500ms
        });
    }

    /**
     * Determines if a feature is unlocked based on installed packs
     */
    canUseEmbeddings() {
        return this.currentPack === AIPacks.LITE || this.currentPack === AIPacks.FULL;
    }

    canUseGeneration() {
        return this.currentPack === AIPacks.FULL;
    }
}

export const AIPackManager = new AIPackManagerService();
