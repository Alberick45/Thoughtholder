/**
 * Intelligent Formatting Engine
 * Processes raw transcripts into structured formats based on the current mode.
 */

export class FormatEngine {
  constructor() {
    this.lastSpeechTime = Date.now();
  }

  /**
   * Processes a new speech segment and appends it correctly based on mode.
   * @param {string} cleanTranscript - The latest chunk of transcribed text
   * @param {string} currentText - The existing text in the input bar
   * @param {string} mode - 'thought', 'task', or 'buy'
   * @param {boolean} isFinal - Whether this chunk is a final segment
   * @returns {string} The combined and formatted text
   */
  process(rawTranscript, currentText, mode, isFinal = false) {
    if (!rawTranscript) return currentText;
    
    // Strip out hallucinated tags from Whisper like [BLANK_AUDIO] or (birds chirping)
    const cleanTranscript = rawTranscript.replace(/[\[\(].*?[\]\)]/g, '').trim();
    if (!cleanTranscript) return currentText;

    const trimmedCurrent = currentText.trim();
    const isList = mode === 'task' || mode === 'buy' || trimmedCurrent.match(/^\d+\.\s/m);

    // If it's Thought Mode: Continuous flowing text
    if (!isList) {
      if (!currentText) return cleanTranscript;
      // Add a space if it doesn't already have one
      const hasTrailingSpace = currentText.endsWith(' ') || currentText.endsWith('\n');
      return `${currentText}${hasTrailingSpace ? '' : ' '}${cleanTranscript}`;
    }

    // LIST MODE
    if (!trimmedCurrent) {
      // Input bar empty, start list
      if (!cleanTranscript.match(/^\d+\.\s/)) {
        return `1. ${cleanTranscript}`;
      }
      return cleanTranscript;
    }

    // Determine if we need to start a new line.
    // If it's an interim result and the current line already exists, we just append it.
    // The previous implementation appended to the end of the line if it ended with a number, 
    // or created a new line. Since we are doing streaming, if it's interim we don't start a new line 
    // unless there was a significant pause.

    const endsWithNumbering = currentText.match(/\b\d+\.\s*$/);
    if (endsWithNumbering) {
      const hasTrailingSpace = currentText.endsWith(' ');
      return `${currentText}${hasTrailingSpace ? '' : ' '}${cleanTranscript}`;
    }

    // In streaming, we only want to jump to a new line if it's a new final segment 
    // and there was a pause, OR if it's explicitly a new line command.
    // For simplicity, if it's final we jump to the next line. If it's interim, we append to the last line.
    if (!isFinal) {
      // Just append to the last line for interim
      const hasTrailingSpace = currentText.endsWith(' ');
      return `${currentText}${hasTrailingSpace ? '' : ' '}${cleanTranscript}`;
    }

    // It's a final segment. Find the next number.
    const lines = trimmedCurrent.split('\n');
    let nextNumber = 1;
    for (let j = lines.length - 1; j >= 0; j--) {
      const match = lines[j].match(/^(\d+)\.\s/);
      if (match) {
        nextNumber = parseInt(match[1], 10) + 1;
        break;
      }
    }

    return `${trimmedCurrent}\n${nextNumber}. ${cleanTranscript}`;
  }
}

export const formatEngine = new FormatEngine();
