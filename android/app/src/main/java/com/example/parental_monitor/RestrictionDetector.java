package com.example.parental_monitor;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.PowerManager;
import android.provider.Settings;
import android.util.Log;

import java.util.HashMap;
import java.util.Map;

/**
 * RestrictionDetector - Detects OS and OEM background restrictions.
 * 
 * DESIGN RATIONALE:
 * -----------------
 * 1. Battery Optimization:
 *    - We can detect if our app is exempted from battery optimization
 *    - We can request exemption via ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
 *    - This is the standard Android way and is allowed for apps that need background execution
 * 
 * 2. Samsung Deep Sleeping Apps:
 *    - Samsung has an aggressive "Deep Sleeping Apps" feature that kills apps
 *    - This CANNOT be disabled programmatically
 *    - We can only detect Samsung devices and guide users to the settings
 *    - The user must manually remove the app from the deep sleep list
 * 
 * 3. Other OEM Restrictions (Xiaomi, Huawei, OnePlus, etc.):
 *    - Each OEM has different restriction mechanisms
 *    - We detect the manufacturer and provide appropriate guidance
 *    - We cannot bypass these restrictions programmatically
 * 
 * IMPORTANT: We do NOT attempt to bypass any restrictions.
 * We only detect them and provide user guidance.
 */
public class RestrictionDetector {
    private static final String TAG = "RestrictionDetector";
    
    // Known manufacturers with aggressive background restrictions
    public static final String MANUFACTURER_SAMSUNG = "samsung";
    public static final String MANUFACTURER_XIAOMI = "xiaomi";
    public static final String MANUFACTURER_HUAWEI = "huawei";
    public static final String MANUFACTURER_OPPO = "oppo";
    public static final String MANUFACTURER_VIVO = "vivo";
    public static final String MANUFACTURER_ONEPLUS = "oneplus";
    
    private final Context context;
    
    public RestrictionDetector(Context context) {
        this.context = context.getApplicationContext();
    }
    
