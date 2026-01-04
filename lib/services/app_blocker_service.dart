import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service to check and enforce app blocking on the child's device.
/// This service communicates with the native Android AppBlockerService.
class AppBlockerService {
  static const platform = MethodChannel('com.example.parental_monitor/overlay');
  
  static List<String> _blockedApps = [];
  static StreamSubscription? _blockedAppsSubscription;
  static bool _isInitialized = false;
  static bool _serviceStarted = false;
  
  /// Initialize the blocker service and start listening to blocked apps
  static Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    
    // Listen to blocked apps changes from Firestore
    _blockedAppsSubscription = FirebaseFirestore.instance
        .collection('children')
        .doc(uid)
        .snapshots()
        .listen((snapshot) async {
      if (snapshot.exists) {
        final data = snapshot.data();
        final blockedList = data?['blockedApps'] as List<dynamic>?;
        _blockedApps = blockedList?.cast<String>() ?? [];
        debugPrint('AppBlocker: Blocked apps updated: $_blockedApps');
        
        // Sync blocked apps to native service
        await _syncBlockedAppsToNative();
        
        // Start or stop the blocker service based on whether there are blocked apps
        if (_blockedApps.isNotEmpty) {
          await startBlockerService();
        }
      }
    });
    
    debugPrint('AppBlocker: Initialized');
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
  
  /// Sync the blocked apps list to the native service
  static Future<void> _syncBlockedAppsToNative() async {
    if (!Platform.isAndroid) return;
    
    try {
      await platform.invokeMethod('updateBlockedApps', {'apps': _blockedApps});
      debugPrint('AppBlocker: Synced ${_blockedApps.length} blocked apps to native');
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
    
    // Stop the native service
    await stopBlockerService();
  }
  
  /// Get list of currently blocked apps
  static List<String> get blockedApps => List.unmodifiable(_blockedApps);
  
  /// Check if a package is blocked
  static bool isBlocked(String packageName) {
    return _blockedApps.contains(packageName);
  }
  
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

