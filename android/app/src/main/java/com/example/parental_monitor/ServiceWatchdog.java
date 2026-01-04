package com.example.parental_monitor;

import android.app.job.JobInfo;
import android.app.job.JobParameters;
import android.app.job.JobScheduler;
import android.app.job.JobService;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.util.Log;

import androidx.annotation.RequiresApi;

/**
 * JobService that periodically checks if our foreground services are running.
 * If they're not running, it restarts them.
 * 
 * Schedule:
 * - Blocker check: Every 15 minutes
 * - Data sync trigger: Every 30 minutes
 * 
 * This provides an additional layer of reliability for keeping services alive.
 */
@RequiresApi(api = Build.VERSION_CODES.LOLLIPOP)
public class ServiceWatchdog extends JobService {
    private static final String TAG = "ServiceWatchdog";
    private static final int JOB_ID = 1001;
    // Run every 15 minutes (blocker check interval)
    private static final long CHECK_INTERVAL_MS = 15 * 60 * 1000;

    @Override
    public boolean onStartJob(JobParameters params) {
        Log.d(TAG, "Watchdog job started - checking services");

        // Run the check in a background thread
        new Thread(() -> {
            try {
                checkAndRestartServices();
            } catch (Exception e) {
                Log.e(TAG, "Error in watchdog: " + e.getMessage(), e);
            } finally {
                // Reschedule the job
                scheduleWatchdog(this);
                // Job finished
                jobFinished(params, false);
            }
        }).start();

        // Return true because we're handling this asynchronously
        return true;
    }

    @Override
    public boolean onStopJob(JobParameters params) {
        Log.d(TAG, "Watchdog job stopped");
        // Return true to reschedule
        return true;
    }

    /**
     * Check if services are running and restart them if needed.
     * Also updates sync coordinator timestamps.
     */
    private void checkAndRestartServices() {
        Context context = getApplicationContext();
        SyncCoordinator syncCoordinator = new SyncCoordinator(context);

        // Always check AppBlockerService (every 15 min)
        boolean isAppBlockerRunning = AppBlockerService.isServiceRunning();
        Log.d(TAG, "AppBlockerService running: " + isAppBlockerRunning);

        if (!isAppBlockerRunning) {
            Log.d(TAG, "AppBlockerService not running - restarting");
            restartAppBlockerService(context);
        }

        // Update blocker check time
        syncCoordinator.updateLastBlockerCheckTime();

        // Check if sync is due (every 30 min)
        boolean syncDue = syncCoordinator.isSyncDue();
        Log.d(TAG, "Sync due: " + syncDue);

        // Mark sync time for tracking purposes
        // NOTE: We do NOT launch the Flutter app to avoid unexpected app restarts.
        // The Flutter foreground service will sync when the user opens the app.
        if (syncDue) {
            syncCoordinator.updateLastSyncTime();
            Log.d(TAG, "Sync time updated (Flutter will sync when app is opened)");
        }
    }

    /**
     * Start the AppBlockerService
     */
    private void restartAppBlockerService(Context context) {
        try {
            Intent serviceIntent = new Intent(context, AppBlockerService.class);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent);
            } else {
                context.startService(serviceIntent);
            }
            Log.d(TAG, "AppBlockerService restarted");
        } catch (Exception e) {
            Log.e(TAG, "Error restarting AppBlockerService: " + e.getMessage(), e);
        }
    }

    /**
     * Schedule the watchdog job to run periodically (every 15 minutes)
     */
    public static void scheduleWatchdog(Context context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            Log.d(TAG, "JobScheduler not available on this Android version");
            return;
        }

        JobScheduler jobScheduler = (JobScheduler) context.getSystemService(Context.JOB_SCHEDULER_SERVICE);
        if (jobScheduler == null) {
            Log.e(TAG, "JobScheduler not available");
            return;
        }

        ComponentName componentName = new ComponentName(context, ServiceWatchdog.class);
        JobInfo.Builder builder = new JobInfo.Builder(JOB_ID, componentName);

        // Set periodic execution (every 15 minutes)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            // For Android 7.0+, use setPeriodic with flex
            builder.setPeriodic(CHECK_INTERVAL_MS, JobInfo.getMinFlexMillis());
        } else {
            // For older versions, use simple periodic
            builder.setPeriodic(CHECK_INTERVAL_MS);
        }

        // Set constraints - we want this to run regardless of conditions
        builder.setRequiresCharging(false);
        builder.setRequiresDeviceIdle(false);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder.setRequiresBatteryNotLow(false);
            builder.setRequiresStorageNotLow(false);
        }

        // Persist across reboots
        builder.setPersisted(true);

        int result = jobScheduler.schedule(builder.build());
        if (result == JobScheduler.RESULT_SUCCESS) {
            Log.d(TAG, "Watchdog job scheduled successfully (15 min interval)");
        } else {
            Log.e(TAG, "Failed to schedule watchdog job");
        }
    }

    /**
     * Cancel the watchdog job
     */
    public static void cancelWatchdog(Context context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            return;
        }

        JobScheduler jobScheduler = (JobScheduler) context.getSystemService(Context.JOB_SCHEDULER_SERVICE);
        if (jobScheduler != null) {
            jobScheduler.cancel(JOB_ID);
            Log.d(TAG, "Watchdog job cancelled");
        }
    }
}