    /**
     * Check if the app is exempted from battery optimization.
     * @return true if exempted (unrestricted), false if optimization is enabled
     */
    public boolean isIgnoringBatteryOptimizations() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PowerManager pm = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
            if (pm != null) {
                return pm.isIgnoringBatteryOptimizations(context.getPackageName());
            }
        }
        // On older devices, battery optimization doesn't apply the same way
        return true;
    }
    
    /**
     * Get an Intent to request battery optimization exemption.
     * The user will be shown a dialog to allow/deny the exemption.
     */
    public Intent getBatteryOptimizationIntent() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Intent intent = new Intent();
            intent.setAction(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS);
            intent.setData(Uri.parse("package:" + context.getPackageName()));
            return intent;
        }
        return null;
    }
    
    /**
     * Get an Intent to open battery optimization settings for all apps.
     * Useful if the direct request fails or user needs to review all apps.
     */
    public Intent getBatterySettingsIntent() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS);
        }
        return new Intent(Settings.ACTION_SETTINGS);
    }
    
    /**
     * Get the device manufacturer (lowercase).
     */
    public String getManufacturer() {
        return Build.MANUFACTURER.toLowerCase();
    }
    
    /**
     * Check if this is a Samsung device.
     */
    public boolean isSamsungDevice() {
        return MANUFACTURER_SAMSUNG.equals(getManufacturer());
    }
    
    /**
     * Check if this device has known aggressive background restrictions.
     */
    public boolean hasAggressiveOemRestrictions() {
        String manufacturer = getManufacturer();
        return MANUFACTURER_SAMSUNG.equals(manufacturer) ||
               MANUFACTURER_XIAOMI.equals(manufacturer) ||
               MANUFACTURER_HUAWEI.equals(manufacturer) ||
               MANUFACTURER_OPPO.equals(manufacturer) ||
               MANUFACTURER_VIVO.equals(manufacturer) ||
               MANUFACTURER_ONEPLUS.equals(manufacturer);
    }
    
    /**
     * Get an Intent to open Samsung's battery/deep sleep settings.
     * 
     * NOTE: Samsung's "Deep Sleeping Apps" is under:
     * Settings > Battery > Background usage limits > Deep sleeping apps
     * 
     * We cannot directly open this screen, but we can open battery settings.
     */
    public Intent getSamsungBatterySettingsIntent() {
        Intent intent = new Intent();
        
        // Try Samsung's specific battery screen
        intent.setAction("com.samsung.android.sm.ACTION_BATTERY_USAGE");
        if (intent.resolveActivity(context.getPackageManager()) != null) {
            return intent;
        }
        
        // Fallback to generic battery settings
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            intent = new Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS);
            if (intent.resolveActivity(context.getPackageManager()) != null) {
                return intent;
            }
        }
        
        // Final fallback to app settings
        return getAppSettingsIntent();
    }
    
    /**
     * Get an Intent to open the app's system settings page.
     * Useful as a fallback for OEM-specific settings.
     */
    public Intent getAppSettingsIntent() {
        Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
        intent.setData(Uri.parse("package:" + context.getPackageName()));
        return intent;
    }
    
    /**
     * Get user-friendly instructions for the current OEM.
     */
    public String getOemInstructions() {
        String manufacturer = getManufacturer();
        
        if (MANUFACTURER_SAMSUNG.equals(manufacturer)) {
            return "Samsung devices have 'Deep Sleeping Apps' that may kill this app.\n\n" +
                   "To fix:\n" +
                   "1. Go to Settings > Battery\n" +
                   "2. Tap 'Background usage limits'\n" +
                   "3. Tap 'Deep sleeping apps'\n" +
                   "4. Remove this app from the list";
        } else if (MANUFACTURER_XIAOMI.equals(manufacturer)) {
            return "Xiaomi devices have battery restrictions that may kill this app.\n\n" +
                   "To fix:\n" +
                   "1. Go to Settings > Battery & performance\n" +
                   "2. Tap 'App battery saver'\n" +
                   "3. Select this app\n" +
                   "4. Choose 'No restrictions'";
        } else if (MANUFACTURER_HUAWEI.equals(manufacturer)) {
            return "Huawei devices have power management that may kill this app.\n\n" +
                   "To fix:\n" +
                   "1. Go to Settings > Battery\n" +
                   "2. Tap 'App launch'\n" +
                   "3. Find this app and disable 'Manage automatically'\n" +
                   "4. Enable all toggles (Auto-launch, Secondary launch, Run in background)";
        } else if (MANUFACTURER_OPPO.equals(manufacturer) || MANUFACTURER_VIVO.equals(manufacturer)) {
            return "This device may kill apps in the background.\n\n" +
                   "To fix:\n" +
                   "1. Go to Settings > Battery\n" +
                   "2. Find 'Background app management' or similar\n" +
                   "3. Select this app\n" +
                   "4. Allow background running";
        } else if (MANUFACTURER_ONEPLUS.equals(manufacturer)) {
            return "OnePlus devices have battery optimization that may kill this app.\n\n" +
                   "To fix:\n" +
                   "1. Go to Settings > Battery\n" +
                   "2. Tap 'Battery optimization'\n" +
                   "3. Find this app\n" +
                   "4. Select 'Don't optimize'";
        }
        
        return "For best reliability, ensure this app is excluded from battery optimization " +
               "and any manufacturer-specific power saving features.";
    }
    
    /**
     * Get comprehensive restriction status for Flutter UI.
     */
    public Map<String, Object> getRestrictionStatus() {
        Map<String, Object> status = new HashMap<>();
        
        // Battery optimization status
        boolean isIgnoringBattery = isIgnoringBatteryOptimizations();
        status.put("isIgnoringBatteryOptimizations", isIgnoringBattery);
        
        // Manufacturer and OEM info
        String manufacturer = getManufacturer();
        status.put("manufacturer", manufacturer);
        status.put("isSamsung", isSamsungDevice());
        status.put("hasAggressiveOemRestrictions", hasAggressiveOemRestrictions());
        
        // Device info
        status.put("androidVersion", Build.VERSION.SDK_INT);
        status.put("deviceModel", Build.MODEL);
        
        // Instructions for user
        status.put("oemInstructions", getOemInstructions());
        
        // Overall recommendation
        boolean needsUserAction = !isIgnoringBattery || hasAggressiveOemRestrictions();
        status.put("needsUserAction", needsUserAction);
        
        Log.d(TAG, "Restriction status: ignoring=" + isIgnoringBattery + 
              ", manufacturer=" + manufacturer + 
              ", hasOemRestrictions=" + hasAggressiveOemRestrictions());
        
        return status;
    }
}
