import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';
import 'screentime_sync_service.dart';
import 'app_blocker_service.dart';

/// Foreground task handler that runs in the background
@pragma('vm:entry-point')
class ScreenTimeSyncTaskHandler extends TaskHandler {
  Timer? _syncTimer;
  static bool _isRunning = false;
  
  /// Check if the foreground task handler is running
  static bool get isRunning => _isRunning;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _isRunning = true;
    debugPrint('ForegroundTask: onStart');
    
    // Initialize Supabase in the isolate
    try {
      await SupabaseConfig.initialize();
    } catch (e) {
      debugPrint('ForegroundTask: Supabase initialization error: $e');
    }
    
    // Start periodic sync (every 5 minutes)
    _startPeriodicSync();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    debugPrint('ForegroundTask: onRepeatEvent at $timestamp');
    _syncScreenTime();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('ForegroundTask: onDestroy');
    _isRunning = false;
    _syncTimer?.cancel();
  }

  @override
  void onReceiveData(Object data) {
    debugPrint('ForegroundTask: Received data: $data');
    if (data == 'syncNow') {
      _syncScreenTime();
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    debugPrint('ForegroundTask: Button pressed: $id');
  }

  @override
  void onNotificationPressed() {
    debugPrint('ForegroundTask: Notification pressed');
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {
    debugPrint('ForegroundTask: Notification dismissed');
  }

  void _startPeriodicSync() {
    // Sync immediately
    _syncScreenTime();
    
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _syncScreenTime();
    });
  }

  Future<void> _syncScreenTime() async {
    try {
      debugPrint('ForegroundTask: Syncing screen time...');
      await FlutterForegroundTask.updateService(
        notificationText: 'Syncing screen time...',
      );

      // We use the already migrated ScreentimeSyncService
      await ScreentimeSyncService.syncNow();

      debugPrint('ForegroundTask: Synced successfully');
      
      final now = DateTime.now();
      final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      await FlutterForegroundTask.updateService(
        notificationText: 'Last sync: $timeStr',
      );

    } catch (e) {
      debugPrint('ForegroundTask: Error syncing - $e');
      await FlutterForegroundTask.updateService(
        notificationText: 'Sync failed: $e',
      );
    }
  }
}

/// Service to manage the foreground task for screen time sync
class ForegroundSyncService {
  static bool _isInitialized = false;

  /// Initialize the foreground task (call once in main.dart)
  static Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'screentime_sync',
        channelName: 'Screen Time Sync',
        channelDescription: 'Syncs screen time data to parent device',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(
          300000, // 5 minutes in milliseconds
        ),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    debugPrint('ForegroundSyncService: Initialized');
  }

  /// Start the foreground service (call after child login)
  static Future<bool> startService() async {
    final notificationPermission = 
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (await FlutterForegroundTask.isRunningService) {
      debugPrint('ForegroundSyncService: Service already running - triggering sync');
      syncNow();
      return true;
    }

    debugPrint('ForegroundSyncService: Starting service...');

    final result = await FlutterForegroundTask.startService(
      notificationTitle: 'Parental Monitor',
      notificationText: 'Syncing screen time...',
      callback: startCallback,
    );
    
    if (result is ServiceRequestSuccess) {
      try {
        await AppBlockerService.startWatchdog();
      } catch (e) {
        debugPrint('ForegroundSyncService: Error starting watchdog: $e');
      }
    }
    
    return result is ServiceRequestSuccess;
  }

  /// Stop the foreground service (call on logout)
  static Future<bool> stopService() async {
    debugPrint('ForegroundSyncService: Stopping service...');
    final result = await FlutterForegroundTask.stopService();
    return result is ServiceRequestSuccess;
  }

  /// Check if the service is running
  static Future<bool> isRunning() async {
    return await FlutterForegroundTask.isRunningService;
  }

  /// Trigger immediate sync
  static void syncNow() {
    FlutterForegroundTask.sendDataToTask('syncNow');
  }

  /// Trigger immediate sync with fallback
  static Future<void> triggerSyncNow() async {
    if (await isRunning()) {
      syncNow();
      return;
    }
    await ScreentimeSyncService.syncNow();
  }
}

/// Callback function for the foreground task
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(ScreenTimeSyncTaskHandler());
}
