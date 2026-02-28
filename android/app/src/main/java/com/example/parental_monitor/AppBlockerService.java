package com.example.parental_monitor;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.app.usage.UsageEvents;
import android.app.usage.UsageStatsManager;
import android.content.Context;
import android.content.Intent;
import android.graphics.PixelFormat;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.provider.Settings;
import android.util.Log;
import android.view.Gravity;
import android.view.WindowManager;

import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;
import java.util.Set;

/**
 * Foreground service that monitors running apps and shows a blocking overlay
 * when a blocked app is detected in the foreground.
 */
public class AppBlockerService extends Service {
    private static final String TAG = "AppBlockerService";
    private static final String CHANNEL_ID = "app_blocker_channel";
    private static final int NOTIFICATION_ID = 2001;
    private static final long CHECK_INTERVAL_MS = 100; // Check every 100ms for strict blocking
    
    // Heartbeat mechanism: record heartbeat every 3 minutes (180 seconds)
    // This is used by ServiceHealthWorker to detect if the service is still alive
    private static final long HEARTBEAT_INTERVAL_MS = HeartbeatManager.HEARTBEAT_INTERVAL_MS;

    private Handler handler;
    private Runnable checkRunnable;
    private WindowManager windowManager;
    private BlockOverlayView overlayView;
    private boolean isOverlayShowing = false;
    private String currentBlockedApp = null;

    // Blocked apps list (package names)
    private static Set<String> blockedApps = new HashSet<>();
    private static AppBlockerService instance;
    private static boolean isServiceRunning = false;
    
    // Heartbeat tracking
    private HeartbeatManager heartbeatManager;
    private AtomicLong lastHeartbeatUpdate = new AtomicLong(0);

    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
        isServiceRunning = true;
        handler = new Handler(Looper.getMainLooper());
        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        
        // Initialize heartbeat manager and record service start
        heartbeatManager = new HeartbeatManager(this);
        heartbeatManager.recordServiceStart();
        lastHeartbeatUpdate.set(System.currentTimeMillis());

        Log.d(TAG, "AppBlockerService created with heartbeat initialized");
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Log.d(TAG, "AppBlockerService started");

        createNotificationChannel();
        startForeground(NOTIFICATION_ID, createNotification());

        // Start monitoring
        startMonitoring();
        
        // Schedule the health worker to monitor this service
        // The worker will restart us if we stop unexpectedly
        ServiceHealthWorker.scheduleHealthWorker(this);
        
        // Record heartbeat immediately on start
        if (heartbeatManager != null) {
            heartbeatManager.recordHeartbeat();
        }

        // Return START_STICKY to ensure the service is restarted if killed
        // Also provide a restart intent
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        Log.d(TAG, "AppBlockerService destroyed");

        isServiceRunning = false;
        stopMonitoring();
        hideOverlay();
        instance = null;

