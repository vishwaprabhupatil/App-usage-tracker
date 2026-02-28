import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'usage_service.dart';
import 'app_blocker_service.dart';
import 'package_installer_service.dart';
import 'screentime_sync_service.dart';

/// Foreground task handler that runs in the background
@pragma('vm:entry-point')
class ScreenTimeSyncTaskHandler extends TaskHandler {
  Timer? _syncTimer;
  static bool _isRunning = false;
  static const int _maxAppsUpload = 120;
  static const int _maxInstalledAppsUpload = 250;
  static const int _maxUsageIcons = 80;
  static const int _maxInstalledIcons = 250;
  
  /// Check if the foreground task handler is running
  static bool get isRunning => _isRunning;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _isRunning = true;
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
    
    // The periodic sync is handled by the foreground task manager (onRepeatEvent),
    // but we can keep a backup timer if needed. Reducing to 5 minutes to match.
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
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

      final childData = childDoc.data() ?? <String, dynamic>{};
      final parentId =
          (childData['parentId'] ?? childData['parentUid']) as String?;

      if (!childDoc.exists || parentId == null || parentId.isEmpty) {
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
      
      // Get all installed apps (with icons so parent can view them)
      final allInstalledApps = await UsageService.getInstalledAppsMetadata(withIcons: true);

      final usageUpload = apps.take(_maxAppsUpload).toList();
      final installedUpload = allInstalledApps.take(_maxInstalledAppsUpload).toList();

      // Fetch app logo metadata via Android PackageManager / installer info API.
      final metadataPackages = <String>{
        ...usageUpload.take(_maxUsageIcons).map((a) => a.packageName),
        ...installedUpload.take(_maxInstalledIcons).map((a) => a.packageName),
      }.toList();
      final packageMetadata = await PackageInstallerService.getPackageMetadata(
        metadataPackages,
        iconSize: 48,
      );

      // Calculate total time
      Duration total = Duration.zero;
      for (final app in apps) {
        total += app.duration;
      }

      // Format total time
      final totalFormatted = _formatDuration(total);

      // Check for over-limit apps
      final limits = AppBlockerService.appLimits;
      final List<String> overLimitApps = [];

      // Format apps list with icons as base64
      final appsList = usageUpload.map((app) {
        final meta = packageMetadata[app.packageName];
        final Map<String, dynamic> appData = {
          'packageName': app.packageName,
          'appName': (meta != null && meta.appName.isNotEmpty)
              ? meta.appName
              : app.appName,
          'duration': _formatDuration(app.duration),
          'openCount': app.openCount,
        };
        if (meta != null &&
            meta.iconBase64 != null &&
            meta.iconBase64!.isNotEmpty) {
          appData['icon'] = meta.iconBase64;
        } else if (app.iconBytes != null && app.iconBytes!.isNotEmpty) {
          appData['icon'] = base64Encode(app.iconBytes!);
        }

        // Check limits
        final limitMinutes = limits[app.packageName];
        if (limitMinutes != null && app.duration.inMinutes >= limitMinutes) {
          overLimitApps.add(app.packageName);
        }
        
        return appData;
      }).toList();
      
      // Update app blocker service with new over limit apps
      try {
        await AppBlockerService.updateOverLimitApps(overLimitApps);
      } catch (e) {
        debugPrint('ForegroundTask: Error updating over limit apps: $e');
      }
      
      // Format all installed apps list
      final allAppsList = installedUpload.map((app) {
        final meta = packageMetadata[app.packageName];
        final Map<String, dynamic> appData = {
          'packageName': app.packageName,
          'appName': (meta != null && meta.appName.isNotEmpty)
              ? meta.appName
              : app.appName,
        };
        if (meta != null &&
            meta.iconBase64 != null &&
            meta.iconBase64!.isNotEmpty) {
          appData['icon'] = meta.iconBase64;
        } else if (app.iconBytes != null && app.iconBytes!.isNotEmpty) {
          appData['icon'] = base64Encode(app.iconBytes!);
        }
        if (meta != null &&
            meta.installerPackage != null &&
            meta.installerPackage!.isNotEmpty) {
          appData['installerPackage'] = meta.installerPackage;
        }
        return appData;
      }).toList();

      // Upload to Firebase
      final batch = FirebaseFirestore.instance.batch();
      
      // Update screentime info
      final screentimeRef = FirebaseFirestore.instance.collection('screentime').doc(uid);
      batch.set(screentimeRef, {
        'totalTime': totalFormatted,
        'apps': appsList,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      
      // Update installed apps list on the child doc
      final childRef = FirebaseFirestore.instance.collection('children').doc(uid);
      batch.set(childRef, {
        // Backward compatibility: migrate legacy `parentUid` to `parentId`.
        'parentId': parentId,
        'installedApps': allAppsList,
        'appUsageSyncTime': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      // Sync past 7 days of historical data
      final now = DateTime.now();
      final DateTime endHistory = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(seconds: 1)); // End yesterday
      final DateTime startHistory = endHistory
          .subtract(const Duration(days: 29)); // Past 30 days including yesterday
      
      final historyData = await UsageService.getDailyUsageForRange(startHistory, endHistory);
      
      for (final entry in historyData.entries) {
        final dateStr = entry.key; // YYYY-MM-DD
        final dayApps = entry.value;
        
        Duration dayTotal = Duration.zero;
        for (var a in dayApps) {
          dayTotal += a.duration;
        }
        
        final historyRef = screentimeRef.collection('daily').doc(dateStr);
        batch.set(historyRef, {
          'date': dateStr,
          'totalMinutes': dayTotal.inMinutes,
          'apps': dayApps.map((a) => {
            'packageName': a.packageName,
            'appName': a.appName,
            'minutes': a.duration.inMinutes,
            'openCount': a.openCount,
          }).toList(),
        }, SetOptions(merge: true));
      }
      
      // Also save today's provisional data to history for the current day
      final todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final todayRef = screentimeRef.collection('daily').doc(todayStr);
      batch.set(todayRef, {
        'date': todayStr,
        'totalMinutes': total.inMinutes,
        'apps': apps.map((a) => {
          'packageName': a.packageName,
          'appName': a.appName,
          'minutes': a.duration.inMinutes,
          'openCount': a.openCount,
        }).toList(),
      }, SetOptions(merge: true));
      
      await batch.commit();

      debugPrint('ForegroundTask: Synced - $totalFormatted, ${apps.length} apps');
      
      // Update native sync time tracking
      try {
        await AppBlockerService.updateLastSyncTime();
      } catch (e) {
        debugPrint('ForegroundTask: Error updating native sync time: $e');
      }
      
      // Update notification with last sync time
      final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      await FlutterForegroundTask.updateService(
        notificationText: 'Screen time: $totalFormatted • Last sync: $timeStr',
      );

    } catch (e) {
      debugPrint('ForegroundTask: Error syncing - $e');

      // Fallback path: try a lightweight direct sync that writes less data.
      try {
        await ScreentimeSyncService.syncNow();
        await FlutterForegroundTask.updateService(
          notificationText: 'Synced (fallback mode)',
        );
        return;
      } catch (fallbackError) {
        debugPrint('ForegroundTask: Fallback sync failed - $fallbackError');
      }

      await FlutterForegroundTask.updateService(
        notificationText: _shortErrorForNotification(e),
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

  String _shortErrorForNotification(Object error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'Sync blocked by Firestore rules';
        case 'unauthenticated':
          return 'Sync failed: login required';
        case 'resource-exhausted':
        case 'invalid-argument':
          return 'Sync payload too large';
        case 'unavailable':
          return 'Sync failed: network unavailable';
      }
      return 'Sync error (${error.code}) - retrying...';
    }
    return 'Sync error - retrying...';
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
    // Request notification permission for Android 13+
    final notificationPermission = 
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    // Check if service is already running
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
      // Start the watchdog to ensure services stay alive
      try {
        await AppBlockerService.startWatchdog();
      } catch (e) {
        debugPrint('ForegroundSyncService: Error starting watchdog: $e');
      }
      
      // Request battery optimization exemption if not already granted
      final hasExemption = await AppBlockerService.hasBatteryOptimizationExemption();
      if (!hasExemption) {
        debugPrint('ForegroundSyncService: Battery optimization not exempted');
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

  /// Trigger immediate sync with fallback for devices where foreground task
  /// cannot run reliably (permission/OEM restrictions).
  static Future<void> triggerSyncNow() async {
    if (await isRunning()) {
      syncNow();
      return;
    }

    // Fallback path: write directly via Flutter when service is not running.
    await ScreentimeSyncService.syncNow();
  }
}

/// Callback function for the foreground task
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(ScreenTimeSyncTaskHandler());
}
