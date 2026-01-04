package com.example.parental_monitor;

import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.work.Constraints;
import androidx.work.ExistingPeriodicWorkPolicy;
import androidx.work.PeriodicWorkRequest;
import androidx.work.WorkManager;
import androidx.work.Worker;
import androidx.work.WorkerParameters;

import java.util.concurrent.TimeUnit;

/**
 * ServiceHealthWorker - WorkManager Worker for periodic service health checks and recovery.
 * 
 * DESIGN RATIONALE:
 * -----------------
 * 1. We use WorkManager instead of JobScheduler/AlarmManager because:
 *    - WorkManager respects Android Doze mode and app standby
 *    - It guarantees execution even if the app is killed
 *    - It handles backward compatibility automatically
 *    - It uses unique work to prevent duplicate recovery attempts
 * 
 * 2. Minimum interval is 15 minutes (Android restriction for periodic work)
 *    - This is acceptable because our heartbeat threshold is 10 minutes
 *    - Worst case: service could be dead for up to 25 minutes before recovery
 * 
 * 3. We ONLY restart the Foreground Service:
 *    - We do NOT launch any Activity
 *    - We do NOT start the Flutter engine
 *    - This respects user expectations and Android policies
 * 
 * HEALTH CHECK LOGIC:
 * -------------------
 * 1. Read last heartbeat timestamp from HeartbeatManager
 * 2. Compare: (currentTime - lastHeartbeat) vs threshold (10 min)
 * 3. If stale → service is dead → restart AppBlockerService
 * 4. Also check the static isServiceRunning() flag as a secondary check
 */
public class ServiceHealthWorker extends Worker {
    private static final String TAG = "ServiceHealthWorker";
    
    // Unique work name - ensures only one health worker is scheduled
    public static final String WORK_NAME = "service_health_worker";
    
    // Work interval: 15 minutes (minimum allowed by WorkManager)
    public static final long WORK_INTERVAL_MINUTES = 15;
    
    public ServiceHealthWorker(
            @NonNull Context context,
            @NonNull WorkerParameters params) {
        super(context, params);
    }
    
    @NonNull
    @Override
    public Result doWork() {
        Log.d(TAG, "ServiceHealthWorker executing health check");
        
        Context context = getApplicationContext();
        HeartbeatManager heartbeatManager = new HeartbeatManager(context);
        
        try {
            // Check 1: Heartbeat-based health detection
            boolean isHealthyByHeartbeat = heartbeatManager.isServiceHealthy();
            
            // Check 2: Static flag (may be inaccurate if process was killed)
            boolean isRunningByFlag = AppBlockerService.isServiceRunning();
            
            Log.d(TAG, "Health check results: " +
                  "heartbeatHealthy=" + isHealthyByHeartbeat + 
                  ", staticFlagRunning=" + isRunningByFlag);
            
            // Primary decision: use heartbeat
            // The static flag can be stale if the process was killed without lifecycle callbacks
            if (!isHealthyByHeartbeat) {
                Log.w(TAG, "Service unhealthy by heartbeat - attempting recovery");
                restartAppBlockerService(context);
            } else if (!isRunningByFlag) {
                // Secondary check: if static flag says not running but heartbeat is healthy,
                // this might indicate a race condition. Log but don't restart.
                Log.w(TAG, "Static flag says stopped but heartbeat is healthy - monitoring");
            } else {
                Log.d(TAG, "Service is healthy - no action needed");
            }
            
            return Result.success();
            
        } catch (Exception e) {
            Log.e(TAG, "Error during health check: " + e.getMessage(), e);
            // Return success anyway to prevent retry flooding
            return Result.success();
        }
    }
    
    /**
     * Restart the AppBlockerService.
     * This starts ONLY the foreground service - no Activity, no Flutter UI.
     */
    private void restartAppBlockerService(Context context) {
        try {
            Log.d(TAG, "Attempting to restart AppBlockerService");
            
            Intent serviceIntent = new Intent(context, AppBlockerService.class);
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // For Android 8.0+, must use startForegroundService
                context.startForegroundService(serviceIntent);
            } else {
                context.startService(serviceIntent);
            }
            
            Log.d(TAG, "AppBlockerService restart initiated");
            
        } catch (Exception e) {
            Log.e(TAG, "Failed to restart AppBlockerService: " + e.getMessage(), e);
        }
    }
    
    /**
     * Schedule the health worker to run periodically.
     * Uses ExistingPeriodicWorkPolicy.KEEP to prevent duplicates.
     * 
     * Call this:
     * - On app launch
     * - After device boot (from ServiceRestartReceiver)
     * - When user explicitly starts the blocker service
     */
    public static void scheduleHealthWorker(Context context) {
        Log.d(TAG, "Scheduling health worker");
        
        try {
            // Build constraints - we want this to run regardless of conditions
            // since it's critical for service reliability
            Constraints constraints = new Constraints.Builder()
                    .setRequiresBatteryNotLow(false)
                    .setRequiresCharging(false)
                    .setRequiresDeviceIdle(false)
                    .build();
            
            // Create periodic work request
            // Minimum interval is 15 minutes as per Android WorkManager
            PeriodicWorkRequest healthWorkRequest = new PeriodicWorkRequest.Builder(
                    ServiceHealthWorker.class,
                    WORK_INTERVAL_MINUTES,
                    TimeUnit.MINUTES)
                    .setConstraints(constraints)
                    .build();
            
            // Enqueue with KEEP policy - if work already exists, keep it
            // This prevents duplicate workers from being scheduled
            WorkManager.getInstance(context)
                    .enqueueUniquePeriodicWork(
                            WORK_NAME,
                            ExistingPeriodicWorkPolicy.KEEP,
                            healthWorkRequest);
            
            Log.d(TAG, "Health worker scheduled with " + WORK_INTERVAL_MINUTES + " min interval");
            
        } catch (Exception e) {
            Log.e(TAG, "Failed to schedule health worker: " + e.getMessage(), e);
        }
    }
    
    /**
     * Cancel the scheduled health worker.
     * Call this when the blocker service is explicitly stopped by the user.
     */
    public static void cancelHealthWorker(Context context) {
        try {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME);
            Log.d(TAG, "Health worker cancelled");
        } catch (Exception e) {
            Log.e(TAG, "Failed to cancel health worker: " + e.getMessage(), e);
        }
    }
    
    /**
     * Run an immediate health check (one-time).
     * Useful for checking health on app launch or boot.
     */
    public static void runImmediateHealthCheck(Context context) {
        Log.d(TAG, "Running immediate health check");
        
        HeartbeatManager heartbeatManager = new HeartbeatManager(context);
        boolean isHealthy = heartbeatManager.isServiceHealthy();
        boolean isRunning = AppBlockerService.isServiceRunning();
        
        Log.d(TAG, "Immediate check: heartbeatHealthy=" + isHealthy + ", running=" + isRunning);
        
        if (!isHealthy || !isRunning) {
            Log.w(TAG, "Service needs recovery - restarting");
            
            try {
                Intent serviceIntent = new Intent(context, AppBlockerService.class);
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent);
                } else {
                    context.startService(serviceIntent);
                }
            } catch (Exception e) {
                Log.e(TAG, "Failed to start service: " + e.getMessage(), e);
            }
        }
    }
}
