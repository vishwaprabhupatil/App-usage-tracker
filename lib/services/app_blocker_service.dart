import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';

/// Service to check and enforce app blocking on the child's device.
/// This service communicates with the native Android AppBlockerService.
class AppBlockerService {
  static const platform = MethodChannel('com.example.parental_monitor/overlay');
  
  static List<String> _blockedApps = [];
  static Map<String, int> _appLimits = {};
  static List<String> _overLimitApps = [];
  static StreamSubscription? _blockedAppsSubscription;
  static bool _isInitialized = false;
  static bool _serviceStarted = false;

  static const String _keyBlockedApps = 'cached_blocked_apps';
  static const String _keyAppLimits = 'cached_app_limits';
  
  /// Initialize the blocker service, load cached rules immediately, and listen to blocked apps
  static Future<void> init() async {
    // Load local cached rules immediately for instant offline/low-speed blocking
    await _loadCachedBlockedApps();

    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) {
      debugPrint('AppBlocker: Current user is null - skipping stream subscription for now');
      return;
    }
    
    if (_isInitialized && _blockedAppsSubscription != null) return;
    _isInitialized = true;
    
    await _blockedAppsSubscription?.cancel();
    
    // Listen to blocked apps changes from Supabase Realtime
    _blockedAppsSubscription = SupabaseConfig.client
        .from('children')
        .stream(primaryKey: ['id'])
        .eq('id', user.id)
        .listen((data) async {
      if (data.isNotEmpty) {
        final childData = data.first;
        
        // Manual Blocks
        final blockedList = childData['blocked_apps'] as List<dynamic>?;
        _blockedApps = blockedList?.cast<String>() ?? [];
        
        // App Limits
        final limitsMap = childData['app_limits'] as Map<String, dynamic>?;
        if (limitsMap != null) {
          _appLimits = limitsMap.map((key, value) => MapEntry(key, value as int));
        } else {
          _appLimits = {};
        }

        // Clean up over-limit apps whose limit was removed
        _overLimitApps.removeWhere((pkg) => !_appLimits.containsKey(pkg));
        
        debugPrint('AppBlocker: Settings updated from stream. Blocked: $_blockedApps, Limits: $_appLimits');
        
        // Save to SharedPreferences for instant offline/low-speed fallback
        await _saveCachedBlockedApps();

        // Trigger a re-sync to native (always syncs, even if empty to unblock)
        await _syncBlockedAppsToNative();
      }
    }, onError: (error) {
      debugPrint('AppBlocker: Realtime stream error: $error');
    });
    
