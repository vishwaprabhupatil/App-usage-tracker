import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'usage_service.dart';
import 'app_blocker_service.dart';

/// Foreground task handler that runs in the background
@pragma('vm:entry-point')
class ScreenTimeSyncTaskHandler extends TaskHandler {
  Timer? _syncTimer;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('ForegroundTask: onStart');
    
    // Initialize Firebase in the isolate
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('ForegroundTask: Firebase already initialized or error: $e');
    }
    
    // Start periodic sync (every 5 minutes)
    _startPeriodicSync();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // This is called periodically based on the interval set in init
    debugPrint('ForegroundTask: onRepeatEvent at $timestamp');
    _syncScreenTime();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('ForegroundTask: onDestroy');
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
    // Send data to main app to bring it to foreground
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {
    debugPrint('ForegroundTask: Notification dismissed');
  }

  void _startPeriodicSync() {
    // Sync immediately
    _syncScreenTime();
    
    // Then sync every 30 minutes
    _syncTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      _syncScreenTime();
    });
  }

  Future<void> _syncScreenTime() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        debugPrint('ForegroundTask: No user logged in');
        await FlutterForegroundTask.updateService(
          notificationText: 'Not logged in',
        );
        return;
      }

      // Check if child is linked to a parent
      final childDoc = await FirebaseFirestore.instance
          .collection('children')
          .doc(uid)
          .get();

      if (!childDoc.exists || childDoc.data()?['parentId'] == null) {
        debugPrint('ForegroundTask: Not linked to parent');
        await FlutterForegroundTask.updateService(
          notificationText: 'Not linked to parent',
        );
        return;
      }

      debugPrint('ForegroundTask: Syncing screen time...');
      await FlutterForegroundTask.updateService(
        notificationText: 'Syncing screen time...',
      );

      // Get today's usage
      final apps = await UsageService.getTodayUsage();

      // Calculate total time
      Duration total = Duration.zero;
      for (final app in apps) {
        total += app.duration;
      }

      // Format total time
      final totalFormatted = _formatDuration(total);

      // Format apps list with icons as base64
      final appsList = apps.map((app) {
        final Map<String, dynamic> appData = {
          'packageName': app.packageName,
          'appName': app.appName,
          'duration': _formatDuration(app.duration),
        };
        
        // Include icon as base64 if available
        if (app.iconBytes != null && app.iconBytes!.isNotEmpty) {
          appData['icon'] = base64Encode(app.iconBytes!);
        }
        
        return appData;
      }).toList();

      // Upload to Firebase
      await FirebaseFirestore.instance.collection('screentime').doc(uid).set({
        'totalTime': totalFormatted,
        'apps': appsList,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      debugPrint('ForegroundTask: Synced - $totalFormatted, ${apps.length} apps');
      
      // Update notification with last sync time
      final now = DateTime.now();
      final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      await FlutterForegroundTask.updateService(
        notificationText: 'Screen time: $totalFormatted • Last sync: $timeStr',
      );

    } catch (e) {
      debugPrint('ForegroundTask: Error syncing - $e');
      await FlutterForegroundTask.updateService(
        notificationText: 'Sync error - retrying...',
      );
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h == 0 && m == 0) return '<1m';
    if (h == 0) return '${m}m';
    return '${h}h ${m}m';
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
          1800000, // 30 minutes in milliseconds
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
    // Request notification permission for Android 13+
    final notificationPermission = 
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    // Check if service is already running
    if (await FlutterForegroundTask.isRunningService) {
      debugPrint('ForegroundSyncService: Service already running');
      return true;
    }

    debugPrint('ForegroundSyncService: Starting service...');

    final result = await FlutterForegroundTask.startService(
      notificationTitle: 'Parental Monitor',
      notificationText: 'Syncing screen time...',
      callback: startCallback,
    );
    
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
}

/// Callback function for the foreground task
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(ScreenTimeSyncTaskHandler());
}
