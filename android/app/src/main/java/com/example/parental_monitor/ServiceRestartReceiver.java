package com.example.parental_monitor;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

/**
 * Broadcast receiver that handles service restart events.
 * Listens for:
 * - BOOT_COMPLETED: Restart services after device reboot
 * - Custom restart action: Restart services when they're killed
 */
public class ServiceRestartReceiver extends BroadcastReceiver {
    private static final String TAG = "ServiceRestartReceiver";
    public static final String ACTION_RESTART_SERVICE = "com.example.parental_monitor.RESTART_SERVICE";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null) {
            return;
        }

        String action = intent.getAction();
        Log.d(TAG, "Received broadcast: " + action);

        if (Intent.ACTION_BOOT_COMPLETED.equals(action)) {
            Log.d(TAG, "Device booted - scheduling service restart");
            // Delay start after boot to let system stabilize
            restartServicesWithDelay(context, 5000);
        } else if (ACTION_RESTART_SERVICE.equals(action)) {
            Log.d(TAG, "Service restart requested");
            // Small delay to ensure clean restart
            restartServicesWithDelay(context, 500);
        }
    }

    /**
     * Restart services after a delay
     */
    private void restartServicesWithDelay(Context context, int delayMs) {
        final Context appContext = context.getApplicationContext();
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            restartServices(appContext);
        }, delayMs);
    }

    /**
     * Restart services based on heartbeat health check (not static flag).
     * Uses HeartbeatManager to determine if service is actually dead.
     */
    private void restartServices(Context context) {
        try {
            // Use heartbeat-based health detection instead of static flag
            // Static flags are unreliable after process death
            HeartbeatManager heartbeatManager = new HeartbeatManager(context);
            boolean isHealthy = heartbeatManager.isServiceHealthy();
            boolean isRunningByFlag = AppBlockerService.isServiceRunning();
            
            Log.d(TAG, "Health check: heartbeatHealthy=" + isHealthy + 
                  ", staticFlag=" + isRunningByFlag);
            
            // Restart if heartbeat indicates service is dead
            if (!isHealthy) {
                Log.d(TAG, "Service unhealthy - restarting AppBlockerService");
                Intent serviceIntent = new Intent(context, AppBlockerService.class);
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent);
                } else {
                    context.startService(serviceIntent);
                }
                Log.d(TAG, "Started AppBlockerService");
            } else {
                Log.d(TAG, "Service is healthy - no restart needed");
            }

            // Always schedule the health worker for ongoing monitoring
            // This uses WorkManager which is more reliable than JobScheduler
            ServiceHealthWorker.scheduleHealthWorker(context);
            Log.d(TAG, "Scheduled ServiceHealthWorker for ongoing monitoring");

            // NOTE: We intentionally do NOT launch the Flutter app here
            // to avoid disrupting the user with unexpected app restarts.
            // The Flutter foreground service will resume when the user opens the app.

        } catch (Exception e) {
            Log.e(TAG, "Error restarting services: " + e.getMessage(), e);
        }
    }
}

