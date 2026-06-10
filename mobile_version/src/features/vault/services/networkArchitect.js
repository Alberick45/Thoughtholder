/**
 * NetworkArchitect - External Intelligence Service
 * Handles remote data access, searching, and scraping.
 */

export const networkArchitect = {
  /**
   * Search the web using a privacy-focused search provider (DuckDuckGo).
   * @param {string} query The search query.
   * @returns {Promise<Array>} List of search results {title, link, snippet}.
   */
  async search(query) {
    console.log(`[NETWORK] Searching for: ${query}`);
    try {
      // Use Local Proxy to bypass CORS
      const proxyUrl = `http://localhost:8080/proxy/ddg?q=${encodeURIComponent(query)}`;
      const response = await fetch(proxyUrl);
      const html = await response.text();

      // Simple parsing of DDG HTML results
      const results = [];
      const parser = new DOMParser();
      const doc = parser.parseFromString(html, 'text/html');
      const entries = doc.querySelectorAll('.result');

      entries.forEach(entry => {
        const titleEl = entry.querySelector('.result__title a');
        const snippetEl = entry.querySelector('.result__snippet');
        
        if (titleEl && snippetEl) {
          results.push({
            title: titleEl.textContent.trim(),
            link: titleEl.href,
            snippet: snippetEl.textContent.trim()
          });
        }
      });

      return results.slice(0, 5); // Return top 5
    } catch (error) {
      console.error('[NETWORK] Search failed:', error);
      throw error;
    }
  },

  /**
   * Scrape a URL and extract useful text content.
   * @param {string} url The URL to scrape.
   * @returns {Promise<string>} The extracted text.
   */
  async scrape(url) {
    console.log(`[NETWORK] Scraping URL: ${url}`);
    try {
      // Check robots.txt first (Requirement 2)
      const isAllowed = await this.isScrapingAllowed(url);
      if (!isAllowed) {
        throw new Error('SCRAPE_BLOCKED_BY_ROBOTS');
      }

      const response = await fetch(url);
      const html = await response.text();

      const parser = new DOMParser();
      const doc = parser.parseFromString(html, 'text/html');

      // Remove script, style, and navigation elements
      const elementsToRemove = doc.querySelectorAll('script, style, nav, footer, header, iframe, ads');
      elementsToRemove.forEach(el => el.remove());

      // Extract main text content
      // A simple heuristic: get text from p, h1, h2, h3 tags
      const contentElements = doc.querySelectorAll('p, h1, h2, h3, article');
      let text = Array.from(contentElements)
        .map(el => el.textContent.trim())
        .filter(t => t.length > 20) // Filter out noise
        .join('\n\n');

      return text;
    } catch (error) {
      console.error('[NETWORK] Scraping failed:', error);
      throw error;
    }
  },

  /**
   * Basic robots.txt check.
   */
  async isScrapingAllowed(url) {
    try {
      const parsedUrl = new URL(url);
      const robotsUrl = `${parsedUrl.protocol}//${parsedUrl.host}/robots.txt`;
      const response = await fetch(robotsUrl);
      if (!response.ok) return true; // Assume allowed if no robots.txt

      const text = await response.text();
      // Very basic check: look for User-agent: * and Disallow: /
      const lines = text.split('\n');
      let isRelevantSection = false;
      for (const line of lines) {
        const cleanLine = line.trim().toLowerCase();
        if (cleanLine.startsWith('user-agent: *')) {
          isRelevantSection = true;
        } else if (isRelevantSection && cleanLine.startsWith('disallow: /')) {
          const path = cleanLine.split('disallow:')[1].trim();
          if (path === '/' || parsedUrl.pathname.startsWith(path)) {
            return false;
          }
        } else if (cleanLine.startsWith('user-agent:')) {
          isRelevantSection = false;
        }
      }
      return true;
    } catch (e) {
      return true; // If check fails, default to allowed for now
    }
  }
};
