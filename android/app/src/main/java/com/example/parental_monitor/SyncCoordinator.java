package com.example.parental_monitor;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;

/**
 * Centralized coordinator for sync operations and service health tracking.
 * Tracks last sync time and provides utility methods for sync coordination.
 */
public class SyncCoordinator {
    private static final String TAG = "SyncCoordinator";
    private static final String PREFS_NAME = "sync_coordinator_prefs";
    private static final String KEY_LAST_SYNC_TIME = "last_sync_time";
    private static final String KEY_LAST_BLOCKER_CHECK = "last_blocker_check";

    // Sync intervals
    public static final long SYNC_INTERVAL_MS = 5 * 60 * 1000; // 5 minutes for data sync
    public static final long BLOCKER_CHECK_INTERVAL_MS = 15 * 60 * 1000; // 15 minutes for blocker check

    private final SharedPreferences prefs;

    public SyncCoordinator(Context context) {
        prefs = context.getApplicationContext()
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
    }

    /**
     * Get the last successful sync timestamp
     */
    public long getLastSyncTime() {
        return prefs.getLong(KEY_LAST_SYNC_TIME, 0);
    }

    /**
     * Update the last sync timestamp to now
     */
    public void updateLastSyncTime() {
        prefs.edit().putLong(KEY_LAST_SYNC_TIME, System.currentTimeMillis()).apply();
        Log.d(TAG, "Updated last sync time");
    }

    /**
     * Get the last blocker check timestamp
     */
    public long getLastBlockerCheckTime() {
        return prefs.getLong(KEY_LAST_BLOCKER_CHECK, 0);
    }

    /**
     * Update the last blocker check timestamp to now
     */
    public void updateLastBlockerCheckTime() {
        prefs.edit().putLong(KEY_LAST_BLOCKER_CHECK, System.currentTimeMillis()).apply();
        Log.d(TAG, "Updated last blocker check time");
    }

    /**
     * Check if it's time for a data sync (every 30 min)
     */
    public boolean isSyncDue() {
        long lastSync = getLastSyncTime();
        long now = System.currentTimeMillis();
        return (now - lastSync) >= SYNC_INTERVAL_MS;
    }

    /**
     * Check if it's time for a blocker service check (every 15 min)
     */
    public boolean isBlockerCheckDue() {
        long lastCheck = getLastBlockerCheckTime();
        long now = System.currentTimeMillis();
        return (now - lastCheck) >= BLOCKER_CHECK_INTERVAL_MS;
    }

    /**
     * Get time until next sync in milliseconds
     */
    public long getTimeUntilNextSync() {
        long lastSync = getLastSyncTime();
        long now = System.currentTimeMillis();
        long timeSinceSync = now - lastSync;
        return Math.max(0, SYNC_INTERVAL_MS - timeSinceSync);
    }

    /**
     * Get time until next blocker check in milliseconds
     */
    public long getTimeUntilNextBlockerCheck() {
        long lastCheck = getLastBlockerCheckTime();
        long now = System.currentTimeMillis();
        long timeSinceCheck = now - lastCheck;
        return Math.max(0, BLOCKER_CHECK_INTERVAL_MS - timeSinceCheck);
    }
}
