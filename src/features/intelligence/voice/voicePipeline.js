/**
 * JAOS Phase 7: Voice Pipeline
 * Manages Speech-to-Text (STT) and Text-to-Speech (TTS) for ambient interaction.
 */

export const speak = (text, voiceIndex = 0) => {
    if (!('speechSynthesis' in window)) return;

    const utterance = new SpeechSynthesisUtterance(text);
    const voices = window.speechSynthesis.getVoices();
    if (voices.length > 0) {
        utterance.voice = voices[voiceIndex];
    }
    utterance.rate = 1.1; // Slightly faster for human peer feel
    utterance.pitch = 1.0;
    
    window.speechSynthesis.speak(utterance);
};

export const startListening = (onResult, onError) => {
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognition) return null;

    const recognition = new SpeechRecognition();
    recognition.continuous = false;
    recognition.interimResults = false;
    recognition.lang = 'en-US';

    recognition.onresult = (event) => {
        const transcript = event.results[0][0].transcript;
        onResult(transcript);
    };

    recognition.onerror = (event) => {
        if (onError) onError(event.error);
    };

    recognition.start();
    return recognition;
};
