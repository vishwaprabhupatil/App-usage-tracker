package com.example.parental_monitor;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
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
import java.util.Set;

/**
 * Foreground service that monitors running apps and shows a blocking overlay
 * when a blocked app is detected in the foreground.
 */
public class AppBlockerService extends Service {
    private static final String TAG = "AppBlockerService";
    private static final String CHANNEL_ID = "app_blocker_channel";
    private static final int NOTIFICATION_ID = 2001;
    private static final long CHECK_INTERVAL_MS = 500; // Check every 500ms

    private Handler handler;
    private Runnable checkRunnable;
    private WindowManager windowManager;
    private BlockOverlayView overlayView;
    private boolean isOverlayShowing = false;
    private String currentBlockedApp = null;

    // Blocked apps list (package names)
    private static Set<String> blockedApps = new HashSet<>();
    private static AppBlockerService instance;

    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
        handler = new Handler(Looper.getMainLooper());
        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);

        Log.d(TAG, "AppBlockerService created");
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Log.d(TAG, "AppBlockerService started");

        createNotificationChannel();
        startForeground(NOTIFICATION_ID, createNotification());

        // Start monitoring
        startMonitoring();

        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        Log.d(TAG, "AppBlockerService destroyed");

        stopMonitoring();
        hideOverlay();
        instance = null;
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
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
                handler.postDelayed(this, CHECK_INTERVAL_MS);
            }
        };
        handler.post(checkRunnable);
        Log.d(TAG, "Started monitoring foreground apps");
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

    private String getForegroundApp() {
        UsageStatsManager usageStatsManager = (UsageStatsManager) getSystemService(Context.USAGE_STATS_SERVICE);
        if (usageStatsManager == null) {
            return null;
        }

        long now = System.currentTimeMillis();
        UsageEvents events = usageStatsManager.queryEvents(now - 5000, now);

        String foregroundApp = null;
        UsageEvents.Event event = new UsageEvents.Event();

        while (events.hasNextEvent()) {
            events.getNextEvent(event);
            if (event.getEventType() == UsageEvents.Event.ACTIVITY_RESUMED) {
                foregroundApp = event.getPackageName();
            }
        }

        return foregroundApp;
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
