package com.example.parental_monitor;

import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import android.os.PowerManager;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "com.example.parental_monitor/overlay";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler(
                        (call, result) -> {
                            switch (call.method) {
                                case "checkOverlayPermission":
                                    result.success(checkOverlayPermission());
                                    break;
                                case "requestOverlayPermission":
                                    requestOverlayPermission();
                                    result.success(null);
                                    break;
                                case "startBlockerService":
                                    startBlockerService();
                                    result.success(true);
                                    break;
                                case "stopBlockerService":
                                    stopBlockerService();
                                    result.success(true);
                                    break;
                                case "updateBlockedApps":
                                    List<String> apps = call.argument("apps");
                                    updateBlockedApps(apps);
                                    result.success(true);
                                    break;
                                case "goToHome":
                                    goToHome();
                                    result.success(true);
                                    break;
                                case "checkBatteryOptimization":
                                    result.success(checkBatteryOptimization());
                                    break;
                                case "requestBatteryOptimization":
                                    requestBatteryOptimization();
                                    result.success(null);
                                    break;
                                case "startWatchdog":
                                    startWatchdog();
                                    result.success(true);
                                    break;
                                case "getLastSyncTime":
                                    result.success(getLastSyncTime());
                                    break;
                                case "updateLastSyncTime":
                                    updateLastSyncTime();
                                    result.success(true);
                                    break;
                                case "checkAllServicesStatus":
                                    result.success(checkAllServicesStatus());
                                    break;
                                case "restartAllServices":
                                    restartAllServices();
                                    result.success(true);
                                    break;
                                // ===== NEW HEARTBEAT & RESTRICTION METHODS =====
                                case "getHeartbeatStatus":
                                    result.success(getHeartbeatStatus());
                                    break;
                                case "getRestrictionStatus":
                                    result.success(getRestrictionStatus());
                                    break;
                                case "openBatterySettings":
                                    openBatterySettings();
                                    result.success(true);
                                    break;
                                case "openOemSettings":
                                    openOemSettings();
                                    result.success(true);
                                    break;
                                case "scheduleHealthWorker":
                                    scheduleHealthWorker();
                                    result.success(true);
                                    break;
                                case "runImmediateHealthCheck":
                                    runImmediateHealthCheck();
                                    result.success(true);
                                    break;
                                default:
                                    result.notImplemented();
                                    break;
                            }
                        });
    }

    private boolean checkOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return Settings.canDrawOverlays(this);
        }
        return true;
    }

    private void requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Intent intent = new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:" + getPackageName()));
            startActivity(intent);
        }
    }

    private void startBlockerService() {
        Intent serviceIntent = new Intent(this, AppBlockerService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent);
        } else {
            startService(serviceIntent);
        }
    }

    private void stopBlockerService() {
        Intent serviceIntent = new Intent(this, AppBlockerService.class);
        stopService(serviceIntent);
    }

    private void updateBlockedApps(List<String> apps) {
        AppBlockerService.setBlockedApps(apps != null ? apps : new ArrayList<>());
    }

    private void goToHome() {
        AppBlockerService.goToHomeScreen(this);
    }

    private boolean checkBatteryOptimization() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
            return pm != null && pm.isIgnoringBatteryOptimizations(getPackageName());
        }
        return true;
    }

    private void requestBatteryOptimization() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Intent intent = new Intent();
            intent.setAction(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS);
            intent.setData(Uri.parse("package:" + getPackageName()));
            startActivity(intent);
        }
    }

    private void startWatchdog() {
        ServiceWatchdog.scheduleWatchdog(this);
    }

    /**
     * Get the last sync time in milliseconds since epoch
     */
    private long getLastSyncTime() {
        SyncCoordinator coordinator = new SyncCoordinator(this);
        return coordinator.getLastSyncTime();
    }

    /**
     * Update the last sync time to now
     */
    private void updateLastSyncTime() {
        SyncCoordinator coordinator = new SyncCoordinator(this);
        coordinator.updateLastSyncTime();
    }

    /**
     * Check status of all services and return as a map
     */
    private Map<String, Object> checkAllServicesStatus() {
        Map<String, Object> status = new HashMap<>();

        // AppBlockerService status
        status.put("appBlockerRunning", AppBlockerService.isServiceRunning());

        // Sync info
        SyncCoordinator coordinator = new SyncCoordinator(this);
        status.put("lastSyncTime", coordinator.getLastSyncTime());
        status.put("syncDue", coordinator.isSyncDue());
        status.put("timeUntilNextSync", coordinator.getTimeUntilNextSync());

        return status;
    }

    /**
     * Restart all native services
     */
    private void restartAllServices() {
        // Stop and restart AppBlockerService
        Intent serviceIntent = new Intent(this, AppBlockerService.class);
        stopService(serviceIntent);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent);
        } else {
            startService(serviceIntent);
        }

        // Reschedule watchdog
        ServiceWatchdog.scheduleWatchdog(this);
    }
    
    // ===== NEW HEARTBEAT & RESTRICTION METHODS =====
    
    /**
     * Get comprehensive heartbeat status for Flutter UI
     */
    private Map<String, Object> getHeartbeatStatus() {
        HeartbeatManager heartbeatManager = new HeartbeatManager(this);
        return heartbeatManager.getHeartbeatStatus();
    }
    
    /**
     * Get restriction status (battery optimization, OEM restrictions)
     */
    private Map<String, Object> getRestrictionStatus() {
        RestrictionDetector detector = new RestrictionDetector(this);
        return detector.getRestrictionStatus();
    }
    
    /**
     * Open battery optimization settings
     */
    private void openBatterySettings() {
        RestrictionDetector detector = new RestrictionDetector(this);
        Intent intent = detector.getBatteryOptimizationIntent();
        if (intent != null) {
            startActivity(intent);
        }
    }
    
    /**
     * Open OEM-specific settings (e.g., Samsung battery settings)
     */
    private void openOemSettings() {
        RestrictionDetector detector = new RestrictionDetector(this);
        Intent intent;
        
        if (detector.isSamsungDevice()) {
            intent = detector.getSamsungBatterySettingsIntent();
        } else {
            intent = detector.getAppSettingsIntent();
        }
        
        if (intent != null) {
            startActivity(intent);
        }
    }
    
    /**
     * Schedule the health worker for ongoing service monitoring
     */
    private void scheduleHealthWorker() {
        ServiceHealthWorker.scheduleHealthWorker(this);
    }
    
    /**
     * Run an immediate health check and recover if needed
     */
    private void runImmediateHealthCheck() {
        ServiceHealthWorker.runImmediateHealthCheck(this);
    }
}
