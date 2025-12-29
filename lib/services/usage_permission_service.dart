import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:android_intent_plus/android_intent.dart';

/// Service to check and request Usage Stats permission.
///
/// Uses the usage_stats Dart package for permission management.
class UsagePermissionService {

  /// Check if Usage Access is granted
  static Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return false;
    
    try {
      debugPrint('UsagePermissionService: Checking permission...');
      final bool? isGranted = await UsageStats.checkUsagePermission();
      debugPrint('UsagePermissionService: Permission = $isGranted');
      return isGranted ?? false;
    } catch (e) {
      debugPrint('UsagePermissionService: Error checking permission - $e');
      return false;
    }
  }

  /// Open Usage Access settings
  static Future<void> openUsageAccessSettings() async {
    if (!Platform.isAndroid) return;
    
    try {
      debugPrint('UsagePermissionService: Opening settings...');
      // Use usage_stats package method
      await UsageStats.grantUsagePermission();
    } catch (e) {
      debugPrint('UsagePermissionService: Package method failed, using intent - $e');
      // Fallback to android_intent_plus
      const intent = AndroidIntent(
        action: 'android.settings.USAGE_ACCESS_SETTINGS',
      );
      await intent.launch();
    }
  }
}
