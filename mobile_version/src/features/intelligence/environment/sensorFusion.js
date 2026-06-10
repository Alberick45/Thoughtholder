/**
 * JAOS Phase 4: Sensor Fusion Layer
 * Aggregates raw system data into a structured environment snapshot.
 */

export const getEnvironmentSnapshot = () => {
    // In a full production app, these would come from Electron APIs or system hooks.
    // For the web/browser version, we use browser APIs and local state.
    
    return {
        timestamp: Date.now(),
        window: {
            activeApp: 'Strategist Arsenal',
            isFocused: document.hasFocus(),
            url: window.location.href,
        },
        input: {
            keyboardActivity: 'MODERATE', // Mocked for now
            mouseActivity: 'ACTIVE',
        },
        system: {
            batteryLevel: navigator.getBattery ? 'UNKNOWN' : 'PLUGGED_IN',
            networkStatus: navigator.onLine ? 'ONLINE' : 'OFFLINE',
            screenResolution: `${window.innerWidth}x${window.innerHeight}`,
        },
        context: {
            currentTask: localStorage.getItem('last_active_task') || 'None',
            currentMomentum: localStorage.getItem('jaos_momentum_score') || 0.5,
            userPresence: 'DETECTED'
        }
    };
};
