/**
 * JAOS Behavioral Forecaster
 * 
 * Predicts future user needs and busy windows based on 
 * historical behavioral data and temporal rhythms.
 */

export class BehavioralForecaster {
    constructor(db) {
        this.db = db;
    }

    /**
     * Forecasts the user's likely needs for the next 4-8 hours
     */
    async forecast() {
        const rhythm = JSON.parse(localStorage.getItem('jaos_temporal_rhythm') || '{}');
        const now = new Date();
        const currentHour = now.getHours();
        
        // 1. Predict Activity Level
        const nextHour = (currentHour + 1) % 24;
        const forecastedActivity = rhythm.hourlyActivity ? rhythm.hourlyActivity[nextHour] : 0;
        const avgActivity = rhythm.hourlyActivity ? (rhythm.hourlyActivity.reduce((a, b) => a + b, 0) / 24) : 0;

        const isApproachingPeak = rhythm.peakHour === nextHour || rhythm.peakHour === (nextHour + 1) % 24;
        const isApproachingLull = forecastedActivity < (avgActivity * 0.5);

        // 2. Identify likely next focus area
        const lifeModel = JSON.parse(localStorage.getItem('jaos_life_model') || '{}');
        const focus = lifeModel.focus || 'General';

        const forecast = {
            window: 'Next 4 Hours',
            predictedState: isApproachingPeak ? 'Peak Activity' : (isApproachingLull ? 'Low Activity/Rest' : 'Moderate'),
            suggestedStrategy: isApproachingPeak ? 'Focus Stabilization' : 'Administrative Cleanup',
            likelyNextFocus: focus,
            updated_at: Date.now()
        };

        localStorage.setItem('jaos_behavioral_forecast', JSON.stringify(forecast));
        try {
            await this.db.settings.put({ key: 'jaos_behavioral_forecast', value: forecast });
        } catch (e) {
            console.warn("[FORECASTER] DB persistence failed:", e);
        }
        return forecast;
    }

    static getForecast() {
        return JSON.parse(localStorage.getItem('jaos_behavioral_forecast') || '{}');
    }
}
