/**
 * JAOS Phase 7: Notification Intelligence
 * Handles non-intrusive ambient notifications and system alerts.
 */

export const sendAmbientNotification = (title, body, onClick) => {
    // 1. Check permissions
    if (Notification.permission === 'granted') {
        const n = new Notification(title, {
            body,
            icon: '/favicon.ico',
            silent: true // Maintain ambient philosophy
        });
        if (onClick) n.onclick = onClick;
    } else if (Notification.permission !== 'denied') {
        Notification.requestPermission();
    }

    // 2. Fallback: System Log (internal cognition)
    console.log(`[AMBIENT_NOTIF] ${title}: ${body}`);
};

export const evaluateNotificationPriority = (urgency, fatigue) => {
    // If fatigue is high, suppress low-urgency notifications
    if (fatigue > 0.8 && urgency < 0.6) return false;
    return true;
};
