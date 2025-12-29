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
import java.util.List;

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
}
