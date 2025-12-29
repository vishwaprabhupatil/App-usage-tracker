import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';

import 'app_groups.dart';

/// App usage entry with real icon.
class AppUsage {
  final String id;
  final String packageName;
  final String appName;
  final Duration duration;
  final Uint8List? iconBytes;
  final List<String> contributingPackages;

  AppUsage({
    required this.id,
    required this.packageName,
    required this.appName,
    required this.duration,
    this.iconBytes,
    this.contributingPackages = const [],
  });

  bool get hasIcon => iconBytes != null && iconBytes!.isNotEmpty;

  @override
  String toString() => 'AppUsage($appName: ${duration.inMinutes}m, hasIcon=$hasIcon)';
}

/// Service for fetching screen time data using usage_stats package (pure Dart).
/// Uses queryEvents() for precise time calculation (like Digital Wellbeing).
class UsageService {

  /// Fetches today's app usage using queryEvents() for precise calculation.
  /// This matches how Digital Wellbeing calculates screen time.
  static Future<List<AppUsage>> getTodayUsage() async {
    if (!Platform.isAndroid) {
      debugPrint('UsageService: Not Android');
      return [];
    }

    try {
      debugPrint('UsageService: Fetching usage with queryEvents()...');
      
      // Get today's time range (midnight to now)
      final DateTime now = DateTime.now();
      final DateTime startOfDay = DateTime(now.year, now.month, now.day);
      
      // Query events for precise calculation
      final List<EventUsageInfo> events = await UsageStats.queryEvents(
        startOfDay,
        now,
      );
      
      if (events.isEmpty) {
        debugPrint('UsageService: No events returned');
        return [];
      }

      debugPrint('UsageService: Got ${events.length} events');

      // Calculate foreground time from events
      final Map<String, int> lastResumeTime = {};
      final Map<String, int> totalForegroundTime = {};
      
      // Packages to skip completely (system services + launchers + this app)
      final skipPackages = {
        // System
        'android',
        'com.android.systemui',
        'com.google.android.gms',
        'com.google.android.gsf',
        'com.samsung.android.providers.media',
        'com.android.providers.media',
        'com.android.vending',
        // Launchers - exclude from total time like Digital Wellbeing
        'com.sec.android.app.launcher',        // Samsung One UI Home
        'com.google.android.apps.nexuslauncher', // Pixel Launcher
        'com.miui.home',                        // MIUI Launcher
        'com.oppo.launcher',                    // OPPO Launcher
        // Digital Wellbeing apps - exclude
        'com.samsung.android.forest',           // Samsung Digital Wellbeing
        'com.google.android.apps.wellbeing',    // Google Digital Wellbeing
        // This app
        'com.example.parental_monitor',
        // Phone/Call apps - exclude like Digital Wellbeing
        'com.samsung.android.dialer',           // Samsung Phone
        'com.samsung.android.incallui',         // Samsung In-call UI
        'com.google.android.dialer',            // Google Phone
        'com.android.dialer',                   // Stock Dialer
        'com.android.incallui',                 // Stock In-call UI
        'com.android.phone',                    // Phone process
      };

      // Sort events by timestamp
      events.sort((a, b) {
        final timeA = int.tryParse(a.timeStamp ?? '0') ?? 0;
        final timeB = int.tryParse(b.timeStamp ?? '0') ?? 0;
        return timeA.compareTo(timeB);
      });

      for (final event in events) {
        final String pkg = event.packageName ?? '';
        if (pkg.isEmpty) continue;
        if (skipPackages.contains(pkg)) continue;
        if (pkg.contains('.providers.')) continue;
        
        final int timestamp = int.tryParse(event.timeStamp ?? '0') ?? 0;
        final int eventType = int.tryParse(event.eventType ?? '0') ?? 0;
        
        // Event type 1 = ACTIVITY_RESUMED (foreground)
        // Event type 2 = ACTIVITY_PAUSED (background)
        if (eventType == 1) {
          lastResumeTime[pkg] = timestamp;
        } else if (eventType == 2) {
          final int? resumeTime = lastResumeTime[pkg];
          if (resumeTime != null && resumeTime > 0) {
            final int duration = timestamp - resumeTime;
            if (duration > 0) {
              totalForegroundTime[pkg] = (totalForegroundTime[pkg] ?? 0) + duration;
            }
            lastResumeTime[pkg] = 0;
          }
        }
      }
      
      // Handle apps still in foreground
      final int nowMs = now.millisecondsSinceEpoch;
      for (final entry in lastResumeTime.entries) {
        if (entry.value > 0) {
          final int duration = nowMs - entry.value;
          if (duration > 0) {
            totalForegroundTime[entry.key] = (totalForegroundTime[entry.key] ?? 0) + duration;
          }
        }
      }

      debugPrint('UsageService: Calculated foreground time for ${totalForegroundTime.length} packages');

      // Group by logical app
      final Map<String, _GroupedApp> grouped = {};
      
      for (final entry in totalForegroundTime.entries) {
        final String pkg = entry.key;
        final int durationMs = entry.value;
        
        if (durationMs <= 0) continue;

        final AppGroup? group = AppGroupRegistry.findGroup(pkg);
        final String groupId = group?.id ?? pkg;
        final String displayName = group?.displayName ?? '';
        final String? primaryPackage = group?.primaryPackage;

        if (grouped.containsKey(groupId)) {
          grouped[groupId]!.durationMs += durationMs;
          if (!grouped[groupId]!.packages.contains(pkg)) {
            grouped[groupId]!.packages.add(pkg);
          }
        } else {
          grouped[groupId] = _GroupedApp(
            groupId: groupId,
            displayName: displayName,
            nativeName: '',
            durationMs: durationMs,
            iconBytes: null,
            packages: [pkg],
            primaryPackage: primaryPackage ?? pkg,
          );
        }
      }

      debugPrint('UsageService: Grouped into ${grouped.length} apps');

      // Build app list with icons using installed_apps package
      final List<AppUsage> apps = [];
      int withIcons = 0;

      // Minimum 1 minute filter (60000 ms)
      const int minDurationMs = 60000;

      for (final g in grouped.values) {
        if (g.durationMs < minDurationMs) continue;

        String finalName = g.displayName;
        Uint8List? iconBytes;

        // Try to get app info using installed_apps package
        final packagesToTry = [g.primaryPackage, ...g.packages].whereType<String>().toSet();
        
        for (final tryPkg in packagesToTry) {
          try {
            final AppInfo? appInfo = await InstalledApps.getAppInfo(tryPkg);
            
            if (appInfo != null) {
              if (finalName.isEmpty) {
                finalName = appInfo.name ?? '';
              }
              if (iconBytes == null && appInfo.icon != null) {
                iconBytes = appInfo.icon;
              }
              if (iconBytes != null) break;
            }
          } catch (e) {
            debugPrint('UsageService: installed_apps failed for $tryPkg: $e');
          }
        }

        // Fallback name
        if (finalName.isEmpty) {
          finalName = _prettifyPackageName(g.groupId);
        }

        if (iconBytes != null && iconBytes.isNotEmpty) {
          withIcons++;
        }

        apps.add(AppUsage(
          id: g.groupId,
          packageName: g.packages.first,
          appName: finalName,
          duration: Duration(milliseconds: g.durationMs),
          iconBytes: iconBytes,
          contributingPackages: g.packages,
        ));
      }

      // Sort by duration descending
      apps.sort((a, b) => b.duration.compareTo(a.duration));

      debugPrint('UsageService: RESULT: ${apps.length} apps, $withIcons with icons');
      
      // Log first 5
      for (var i = 0; i < apps.length && i < 5; i++) {
        debugPrint('  ${apps[i].appName}: ${apps[i].duration.inMinutes}m, icon=${apps[i].hasIcon}');
      }

      return apps;

    } catch (e, stack) {
      debugPrint('UsageService: Error - $e\n$stack');
      return [];
    }
  }

