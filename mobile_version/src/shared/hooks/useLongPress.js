import { useState, useRef, useCallback } from 'react';

export function useLongPress(callback, ms = 500) {
    const [startLongPress, setStartLongPress] = useState(false);
    const timerRef = useRef();

    const start = useCallback((e) => {
        // Prevent default only if it's a touch event to avoid double triggers
        if (e.touches) {
            setStartLongPress(true);
            timerRef.current = setTimeout(() => {
                callback(e);
                setStartLongPress(false);
            }, ms);
        } else {
            // Support for mouse long press if needed
            setStartLongPress(true);
            timerRef.current = setTimeout(() => {
                callback(e);
                setStartLongPress(false);
            }, ms);
        }
    }, [callback, ms]);

    const stop = useCallback(() => {
        setStartLongPress(false);
        if (timerRef.current) {
            clearTimeout(timerRef.current);
        }
    }, []);

    return {
        onMouseDown: start,
        onMouseUp: stop,
        onMouseLeave: stop,
        onTouchStart: start,
        onTouchEnd: stop,
    };
}
