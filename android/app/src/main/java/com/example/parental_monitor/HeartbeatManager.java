package com.example.parental_monitor;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;

import java.util.HashMap;
import java.util.Map;

/**
 * HeartbeatManager - Centralized manager for service heartbeat persistence.
 * 
 * DESIGN RATIONALE:
 * -----------------
 * 1. We use SharedPreferences because:
 *    - It persists across process death (unlike static variables)
 *    - It's lightweight and battery-efficient
 *    - It's synchronous for reads, making health checks fast
 * 
 * 2. We do NOT rely on onDestroy() because:
 *    - Android may kill the process without calling lifecycle methods
 *    - The system can terminate apps during low memory without notice
 * 
 * 3. Health detection is based on timestamp staleness:
 *    - If (currentTime - lastHeartbeat) > threshold, service is considered dead
 *    - Default threshold is 10 minutes (configurable)
 * 
 * USAGE:
 * ------
 * - AppBlockerService calls recordHeartbeat() every 3 minutes
 * - ServiceHealthWorker calls isServiceHealthy() to check if recovery is needed
 * - Flutter calls getHeartbeatStatus() via platform channel for UI display
 */
public class HeartbeatManager {
    private static final String TAG = "HeartbeatManager";
    private static final String PREFS_NAME = "heartbeat_prefs";
    
    // SharedPreferences keys
    private static final String KEY_LAST_HEARTBEAT = "last_heartbeat_time";
    private static final String KEY_SERVICE_START_TIME = "service_start_time";
    private static final String KEY_HEARTBEAT_COUNT = "heartbeat_count";
    
    // Default health threshold: 10 minutes
    // If no heartbeat for 10 minutes, service is considered dead
    public static final long DEFAULT_HEALTH_THRESHOLD_MS = 10 * 60 * 1000;
    
    // Heartbeat update interval: 3 minutes
    // Chosen as a balance between reliability and battery efficiency
    public static final long HEARTBEAT_INTERVAL_MS = 3 * 60 * 1000;
    
    private final SharedPreferences prefs;
    private final Context context;
    
    public HeartbeatManager(Context context) {
        this.context = context.getApplicationContext();
        this.prefs = this.context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
    }
    
    /**
     * Record a heartbeat. Called by AppBlockerService periodically.
     * This updates the timestamp to prove the service is still alive.
     */
    public void recordHeartbeat() {
        long now = System.currentTimeMillis();
        long count = prefs.getLong(KEY_HEARTBEAT_COUNT, 0) + 1;
        
        prefs.edit()
            .putLong(KEY_LAST_HEARTBEAT, now)
            .putLong(KEY_HEARTBEAT_COUNT, count)
            .apply();
        
        Log.d(TAG, "Heartbeat recorded #" + count + " at " + now);
    }
    
    /**
     * Record that the service has started.
     * This is separate from heartbeat and tracks service lifecycle.
     */
    public void recordServiceStart() {
        long now = System.currentTimeMillis();
        prefs.edit()
            .putLong(KEY_SERVICE_START_TIME, now)
            .putLong(KEY_LAST_HEARTBEAT, now) // Also count as a heartbeat
            .apply();
        
        Log.d(TAG, "Service start recorded at " + now);
    }
    
    /**
     * Get the timestamp of the last heartbeat.
     * @return Milliseconds since epoch, or 0 if never recorded
     */
    public long getLastHeartbeatTime() {
        return prefs.getLong(KEY_LAST_HEARTBEAT, 0);
    }
    
    /**
     * Get the timestamp when the service was last started.
     * @return Milliseconds since epoch, or 0 if never started
     */
    public long getServiceStartTime() {
        return prefs.getLong(KEY_SERVICE_START_TIME, 0);
    }
    
    /**
     * Get the total number of heartbeats recorded.
     * Useful for debugging and monitoring service uptime.
     */
    public long getHeartbeatCount() {
        return prefs.getLong(KEY_HEARTBEAT_COUNT, 0);
    }
    
    /**
     * Check if the service is healthy based on heartbeat staleness.
     * 
     * LOGIC:
     * - If no heartbeat ever recorded → unhealthy
     * - If (current time - last heartbeat) > threshold → unhealthy
     * - Otherwise → healthy
     * 
     * @param thresholdMs Maximum allowed time since last heartbeat
     * @return true if service appears healthy, false if recovery is needed
     */
    public boolean isServiceHealthy(long thresholdMs) {
        long lastHeartbeat = getLastHeartbeatTime();
        
        // No heartbeat ever recorded
        if (lastHeartbeat == 0) {
            Log.d(TAG, "Health check: No heartbeat ever recorded");
            return false;
        }
        
        long now = System.currentTimeMillis();
        long timeSinceHeartbeat = now - lastHeartbeat;
        
        boolean healthy = timeSinceHeartbeat < thresholdMs;
        
        Log.d(TAG, "Health check: lastHeartbeat=" + lastHeartbeat + 
              ", timeSince=" + timeSinceHeartbeat + "ms" +
              ", threshold=" + thresholdMs + "ms" +
              ", healthy=" + healthy);
        
        return healthy;
    }
    
    /**
     * Check service health using the default threshold (10 minutes).
     */
    public boolean isServiceHealthy() {
        return isServiceHealthy(DEFAULT_HEALTH_THRESHOLD_MS);
    }
    
    /**
     * Get time since last heartbeat in milliseconds.
     * @return Time in ms, or -1 if no heartbeat ever recorded
     */
    public long getTimeSinceLastHeartbeat() {
        long lastHeartbeat = getLastHeartbeatTime();
        if (lastHeartbeat == 0) {
            return -1;
        }
        return System.currentTimeMillis() - lastHeartbeat;
    }
    
    /**
     * Get comprehensive heartbeat status for Flutter UI.
     * Returns a Map with all relevant status information.
     */
    public Map<String, Object> getHeartbeatStatus() {
        Map<String, Object> status = new HashMap<>();
        
        long lastHeartbeat = getLastHeartbeatTime();
        long serviceStartTime = getServiceStartTime();
        long heartbeatCount = getHeartbeatCount();
        long timeSinceHeartbeat = getTimeSinceLastHeartbeat();
        boolean isHealthy = isServiceHealthy();
        
        status.put("lastHeartbeatTime", lastHeartbeat);
        status.put("serviceStartTime", serviceStartTime);
        status.put("heartbeatCount", heartbeatCount);
        status.put("timeSinceLastHeartbeat", timeSinceHeartbeat);
        status.put("isHealthy", isHealthy);
        status.put("healthThresholdMs", DEFAULT_HEALTH_THRESHOLD_MS);
        status.put("heartbeatIntervalMs", HEARTBEAT_INTERVAL_MS);
        
        // Also include the static running flag for comparison
        status.put("staticServiceRunning", AppBlockerService.isServiceRunning());
        
        return status;
    }
    
    /**
     * Clear all heartbeat data.
     * Used for testing or when explicitly stopping the service.
     */
    public void clearHeartbeatData() {
        prefs.edit().clear().apply();
        Log.d(TAG, "Heartbeat data cleared");
    }
}