  static String _prettifyPackageName(String packageName) {
    final parts = packageName.split('.');
    final meaningful = parts
        .where((p) => !['com', 'org', 'net', 'android', 'app', 'apps', 'sec', 'google'].contains(p))
        .toList();
    if (meaningful.isNotEmpty) {
      final name = meaningful.last;
      return name[0].toUpperCase() + name.substring(1);
    }
    return parts.isNotEmpty ? parts.last : packageName;
  }

  static Future<Duration> getTodayScreenTime() async {
    final apps = await getTodayUsage();
    int totalMs = 0;
    for (final app in apps) {
      totalMs += app.duration.inMilliseconds;
    }
    return Duration(milliseconds: totalMs);
  }

  /// Check if usage permission is granted
  static Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? isGranted = await UsageStats.checkUsagePermission();
      return isGranted ?? false;
    } catch (e) {
      debugPrint('UsageService: Permission check failed - $e');
      return false;
    }
  }

  /// Open usage access settings
  static Future<void> openUsageSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await UsageStats.grantUsagePermission();
    } catch (e) {
      debugPrint('UsageService: Open settings failed - $e');
    }
  }
}

class _GroupedApp {
  final String groupId;
  final String displayName;
  final String nativeName;
  int durationMs;
  Uint8List? iconBytes;
  final List<String> packages;
  String? primaryPackage;

  _GroupedApp({
    required this.groupId,
    required this.displayName,
    required this.nativeName,
    required this.durationMs,
    required this.iconBytes,
    required this.packages,
    this.primaryPackage,
  });
}