        // Schedule restart using AlarmManager (more reliable than broadcasts)
        scheduleRestart();
    }

    @Override
    public void onTaskRemoved(Intent rootIntent) {
        super.onTaskRemoved(rootIntent);
        Log.d(TAG, "Task removed - scheduling restart");
        scheduleRestart();
    }

    /**
     * Schedule a restart of this service using AlarmManager
     * This is more reliable than broadcasts on Android 8+
     */
    private void scheduleRestart() {
        try {
            Intent restartIntent = new Intent(this, ServiceRestartReceiver.class);
            restartIntent.setAction(ServiceRestartReceiver.ACTION_RESTART_SERVICE);

            int flags = PendingIntent.FLAG_ONE_SHOT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                flags |= PendingIntent.FLAG_IMMUTABLE;
            }

            PendingIntent pendingIntent = PendingIntent.getBroadcast(
                    this, 0, restartIntent, flags);

            AlarmManager alarmManager = (AlarmManager) getSystemService(Context.ALARM_SERVICE);
            if (alarmManager != null) {
                long triggerTime = System.currentTimeMillis() + 1000; // Restart in 1 second

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP, triggerTime, pendingIntent);
                } else {
                    alarmManager.setExact(
                            AlarmManager.RTC_WAKEUP, triggerTime, pendingIntent);
                }
                Log.d(TAG, "Restart scheduled via AlarmManager");
            }
        } catch (Exception e) {
            Log.e(TAG, "Error scheduling restart: " + e.getMessage(), e);
        }
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    /**
     * Check if the service is currently running
     */
    public static boolean isServiceRunning() {
        return isServiceRunning;
    }

    /**
     * Update the list of blocked apps
     */
    public static void setBlockedApps(List<String> apps) {
        blockedApps.clear();
        if (apps != null) {
            blockedApps.addAll(apps);
        }
        Log.d(TAG, "Blocked apps updated: " + blockedApps);

        // If an overlay is showing but the app is no longer blocked, hide it
        if (instance != null && instance.isOverlayShowing && instance.currentBlockedApp != null) {
            if (!blockedApps.contains(instance.currentBlockedApp)) {
                instance.hideOverlay();
            }
        }
        
        // Immediately check if the current foreground app needs to be blocked
        if (instance != null && instance.handler != null) {
            instance.handler.post(() -> instance.checkForegroundApp());
        }
    }

    /**
     * Get the list of blocked apps
     */
    public static List<String> getBlockedApps() {
        return new ArrayList<>(blockedApps);
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID,
                    "App Blocker",
                    NotificationManager.IMPORTANCE_LOW);
            channel.setDescription("Monitors and blocks restricted apps");

            NotificationManager manager = getSystemService(NotificationManager.class);
            if (manager != null) {
                manager.createNotificationChannel(channel);
            }
        }
    }

    private Notification createNotification() {
        NotificationCompat.Builder builder = new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("Parental Monitor")
                .setContentText("App blocking active")
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setOngoing(true);

        return builder.build();
    }

    private void startMonitoring() {
        checkRunnable = new Runnable() {
            @Override
            public void run() {
                checkForegroundApp();
                
                // Update heartbeat periodically (every 3 minutes)
                // This proves to the health worker that we're still alive
                long now = System.currentTimeMillis();
                long lastUpdate = lastHeartbeatUpdate.get();
                if (now - lastUpdate >= HEARTBEAT_INTERVAL_MS) {
                    if (heartbeatManager != null) {
                        heartbeatManager.recordHeartbeat();
                        lastHeartbeatUpdate.set(now);
                    }
                }
                
                handler.postDelayed(this, CHECK_INTERVAL_MS);
            }
        };
        handler.post(checkRunnable);
        Log.d(TAG, "Started monitoring foreground apps with heartbeat");
    }

    private void stopMonitoring() {
        if (checkRunnable != null) {
            handler.removeCallbacks(checkRunnable);
            checkRunnable = null;
        }
        Log.d(TAG, "Stopped monitoring foreground apps");
    }

    private void checkForegroundApp() {
        if (blockedApps.isEmpty()) {
            if (isOverlayShowing) {
                hideOverlay();
            }
            return;
        }

        String foregroundApp = getForegroundApp();
        if (foregroundApp == null) {
            return;
        }

        // Don't block our own app
        if (foregroundApp.equals(getPackageName())) {
            if (isOverlayShowing) {
                hideOverlay();
            }
            return;
        }

        // Check if the foreground app is blocked
        if (blockedApps.contains(foregroundApp)) {
            if (!isOverlayShowing || !foregroundApp.equals(currentBlockedApp)) {
                Log.d(TAG, "Blocked app detected: " + foregroundApp);
                showOverlay(foregroundApp);
            }
        } else {
            if (isOverlayShowing) {
                hideOverlay();
            }
        }
    }

    private String lastForegroundApp = null;

    private String getForegroundApp() {
        UsageStatsManager usageStatsManager = (UsageStatsManager) getSystemService(Context.USAGE_STATS_SERVICE);
        if (usageStatsManager == null) {
            return lastForegroundApp;
        }

        long now = System.currentTimeMillis();
        // Increase query window significantly if we don't have a recent app, otherwise look back 10s
        long queryWindow = (lastForegroundApp == null) ? (1000 * 60 * 60) : 10000;
        UsageEvents events = usageStatsManager.queryEvents(now - queryWindow, now);

        String foregroundApp = null;
        boolean hasEvents = false;
        UsageEvents.Event event = new UsageEvents.Event();

        while (events.hasNextEvent()) {
            hasEvents = true;
            events.getNextEvent(event);
            if (event.getEventType() == UsageEvents.Event.ACTIVITY_RESUMED) {
                foregroundApp = event.getPackageName();
            } else if (event.getEventType() == UsageEvents.Event.ACTIVITY_PAUSED ||
                       event.getEventType() == UsageEvents.Event.ACTIVITY_STOPPED) {
                if (event.getPackageName().equals(foregroundApp)) {
                    foregroundApp = null;
                }
            }
        }

        if (hasEvents) {
            lastForegroundApp = foregroundApp;
        }

        return lastForegroundApp;
    }

    private void showOverlay(String packageName) {
        if (!Settings.canDrawOverlays(this)) {
            Log.w(TAG, "Cannot draw overlays - permission not granted");
            return;
        }

        // Hide existing overlay first
        hideOverlay();

        try {
            overlayView = new BlockOverlayView(this, packageName, () -> {
                goToHome();
            });

            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.MATCH_PARENT,
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                            ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                            : WindowManager.LayoutParams.TYPE_PHONE,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                            | WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                            | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                    PixelFormat.TRANSLUCENT);
            params.gravity = Gravity.TOP | Gravity.START;

            // Make it touchable for the button
            params.flags &= ~WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE;

            windowManager.addView(overlayView, params);
            isOverlayShowing = true;
            currentBlockedApp = packageName;

            Log.d(TAG, "Overlay shown for: " + packageName);
        } catch (Exception e) {
            Log.e(TAG, "Error showing overlay: " + e.getMessage());
        }
    }

    private void hideOverlay() {
        if (overlayView != null && isOverlayShowing) {
            try {
                windowManager.removeView(overlayView);
            } catch (Exception e) {
                Log.e(TAG, "Error hiding overlay: " + e.getMessage());
            }
            overlayView = null;
            isOverlayShowing = false;
            currentBlockedApp = null;
            Log.d(TAG, "Overlay hidden");
        }
    }

    private void goToHome() {
        hideOverlay();

        Intent homeIntent = new Intent(Intent.ACTION_MAIN);
        homeIntent.addCategory(Intent.CATEGORY_HOME);
        homeIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        startActivity(homeIntent);
    }

    /**
     * Static method to go to home screen
     */
    public static void goToHomeScreen(Context context) {
        if (instance != null) {
            instance.goToHome();
        } else {
            Intent homeIntent = new Intent(Intent.ACTION_MAIN);
            homeIntent.addCategory(Intent.CATEGORY_HOME);
            homeIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(homeIntent);
        }
    }
}