    debugPrint('AppBlocker: Initialized with local cache + Supabase stream');
  }

  /// Direct REST query fallback to ensure unblock commands are received even if stream stalls
  static Future<void> refreshFromRemote() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return;

    try {
      final data = await SupabaseConfig.client
          .from('children')
          .select('blocked_apps, app_limits')
          .eq('id', user.id)
          .maybeSingle();

      if (data != null) {
        final blockedList = data['blocked_apps'] as List<dynamic>?;
        _blockedApps = blockedList?.cast<String>() ?? [];
        
        final limitsMap = data['app_limits'] as Map<String, dynamic>?;
        if (limitsMap != null) {
          _appLimits = limitsMap.map((key, value) => MapEntry(key, value as int));
        } else {
          _appLimits = {};
        }

        _overLimitApps.removeWhere((pkg) => !_appLimits.containsKey(pkg));

        await _saveCachedBlockedApps();
        await _syncBlockedAppsToNative();
        debugPrint('AppBlocker: Direct refresh completed. Total blocked apps: ${blockedApps.length}');
      }
    } catch (e) {
      debugPrint('AppBlocker: Error in direct refresh: $e');
    }
  }

  /// Load locally cached block rules from SharedPreferences
  static Future<void> _loadCachedBlockedApps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cachedAppsJson = prefs.getString(_keyBlockedApps);
      final String? cachedLimitsJson = prefs.getString(_keyAppLimits);

      if (cachedAppsJson != null) {
        final List<dynamic> decoded = jsonDecode(cachedAppsJson);
        _blockedApps = decoded.cast<String>();
      } else {
        _blockedApps = [];
      }

      if (cachedLimitsJson != null) {
        final Map<String, dynamic> decoded = jsonDecode(cachedLimitsJson);
        _appLimits = decoded.map((k, v) => MapEntry(k, v as int));
      } else {
        _appLimits = {};
      }

      debugPrint('AppBlocker: Loaded cached rules. Blocked: $_blockedApps, Limits: $_appLimits');

      // Always sync to native on load so native side is in full sync (even if empty)
      await _syncBlockedAppsToNative();
    } catch (e) {
      debugPrint('AppBlocker: Error loading cached rules: $e');
    }
  }

  /// Save current block rules to SharedPreferences
  static Future<void> _saveCachedBlockedApps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyBlockedApps, jsonEncode(_blockedApps));
      await prefs.setString(_keyAppLimits, jsonEncode(_appLimits));
      debugPrint('AppBlocker: Saved rules to SharedPreferences');
    } catch (e) {
      debugPrint('AppBlocker: Error saving cached rules: $e');
    }
  }
  
  /// Start the native app blocker service
  static Future<void> startBlockerService() async {
    if (!Platform.isAndroid) return;
    if (_serviceStarted) return;
    
    // Check if we have overlay permission first
    final hasPermission = await hasOverlayPermission();
    if (!hasPermission) {
      debugPrint('AppBlocker: Cannot start service - overlay permission not granted');
      return;
    }
    
    try {
      await platform.invokeMethod('startBlockerService');
      _serviceStarted = true;
      debugPrint('AppBlocker: Native blocker service started');
      
      // Sync blocked apps immediately
      await _syncBlockedAppsToNative();
    } catch (e) {
      debugPrint('AppBlocker: Error starting blocker service: $e');
    }
  }
  
  /// Stop the native app blocker service
  static Future<void> stopBlockerService() async {
    if (!Platform.isAndroid) return;
    
    try {
      await platform.invokeMethod('stopBlockerService');
      _serviceStarted = false;
      debugPrint('AppBlocker: Native blocker service stopped');
    } catch (e) {
      debugPrint('AppBlocker: Error stopping blocker service: $e');
    }
  }
  
  /// Update the list of over-limit apps (called from ForegroundSyncService)
  static Future<void> updateOverLimitApps(List<String> overLimitApps) async {
    _overLimitApps = overLimitApps;
    await _syncBlockedAppsToNative();
  }
  
  /// Sync the combined blocked apps list to the native service
  static Future<void> _syncBlockedAppsToNative() async {
    if (!Platform.isAndroid) return;
    
    // Combine manual blocks and over-limit blocks
    final combinedBlockedApps = <String>{..._blockedApps, ..._overLimitApps}.toList();
    
    if (combinedBlockedApps.isNotEmpty) {
      await startBlockerService();
    }
    
    try {
      await platform.invokeMethod('updateBlockedApps', {'apps': combinedBlockedApps});
      debugPrint('AppBlocker: Synced ${combinedBlockedApps.length} total blocked apps to native');
    } catch (e) {
      debugPrint('AppBlocker: Error syncing blocked apps: $e');
    }
  }
  
  /// Stop listening and clean up
  static Future<void> dispose() async {
    _blockedAppsSubscription?.cancel();
    _blockedAppsSubscription = null;
    _isInitialized = false;
    _blockedApps = [];
    _appLimits = {};
    _overLimitApps = [];
    
    // Stop the native service
    await stopBlockerService();
  }
  
  /// Get list of currently blocked apps (manual + limits)
  static List<String> get blockedApps => List.unmodifiable([..._blockedApps, ..._overLimitApps]);
  
  /// Check if a package is blocked
  static bool isBlocked(String packageName) {
    return _blockedApps.contains(packageName) || _overLimitApps.contains(packageName);
  }
  
  /// Get the configured limits
  static Map<String, int> get appLimits => Map.unmodifiable(_appLimits);
  
  /// Check if overlay permission is granted
  static Future<bool> hasOverlayPermission() async {
    if (!Platform.isAndroid) return false;
    
    try {
      final result = await platform.invokeMethod<bool>('checkOverlayPermission');
      return result ?? false;
    } catch (e) {
      debugPrint('AppBlocker: Error checking overlay permission: $e');
      return false;
    }
  }
  
  /// Request overlay permission (opens system settings)
  static Future<void> requestOverlayPermission() async {
    if (!Platform.isAndroid) return;
    
    try {
      await platform.invokeMethod('requestOverlayPermission');
    } catch (e) {
      debugPrint('AppBlocker: Error requesting overlay permission: $e');
    }
  }
  
  /// Navigate to home screen
  static Future<void> goToHome() async {
    if (!Platform.isAndroid) return;
    
    try {
      await platform.invokeMethod('goToHome');
    } catch (e) {
      debugPrint('AppBlocker: Error going to home: $e');
    }
  }
  
  /// Check if battery optimization is disabled (app is exempted)
  static Future<bool> hasBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) return true;
    
    try {
      final result = await platform.invokeMethod<bool>('checkBatteryOptimization');
      return result ?? false;
    } catch (e) {
      debugPrint('AppBlocker: Error checking battery optimization: $e');
      return false;
    }
  }
  
  /// Request battery optimization exemption (opens system settings)
  static Future<void> requestBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) return;
    
    try {
      await platform.invokeMethod('requestBatteryOptimization');
    } catch (e) {
      debugPrint('AppBlocker: Error requesting battery optimization: $e');
    }
  }
  
  /// Start the watchdog service to ensure services stay alive
  static Future<void> startWatchdog() async {
    if (!Platform.isAndroid) return;
    
    try {
      await platform.invokeMethod('startWatchdog');
      debugPrint('AppBlocker: Watchdog service started');
    } catch (e) {
      debugPrint('AppBlocker: Error starting watchdog: $e');
    }
  }
  
  /// Get the last sync time from native side (milliseconds since epoch)
  static Future<int> getLastSyncTime() async {
    if (!Platform.isAndroid) return 0;
    
    try {
      final result = await platform.invokeMethod<int>('getLastSyncTime');
      return result ?? 0;
    } catch (e) {
      debugPrint('AppBlocker: Error getting last sync time: $e');
      return 0;
    }
  }
  
  /// Update the last sync time on native side
  static Future<void> updateLastSyncTime() async {
    if (!Platform.isAndroid) return;
    
    try {
      await platform.invokeMethod('updateLastSyncTime');
      debugPrint('AppBlocker: Updated last sync time');
    } catch (e) {
      debugPrint('AppBlocker: Error updating last sync time: $e');
    }
  }
  
  /// Check status of all services
  static Future<Map<String, dynamic>> checkAllServicesStatus() async {
    if (!Platform.isAndroid) {
      return {'appBlockerRunning': false, 'syncDue': false};
    }
    
    try {
      final result = await platform.invokeMethod<Map>('checkAllServicesStatus');
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
    } catch (e) {
      debugPrint('AppBlocker: Error checking services status: $e');
    }
    return {'appBlockerRunning': false, 'syncDue': false};
  }
  
  /// Restart all native services
  static Future<void> restartAllServices() async {
    if (!Platform.isAndroid) return;
    
    try {
      await platform.invokeMethod('restartAllServices');
      debugPrint('AppBlocker: All native services restarted');
    } catch (e) {
      debugPrint('AppBlocker: Error restarting all services: $e');
    }
  }
}

