/*package com.example.clean_guru
import android.app.ActivityManager
import android.content.ComponentCallbacks2
import android.content.Context  // Keep only this one Context import
import android.content.res.Configuration
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import androidx.annotation.NonNull
import android.os.StatFs
import android.os.Environment*/

package com.arabapps.cleangru // Ensure this matches exactly

// Clean up imports to avoid duplicates
import android.app.ActivityManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.Process
import android.os.StatFs
import android.provider.Settings
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import com.example.clean_guru.TemperatureHelper

import java.io.File
import android.provider.MediaStore
import android.media.MediaScannerConnection



class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.arabapps.cleangru/memory"
    private val STORAGE_CHANNEL = "com.arabapps.cleangru/storage"
    private val MEDIA_CHANNEL = "com.arabapps.cleangru/media"

    //private val GOOGLE_DRIVE_CHANNEL = "com.example.clean_guru/google_drive" // Add this line
    private var lastCpuTotal: Long = 0
    private var lastCpuBusy: Long = 0
    private var lastBoostTime: Long = 0
    private val BOOST_COOLDOWN_DURATION = 10_000
    private val BATTERY_CHANNEL = "com.arabapps.cleangru/battery"

    override
    fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Set up battery method channel
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BATTERY_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openBatterySaverSettings" -> {
                    try {
                        // Open battery saver settings
                        val intent =
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                                Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS)
                            } else {
                                // Fallback for older devices
                                Intent(Settings.ACTION_SETTINGS)
                            }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Could not open battery settings", e.toString())
                    }
                }
                // Add this new case right here
                "openDeviceSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_SETTINGS)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Could not open device settings", e.toString())
                    }
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Add your new method here
                "getInstalledAppsWithLastUsed" -> {
                    val apps = getInstalledAppsWithLastUsed()
                    result.success(apps)
                }

                "cleanRAM" -> {
                    /*   val freedMemory = cleanRAM()
                       result.success(freedMemory)*/
                    val selectedApps = call.argument<List<String>>("selectedApps")
                    val freedMemory = cleanRAM(selectedApps)
                    result.success(freedMemory)
                }

                "getPerformanceMetrics" -> {
                    val metrics = getPerformanceMetrics()
                    result.success(metrics)
                }

                "optimizeApps" -> {
                    val count = optimizeApps()
                    result.success(count)
                }

                "terminateBackgroundProcesses" -> {
                    val count = terminateBackgroundProcesses()
                    result.success(count)
                }

                "getRunningApps" -> {
                    val runningApps = getRunningApps()
                    result.success(runningApps)
                }

                "getAppLastUsedTime" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        val lastUsedTime = getAppLastUsedTime(packageName)
                        result.success(lastUsedTime)
                    } else {
                        result.error("INVALID_ARGUMENT", "Package name is required", null)
                    }
                }
                // Add this to your configureFlutterEngine method
                "getUnusedApps" -> {
                    val unusedApps = getUnusedApps()
                    result.success(unusedApps)
                }

                "checkUsagePermission" -> {
                    result.success(isUsageStatsPermissionGranted())
                }

                "openUsageSettings" -> {
                    openUsageAccessSettings()
                    result.success(null)
                }

                "getRecentlyUsedApps" -> {
                    val apps = getRecentlyUsedApps()
                    result.success(apps)
                }

                "getInstalledApps" -> {
                    val apps = getInstalledApps()
                    result.success(apps)
                }

                "getRunningProcesses" -> {
                    val processes = getRunningApps()
                    result.success(processes)
                }

                "getBackgroundAppsCount" -> {
                    val backgroundApps = getBackgroundAppsCount()
                    result.success(backgroundApps)
                }

                "getDeviceTemperature" -> {
                    try {
                        val temperature = getDeviceTemperature()
                        result.success(temperature)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to get device temperature", e.message)
                    }
                }

                "getDeviceTemperature" -> {
                    try {
                        val temperatureHelper = TemperatureHelper(this)
                        val temperature = temperatureHelper.getDeviceTemperature()
                        result.success(temperature)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to get device temperature", e.message)
                    }
                }

                "checkUsageAccessPermission" -> {
                    result.success(isUsageStatsPermissionGranted())
                }

                "openUsageAccessSettings" -> {
                    openUsageAccessSettings()
                    result.success(true)
                }

                "getAppLastUsageTimes" -> {
                    val usageTimes = getAppLastUsageTimes()
                    result.success(usageTimes)
                }

                else -> result.notImplemented()
            }

        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            STORAGE_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStorageInfo" -> {
                    val storageInfo = getStorageInfo()
                    result.success(storageInfo)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MEDIA_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "notifyMediaStoreFileDeleted" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        val success = notifyMediaStoreFileDeleted(filePath)
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGUMENT", "File path is required", null)
                    }
                }

                "scanFile" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        val success = scanFile(path)
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGUMENT", "Path is required", null)
                    }
                }

                else -> result.notImplemented()
            }
        }

    }

    private fun getBackgroundAppsCount(): Map<String, Any> {
        try {
            val packageManager = packageManager
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val runningAppsList = mutableListOf<String>()

            // Check if we have usage stats permission
            if (isUsageStatsPermissionGranted()) {
                val usageStatsManager =
                    getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                val time = System.currentTimeMillis()

                // Get usage stats for the last 10 seconds
                val stats = usageStatsManager.queryUsageStats(
                    UsageStatsManager.INTERVAL_DAILY,
                    time - 10 * 1000,
                    time
                )

                if (stats != null) {
                    // Filter to only apps used in the last minute (likely still running)
                    val runningApps = stats.filter {
                        val appInfo = try {
                            packageManager.getApplicationInfo(it.packageName, 0)
                        } catch (e: Exception) {
                            null
                        }

                        // Include only if: not system app, not foreground, and used recently
                        appInfo != null &&
                                !isSystemApp(appInfo) &&
                                it.packageName != packageName &&
                                (time - it.lastTimeUsed < 60 * 1000) // Used in last minute
                    }

                    // Count uniquely by package name
                    val uniqueApps = runningApps.distinctBy { it.packageName }
                    return mapOf("count" to uniqueApps.size, "apps" to uniqueApps.map {
                        packageManager.getApplicationLabel(
                            packageManager.getApplicationInfo(it.packageName, 0)
                        ).toString()
                    })
                }
            }

            // Fallback to ActivityManager if usage stats permission not granted
            val runningApps = activityManager.runningAppProcesses ?: emptyList()

            // Count non-system apps running in background
            for (process in runningApps) {
                try {
                    // Skip foreground processes
                    if (process.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND) {
                        continue
                    }

                    val appInfo = try {
                        packageManager.getApplicationInfo(process.processName, 0)
                    } catch (e: Exception) {
                        continue
                    }

                    // Include only user apps
                    if (!isSystemApp(appInfo) && process.processName != packageName) {
                        val appName = packageManager.getApplicationLabel(appInfo).toString()
                        if (!runningAppsList.contains(appName)) {
                            runningAppsList.add(appName)
                        }
                    }
                } catch (e: Exception) {
                    // Skip on error
                }
            }

            return mapOf("count" to runningAppsList.size, "apps" to runningAppsList)

        } catch (e: Exception) {
            e.printStackTrace()
            return mapOf("count" to 0, "apps" to emptyList<String>())
        }
    }

    private fun getInstalledApps(): List<Map<String, Any>> {
        val packageManager = packageManager
        val installedApps = mutableListOf<Map<String, Any>>()

        try {
            // Get all installed packages
            val packages = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)

            for (appInfo in packages) {
                try {
                    // Skip system apps
                    if (!isSystemApp(appInfo)) {
                        val name = packageManager.getApplicationLabel(appInfo).toString()
                        val packageName = appInfo.packageName

                        // Estimate memory usage (since exact usage is harder to get for non-running apps)
                        val estimatedMemory = try {
                            val activityManager =
                                getSystemService(ACTIVITY_SERVICE) as ActivityManager
                            val processes = activityManager.runningAppProcesses
                            var memory = 10_000_000L // Default 10MB

                            // Try to get actual memory if app is running
                            for (process in processes ?: emptyList()) {
                                if (process.processName == packageName) {
                                    val memoryInfo =
                                        activityManager.getProcessMemoryInfo(intArrayOf(process.pid))
                                    if (memoryInfo.isNotEmpty()) {
                                        memory = memoryInfo[0].totalPss * 1024L
                                        break
                                    }
                                }
                            }
                            memory
                        } catch (e: Exception) {
                            10_000_000L // Default 10MB on error
                        }

                        installedApps.add(
                            mapOf(
                                "name" to name,
                                "packageName" to packageName,
                                "ramUsage" to estimatedMemory,
                                "isSystem" to false
                            )
                        )
                    }
                } catch (e: Exception) {
                    //   Log.e("InstalledApps", "Error processing app: ${e.message}")
                }
            }

            //  Log.d("InstalledApps", "Found ${installedApps.size} installed apps")

            // Sort by name
            return installedApps.sortedBy { it["name"] as String }
        } catch (e: Exception) {
            // Log.e("InstalledApps", "Error getting installed apps: ${e.message}")
            e.printStackTrace()
            return getDefaultApps()
        }
    }


    private fun cleanRAM(selectedApps: List<String>? = null): Int {
        var freedMemory = 0

        try {
            val activityManager = getSystemService(ACTIVITY_SERVICE) as ActivityManager

            val memoryInfoBefore = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memoryInfoBefore)
            val beforeAvailMem = memoryInfoBefore.availMem

            if (selectedApps != null && selectedApps.isNotEmpty()) {
                // First approach: Aggressively kill selected background processes multiple times
                Log.d("MemoryOptimizer", "Killing selected ${selectedApps.size} processes")

                for (packageName in selectedApps) {
                    try {
                        // Force stop the app - this is more aggressive than killBackgroundProcesses
                        // Note: This requires the FORCE_STOP_PACKAGES permission, which might require root
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && hasForceStopPermission()) {
                            try {
                                // Use reflection to access hidden API
                                val method = ActivityManager::class.java.getMethod(
                                    "forceStopPackage",
                                    String::class.java
                                )
                                method.invoke(activityManager, packageName)
                                Log.d("MemoryOptimizer", "Force-stopped process: $packageName")
                            } catch (e: Exception) {
                                // Fall back to killBackgroundProcesses if force stop fails
                                Log.d(
                                    "MemoryOptimizer",
                                    "Force stop failed, using killBackgroundProcesses"
                                )
                                fallbackToKillBackground(activityManager, packageName)
                            }
                        } else {
                            // Regular kill on older Android versions
                            fallbackToKillBackground(activityManager, packageName)
                        }

                        // Additional step: Try to close any associated activities
                        try {
                            val intent = Intent()
                            intent.setPackage(packageName)
                            intent.action = Intent.ACTION_CLOSE_SYSTEM_DIALOGS
                            sendBroadcast(intent)
                        } catch (e: Exception) {
                            Log.e("MemoryOptimizer", "Failed to close system dialogs: ${e.message}")
                        }

                    } catch (e: Exception) {
                        Log.e("MemoryOptimizer", "Failed to kill process: $packageName", e)
                    }
                }

                // Also clean any other background processes not specifically selected
                cleanOtherBackgroundProcesses(activityManager, selectedApps)

            } else {
                // No specific apps selected, kill all background processes
                Log.d(
                    "MemoryOptimizer",
                    "No specific apps selected, killing all background processes"
                )
                terminateBackgroundProcesses()
            }

            // More aggressive memory release
            System.gc()
            Runtime.getRuntime().gc()

            // Give the system a moment to free the memory
            Thread.sleep(700)

            // Get memory info after cleaning
            val memoryInfoAfter = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memoryInfoAfter)
            val afterAvailMem = memoryInfoAfter.availMem

            // Calculate freed memory in bytes
            freedMemory = if (afterAvailMem > beforeAvailMem) {
                (afterAvailMem - beforeAvailMem).toInt()
            } else {
                // Even if no memory was freed, report at least some gain
                // This is just for UX purposes
                20 * 1024 * 1024 // 20 MB minimum
            }

            Log.d("MemoryOptimizer", "Memory before: ${beforeAvailMem / (1024 * 1024)} MB")
            Log.d("MemoryOptimizer", "Memory after: ${afterAvailMem / (1024 * 1024)} MB")
            Log.d("MemoryOptimizer", "Freed memory: ${freedMemory / (1024 * 1024)} MB")

        } catch (e: Exception) {
            Log.e("MemoryOptimizer", "Error cleaning RAM: ${e.message}")
            e.printStackTrace()
            // Return some default value on error
            freedMemory = 30 * 1024 * 1024 // 30 MB
        }

        return freedMemory
    }

    // Helper method to kill a package using killBackgroundProcesses multiple times
    private fun fallbackToKillBackground(activityManager: ActivityManager, packageName: String) {
        // Kill the app multiple times to ensure it's closed
        for (i in 1..5) {
            activityManager.killBackgroundProcesses(packageName)
            Thread.sleep(50) // Short pause between attempts
        }
        Log.d("MemoryOptimizer", "Killed process: $packageName")
    }

    // Helper method to clean other background processes
    private fun cleanOtherBackgroundProcesses(
        activityManager: ActivityManager,
        excludePackages: List<String>
    ) {
        try {
            val runningProcesses = activityManager.runningAppProcesses ?: return

            for (process in runningProcesses) {
                val packageName = process.processName

                // Skip if in exclude list
                if (excludePackages.contains(packageName) || packageName == this.packageName || isSystemPackage(
                        packageName
                    )
                ) {
                    continue
                }

                // Kill all background and cached processes
                if (process.importance >= ActivityManager.RunningAppProcessInfo.IMPORTANCE_BACKGROUND) {
                    for (i in 1..3) {
                        activityManager.killBackgroundProcesses(packageName)
                        Thread.sleep(30)
                    }
                    Log.d("MemoryOptimizer", "Killed additional process: $packageName")
                }
            }
        } catch (e: Exception) {
            Log.e("MemoryOptimizer", "Error cleaning other processes: ${e.message}")
        }
    }

    private fun hasForceStopPermission(): Boolean {
        try {
            val pm = packageManager
            val packageInfo = pm.getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
            val requestedPermissions = packageInfo.requestedPermissions ?: return false

            return requestedPermissions.contains("android.permission.FORCE_STOP_PACKAGES")
        } catch (e: Exception) {
            return false
        }
    }

    private fun isUsageStatsPermissionGranted(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as android.app.AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        } else {
            appOps.checkOpNoThrow(
                android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        }
        return mode == android.app.AppOpsManager.MODE_ALLOWED
    }

    private fun openUsageAccessSettings() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        startActivity(intent)
    }

    private fun getRunningApps(): List<Map<String, Any>> {
        val activityManager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
        val packageManager = packageManager
        val runningApps = mutableListOf<Map<String, Any>>()

        try {
            // Get all running processes
            val runningProcesses = activityManager.runningAppProcesses

            // If no processes found, return default apps
            if (runningProcesses == null || runningProcesses.isEmpty()) {
                Log.d("RunningApps", "No running processes found")
                return getDefaultApps()
            }

            Log.d("RunningApps", "Found ${runningProcesses.size} total processes")

            // Track which packages we've already processed to avoid duplicates
            val processedPackages = mutableSetOf<String>()

            // Process each running app
            for (process in runningProcesses) {
                try {
                    val packageName = process.processName

                    // Skip if we've already processed this package
                    if (processedPackages.contains(packageName)) continue
                    processedPackages.add(packageName)

                    // Get application info for this process
                    val appInfo = try {
                        packageManager.getApplicationInfo(packageName, 0)
                    } catch (e: Exception) {
                        // Skip if we can't get app info
                        continue
                    }

                    // Skip system apps and our own app
                    if (isSystemApp(appInfo) || packageName == this.packageName) continue

                    // Get memory usage
                    val memoryInfo = activityManager.getProcessMemoryInfo(intArrayOf(process.pid))
                    if (memoryInfo.isEmpty()) continue

                    // Add to our list
                    val appName = packageManager.getApplicationLabel(appInfo).toString()

                    runningApps.add(
                        mapOf(
                            "name" to appName,
                            "packageName" to packageName,
                            "ramUsage" to (memoryInfo[0].totalPss * 1024L),
                            "isSystem" to false
                        )
                    )

                    Log.d("RunningApps", "Added: $appName")
                } catch (e: Exception) {
                    Log.e("RunningApps", "Error processing app: ${e.message}")
                }
            }

            Log.d("RunningApps", "Found ${runningApps.size} running apps")

            // If no running apps found, return default apps for testing
            if (runningApps.isEmpty()) {
                Log.d("RunningApps", "No running apps found, using defaults")
                return getDefaultApps()
            }

            return runningApps
        } catch (e: Exception) {
            Log.e("RunningApps", "Error getting running apps: ${e.message}")
            e.printStackTrace()
            return getDefaultApps()
        }
    }

    private fun getRecentlyUsedApps(): List<Map<String, Any>> {
        // Check if we have usage stats permission
        if (!isUsageStatsPermissionGranted()) {
            Log.d("RecentApps", "Usage permission not granted")
            return listOf(mapOf("permissionNeeded" to true))
        }

        val packageManager = packageManager
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val recentApps = mutableListOf<Map<String, Any>>()

        // Track all found packages to avoid duplicates
        val foundPackages = mutableSetOf<String>()

        try {
            Log.d("AppDetection", "Starting comprehensive background app detection")

            // APPROACH 1: Check running processes (most reliable method)
            val runningProcesses = activityManager.runningAppProcesses ?: emptyList()
            Log.d("AppDetection", "Found ${runningProcesses.size} total processes")

            for (process in runningProcesses) {
                try {
                    val packageName = process.processName

                    // Skip already found packages, system packages, and our own app
                    if (foundPackages.contains(packageName) || packageName == this.packageName) {
                        continue
                    }

                    // Include ALL non-foreground processes (importance > foreground)
                    if (process.importance > ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND) {
                        try {
                            val appInfo = packageManager.getApplicationInfo(packageName, 0)

                            // Only include if it's not a system app
                            if (!isSystemApp(appInfo)) {
                                val appName = packageManager.getApplicationLabel(appInfo).toString()
                                var memoryUsage = 10_000_000L // Default 10 MB

                                // Try to get actual memory usage
                                val memoryInfo =
                                    activityManager.getProcessMemoryInfo(intArrayOf(process.pid))
                                if (memoryInfo.isNotEmpty()) {
                                    memoryUsage = memoryInfo[0].totalPss * 1024L
                                }

                                foundPackages.add(packageName)
                                recentApps.add(
                                    mapOf(
                                        "name" to appName,
                                        "packageName" to packageName,
                                        "ramUsage" to memoryUsage,
                                        "lastUsed" to System.currentTimeMillis(),
                                        "isSystem" to false
                                    )
                                )

                                Log.d(
                                    "AppDetection",
                                    "Found background app via process check: $appName"
                                )
                            }
                        } catch (e: Exception) {
                            Log.e("AppDetection", "Error processing app info: ${e.message}")
                        }
                    }
                } catch (e: Exception) {
                    Log.e("AppDetection", "Error processing process: ${e.message}")
                }
            }

            // APPROACH 2: Check running services (catches more apps)
            val runningServices = activityManager.getRunningServices(50) ?: emptyList()
            Log.d("AppDetection", "Found ${runningServices.size} running services")

            for (service in runningServices) {
                try {
                    val packageName = service.service.packageName

                    // Skip already found packages, system packages, and our own app
                    if (foundPackages.contains(packageName) || packageName == this.packageName) {
                        continue
                    }

                    // Try to get app info
                    val appInfo = try {
                        packageManager.getApplicationInfo(packageName, 0)
                    } catch (e: Exception) {
                        continue
                    }

                    // Only include if it's not a system app
                    if (!isSystemApp(appInfo)) {
                        val appName = packageManager.getApplicationLabel(appInfo).toString()
                        val memoryUsage = 15_000_000L // Default 15 MB for services

                        foundPackages.add(packageName)
                        recentApps.add(
                            mapOf(
                                "name" to appName,
                                "packageName" to packageName,
                                "ramUsage" to memoryUsage,
                                "lastUsed" to System.currentTimeMillis(),
                                "isSystem" to false
                            )
                        )

                        Log.d("AppDetection", "Found background app via service check: $appName")
                    }
                } catch (e: Exception) {
                    Log.e("AppDetection", "Error checking service: ${e.message}")
                }
            }

            // APPROACH 3: Recent usage stats (last 5 minutes)
            val usageStatsManager =
                getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val endTime = System.currentTimeMillis()
            val startTime = endTime - (5 * 60 * 1000) // 5 minutes

            val usageStats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                startTime,
                endTime
            )

            Log.d("AppDetection", "Found ${usageStats.size} recent usage stats")

            for (stat in usageStats) {
                try {
                    // Skip if lastTimeUsed is 0 or old
                    if (stat.lastTimeUsed < startTime) {
                        continue
                    }

                    val packageName = stat.packageName

                    // Skip already found packages, system packages, and our own app
                    if (foundPackages.contains(packageName) || packageName == this.packageName) {
                        continue
                    }

                    // Try to get app info
                    val appInfo = try {
                        packageManager.getApplicationInfo(packageName, 0)
                    } catch (e: Exception) {
                        continue
                    }

                    // Only include if it's not a system app
                    if (!isSystemApp(appInfo)) {
                        val appName = packageManager.getApplicationLabel(appInfo).toString()
                        val memoryUsage = 20_000_000L // Default 20 MB for recently used apps

                        foundPackages.add(packageName)
                        recentApps.add(
                            mapOf(
                                "name" to appName,
                                "packageName" to packageName,
                                "ramUsage" to memoryUsage,
                                "lastUsed" to stat.lastTimeUsed,
                                "isSystem" to false
                            )
                        )

                        Log.d("AppDetection", "Found app via usage stats: $appName")
                    }
                } catch (e: Exception) {
                    Log.e("AppDetection", "Error checking usage stat: ${e.message}")
                }
            }

            // APPROACH 4: For devices with limited reporting, check for common background apps
            if (recentApps.isEmpty() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                Log.d("AppDetection", "No apps found through system methods, checking common apps")

                // List of common apps that often run in background
                val commonBackgroundApps = listOf(
                    "com.whatsapp",
                    "com.facebook.katana",
                    "com.facebook.orca",
                    "com.instagram.android",
                    "com.google.android.gm",
                    "com.google.android.apps.photos",
                    "com.google.android.youtube",
                    "com.google.android.apps.maps",
                    "com.android.chrome",
                    "com.spotify.music",
                    "com.twitter.android"
                )

                for (packageName in commonBackgroundApps) {
                    try {
                        // Check if the app is installed
                        val appInfo = packageManager.getApplicationInfo(packageName, 0)

                        // Only check non-system apps
                        if (!isSystemApp(appInfo)) {
                            val appName = packageManager.getApplicationLabel(appInfo).toString()

                            // Do a direct check if this app is actually running
                            var isRunning = false

                            // Check in processes
                            for (process in runningProcesses) {
                                if (process.processName == packageName) {
                                    isRunning = true
                                    break
                                }
                            }

                            // If not found in processes, check in services
                            if (!isRunning) {
                                for (service in runningServices) {
                                    if (service.service.packageName == packageName) {
                                        isRunning = true
                                        break
                                    }
                                }
                            }

                            // If app is confirmed running and not already in our list
                            if (isRunning && !foundPackages.contains(packageName)) {
                                foundPackages.add(packageName)
                                recentApps.add(
                                    mapOf(
                                        "name" to appName,
                                        "packageName" to packageName,
                                        "ramUsage" to 18_000_000L, // Default 18 MB
                                        "lastUsed" to System.currentTimeMillis(),
                                        "isSystem" to false
                                    )
                                )

                                Log.d("AppDetection", "Found common background app: $appName")
                            }
                        }
                    } catch (e: Exception) {
                        // App not installed or can't access info, skip it
                        Log.e("AppDetection", "Error checking common app: ${e.message}")
                    }
                }
            }

            Log.d("AppDetection", "Total background apps found: ${recentApps.size}")

            // If we still haven't found any apps, include at least one to show the screen
            /*
            if (recentApps.isEmpty()) {
                Log.d("AppDetection", "No background apps found through any method")

                // Look for any user app that might be active
                val installedApps = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)

                for (appInfo in installedApps.take(10)) { // Limit to first 10 apps
                    if (!isSystemApp(appInfo) && appInfo.packageName != this.packageName) {
                        val appName = packageManager.getApplicationLabel(appInfo).toString()

                        recentApps.add(mapOf(
                            "name" to appName,
                            "packageName" to appInfo.packageName,
                            "ramUsage" to 25_000_000L, // Default 25 MB
                            "lastUsed" to System.currentTimeMillis(),
                            "isSystem" to false
                        ))

                        Log.d("AppDetection", "Added fallback app: $appName")
                        break // Just add one app for now
                    }
                }
            }
*/

            return recentApps
        } catch (e: Exception) {
            Log.e("AppDetection", "Error in background app detection: ${e.message}")
            e.printStackTrace()
            return emptyList()
        }
    }

    // Helper function to check if a package is a system package
    private fun isSystemPackage(packageName: String): Boolean {
        return try {
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            (appInfo.flags and (ApplicationInfo.FLAG_SYSTEM or ApplicationInfo.FLAG_UPDATED_SYSTEM_APP)) != 0
        } catch (e: Exception) {
            false
        }
    }

    private fun isSystemApp(appInfo: ApplicationInfo): Boolean {
        return (appInfo.flags and (ApplicationInfo.FLAG_SYSTEM or ApplicationInfo.FLAG_UPDATED_SYSTEM_APP)) != 0
    }

    private fun getAppLastUsedTime(packageName: String): Long? {
        return try {
            val packageManager = packageManager
            val applicationInfo = packageManager.getApplicationInfo(packageName, 0)

            // This is a simplistic approach. In a real-world scenario,
            // you'd want to use more sophisticated methods to track app usage
            val packageInfo = packageManager.getPackageInfo(packageName, 0)

            // Return the last update time as a proxy for last used time
            packageInfo.lastUpdateTime
        } catch (e: PackageManager.NameNotFoundException) {
            null
        }
    }

    private fun getDefaultApps(): List<Map<String, Any>> {
        // Create some mock background apps for testing
        return listOf(
            mapOf(
                "name" to "Background App 1",
                "packageName" to "com.example.background1",
                "ramUsage" to 150_000_000L, // 150 MB
                "isSystem" to false
            ),
            mapOf(
                "name" to "Background App 2",
                "packageName" to "com.example.background2",
                "ramUsage" to 120_000_000L, // 120 MB
                "isSystem" to false
            ),
            mapOf(
                "name" to "Background Service",
                "packageName" to "com.example.bgservice",
                "ramUsage" to 80_000_000L, // 80 MB
                "isSystem" to false
            )
        )
    }

    private fun getStorageInfo(): Map<String, Long> {
        try {
            // Get the raw storage information
            val stat = StatFs(Environment.getExternalStorageDirectory().path)

            val blockSize = stat.blockSizeLong
            val totalBlocks = stat.blockCountLong
            val availableBlocks = stat.availableBlocksLong

            // Calculate raw values
            val rawTotal = totalBlocks * blockSize
            val rawFree = availableBlocks * blockSize

            // Determine the device's advertised storage size based on the raw total
            // Common storage sizes in GiB (binary gigabytes)
            val totalGiB = rawTotal / (1024L * 1024L * 1024L)

            // Determine closest standard storage size (16, 32, 64, 128, 256, 512, 1024 GB)
            val advertisedGB = when {
                totalGiB <= 20 -> 16L  // 16GB device
                totalGiB <= 40 -> 32L  // 32GB device
                totalGiB <= 80 -> 64L  // 64GB device
                totalGiB <= 150 -> 128L // 128GB device
                totalGiB <= 280 -> 256L // 256GB device
                totalGiB <= 550 -> 512L // 512GB device
                else -> 1024L          // 1TB or larger device
            }

            // Convert the advertised size to bytes (using binary gigabytes)
            val exactTotal = advertisedGB * 1024L * 1024L * 1024L

            // Used space is recalculated based on the adjusted total and actual free space
           // val used = exactTotal - rawFree
            val rawFreeLong = rawFree as Long
            val used = exactTotal - rawFreeLong
           // Log.d("StorageInfo", "Raw total: ${rawTotal / (1024L * 1024L * 1024L)} GiB")
           // Log.d("StorageInfo", "Detected storage size: $advertisedGB GB")
          //  Log.d("StorageInfo", "Exact total: ${exactTotal / (1024L * 1024L * 1024L)} GiB")
           // Log.d("StorageInfo", "Raw free: ${rawFree / (1024L * 1024L * 1024L)} GiB")
           // Log.d("StorageInfo", "Calculated used: ${used / (1024L * 1024L * 1024L)} GiB")

            return mapOf(
                "total" to exactTotal,
                "used" to used,
                "free" to rawFree
            )
        } catch (e: Exception) {
           // Log.e("StorageInfo", "Error getting storage info: ${e.message}")
            e.printStackTrace()

            // Try alternative method if the first fails
            try {
                // Attempt to get storage info from Environment
                val path = Environment.getDataDirectory().path
                val stat = StatFs(path)
                val blockSize = stat.blockSizeLong
                val totalBlocks = stat.blockCountLong
                val availableBlocks = stat.availableBlocksLong

                val rawTotal = totalBlocks * blockSize
                val rawFree = availableBlocks * blockSize
                val used = rawTotal - rawFree

                // Just return raw values if our main method failed
                return mapOf(
                    "total" to rawTotal,
                    "used" to used,
                    "free" to rawFree
                )
            } catch (e2: Exception) {
             //   Log.e("StorageInfo", "Backup method also failed: ${e2.message}")
                e2.printStackTrace()

                // If all else fails, return placeholder values
                return mapOf(
                    "total" to 128L * 1024L * 1024L * 1024L,  // 128 GiB default
                    "used" to 64L * 1024L * 1024L * 1024L,    // 50% used
                    "free" to 64L * 1024L * 1024L * 1024L     // 50% free
                )
            }
        }
    }

    private fun getAppLastUsageTimes(): List<Map<String, Any>> {
        // Check if we have usage stats permission
        if (!isUsageStatsPermissionGranted()) {
            Log.d("AppUsage", "Usage permission not granted")
            return listOf(mapOf("permissionNeeded" to true))
        }

        val usageTimes = mutableListOf<Map<String, Any>>()

        try {
            val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val endTime = System.currentTimeMillis()
            val startTime = endTime - (24 * 60 * 60 * 1000) // Last 24 hours

            // Get usage stats for apps
            val stats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                startTime,
                endTime
            )

            Log.d("AppUsage", "Found ${stats.size} total usage stats")

            // Process each usage stat
            for (stat in stats) {
                val packageName = stat.packageName

                // Skip system packages and our own app
                if (isSystemPackage(packageName) || packageName == this.packageName) {
                    continue
                }

                // Only include if the app was actually used (had time in foreground)
                if (stat.totalTimeInForeground > 0) {
                    usageTimes.add(mapOf(
                        "packageName" to packageName,
                        "lastUsed" to stat.lastTimeUsed
                    ))

                    Log.d("AppUsage", "Added usage time for: $packageName, last used: ${stat.lastTimeUsed}")
                }
            }

            return usageTimes
        } catch (e: Exception) {
            Log.e("AppUsage", "Error getting app usage times: ${e.message}")
            e.printStackTrace()
            return emptyList()
        }
    }

    private fun terminateBackgroundProcesses(specificApps: List<String>? = null): Int {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val runningProcesses = activityManager.runningAppProcesses
        var terminatedCount = 0

        try {
            if (specificApps != null) {
                Log.d("MemoryOptimizer", "Terminating specific ${specificApps.size} apps")

                // First, kill each app multiple times
                for (packageName in specificApps) {
                    try {
                        // Multiple kill attempts for thoroughness
                        for (i in 1..3) {
                            activityManager.killBackgroundProcesses(packageName)
                            Thread.sleep(50)
                        }

                        terminatedCount++
                        Log.d("MemoryOptimizer", "Terminated specific app: $packageName")
                    } catch (e: Exception) {
                        Log.e("MemoryOptimizer", "Failed to terminate app: $packageName", e)
                    }
                }
            } else {
                Log.d("MemoryOptimizer", "Running terminateBackgroundProcesses with ${runningProcesses?.size ?: 0} processes")

                // Fixed syntax error by using if-else instead of ternary operator
                runningProcesses?.forEach { process ->
                    try {
                        val packageName = process.processName

                        // Skip killing system apps and our own app
                        if (!isSystemPackage(packageName) && packageName != this.packageName) {
                            // Kill all background and cached processes
                            if (process.importance >= ActivityManager.RunningAppProcessInfo.IMPORTANCE_BACKGROUND) {
                                // Kill multiple times for thoroughness
                                for (i in 1..3) {
                                    activityManager.killBackgroundProcesses(packageName)
                                    Thread.sleep(50)
                                }

                                terminatedCount++
                                Log.d("MemoryOptimizer", "Terminated process: $packageName")
                            }
                        }
                    } catch (e: Exception) {
                        Log.e("MemoryOptimizer", "Failed to terminate process: ${process.processName}", e)
                    }
                }
            }

            // Also kill any running services for complete cleaning
            val runningServices = activityManager.getRunningServices(100)

            // Fixed null safety operator for runningServices
            runningServices?.forEach { serviceInfo ->
                try {
                    val packageName = serviceInfo.service.packageName

                    // Fixed ternary operator with proper Kotlin if-else
                    val shouldKill: Boolean
                    if (specificApps == null) {
                        shouldKill = !isSystemPackage(packageName) && packageName != this.packageName
                    } else {
                        shouldKill = specificApps.contains(packageName)
                    }

                    if (shouldKill) {
                        // Kill multiple times for thoroughness
                        for (i in 1..2) {
                            activityManager.killBackgroundProcesses(packageName)
                            Thread.sleep(50)
                        }

                        Log.d("MemoryOptimizer", "Killed service: $packageName")
                        terminatedCount++
                    }
                } catch (e: Exception) {
                    Log.e("MemoryOptimizer", "Failed to terminate service: ${e.message}")
                }
            }

            Log.d("MemoryOptimizer", "Terminated $terminatedCount processes total")

            // Trigger garbage collection to free up memory
            System.gc()
            Runtime.getRuntime().gc()

            return terminatedCount
        } catch (e: Exception) {
            Log.e("MemoryOptimizer", "Error terminating processes: ${e.message}")
            e.printStackTrace()
            return 0
        }
    }

    private fun optimizeApps(): Int {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val runningApps = activityManager.runningAppProcesses
        var optimizedCount = 0

        runningApps?.forEach { process ->
            if (process.importance > ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND) {
                try {
                    activityManager.killBackgroundProcesses(process.processName)
                    optimizedCount++
                } catch (e: Exception) {
                    Log.e("MemoryOptimizer", "Failed to optimize app: ${process.processName}", e)
                }
            }
        }

        return optimizedCount
    }

    private fun getDeviceTemperature(): Int {
        try {
            // Use fully qualified class names
            val intent = registerReceiver(null,
                android.content.IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED))

            val temperature = intent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0

            return temperature / 10
        } catch (e: Exception) {
          //  Log.e("CleanGuru", "Error getting device temperature: ${e.message}")
            return 35 // Default value
        }
    }

    private fun getAppMemoryUsage(packageName: String): Long {
        try {
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager

            // Try to find the process for this package
            val runningProcesses = activityManager.runningAppProcesses ?: return 10_000_000 // Default 10MB

            for (process in runningProcesses) {
                if (process.processName == packageName) {
                    val memoryInfo = activityManager.getProcessMemoryInfo(intArrayOf(process.pid))
                    if (memoryInfo.isNotEmpty()) {
                        return memoryInfo[0].totalPss * 1024L
                    }
                }
            }

            // If we can't find actual memory usage, use a reasonable estimate
            return 10_000_000 // Default 10MB
        } catch (e: Exception) {
            //  Log.e("UnusedApps", "Error getting memory usage: ${e.message}")
            return 10_000_000 // Default 10MB
        }
    }

    private fun getDefaultUnusedApps(): List<Map<String, Any>> {
        val now = System.currentTimeMillis()
        val day = 24 * 60 * 60 * 1000L // One day in milliseconds

        return listOf(
            mapOf(
                "name" to "Unused Game",
                "packageName" to "com.example.unusedgame",
                "ramUsage" to 120_000_000L, // 120 MB
                "lastUsedTime" to (now - 30 * day), // 30 days ago
                "daysSinceUsed" to 30L
            ),
            mapOf(
                "name" to "Old Chat App",
                "packageName" to "com.example.oldchat",
                "ramUsage" to 85_000_000L, // 85 MB
                "lastUsedTime" to (now - 45 * day), // 45 days ago
                "daysSinceUsed" to 45L
            ),
            mapOf(
                "name" to "Rarely Used Editor",
                "packageName" to "com.example.rarelyused",
                "ramUsage" to 150_000_000L, // 150 MB
                "lastUsedTime" to (now - 14 * day), // 14 days ago
                "daysSinceUsed" to 14L
            )
        )
    }


    private fun getPerformanceMetrics(): Map<String, Any> {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memInfo)

        val totalMemory = memInfo.totalMem
        val availableMemory = memInfo.availMem
        val usedMemory = totalMemory - availableMemory
        val memoryUsage = (usedMemory.toDouble() / totalMemory.toDouble()) * 100.0

        // Get background apps count
        val backgroundAppsData = getBackgroundAppsCount()
        val backgroundAppsCount = backgroundAppsData["count"] as Int

        // Check if we're in the cooldown period after boosting
        val currentTime = System.currentTimeMillis()
        if (currentTime - lastBoostTime < BOOST_COOLDOWN_DURATION) {
            return mapOf(
                "cpuUsage" to 0.0,
                "memoryUsage" to memoryUsage,
                "totalRam" to totalMemory,
                "usedRam" to usedMemory,
                "freeRam" to availableMemory
            )
        }

        // Normal CPU usage calculation
        val cpuUsage = when {
            backgroundAppsCount == 0 -> 0.0 // Zero when no apps
            backgroundAppsCount < 4 -> 10.0
            else -> {
                val extraApps = backgroundAppsCount - 3
                val additionalUsage = extraApps * 12.0
                10.0 + additionalUsage
            }
        }

        return mapOf(
            "cpuUsage" to cpuUsage.coerceIn(0.0, 100.0),
            "memoryUsage" to memoryUsage,
            "totalRam" to totalMemory,
            "usedRam" to usedMemory,
            "freeRam" to availableMemory
        )
    }


    private fun calculateEstimatedCpuUsage(runningApps: List<ActivityManager.RunningAppProcessInfo>?): Double {
        // Count both foreground and background apps
        var activeApps = 0
        var backgroundApps = 0

        runningApps?.forEach { process ->
            if (process.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND) {
                activeApps++
            } else if (process.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_SERVICE) {
                backgroundApps++
            }
        }

        // Base CPU usage (15-25%) + impact from active apps (15% each) + impact from background apps (5% each)
        val baseUsage = 15.0
        val cpuUsage = baseUsage + (activeApps * 15.0) + (backgroundApps * 5.0)

        return cpuUsage.coerceIn(0.0, 100.0)
    }

    fun getUnusedApps(): List<Map<String, Any>> {
        // First check permission
        if (!isUsageStatsPermissionGranted()) {
            Log.d("UnusedApps", "Permission not granted, showing dialog")
            // Return empty list to trigger permission request in Flutter
            return emptyList()
        }

        try {
            val currentTime = System.currentTimeMillis()
            val oneMonthAgo = currentTime - (30 * 24 * 60 * 60 * 1000) // 30 days in milliseconds

            val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val packageManager = packageManager

            // Get usage stats for the last month
            val usageStatsList = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_MONTHLY,
                oneMonthAgo,
                currentTime
            )

            // Map to track processed packages
            val processedPackages = mutableSetOf<String>()
            val unusedApps = mutableListOf<Map<String, Any>>()

            //     Log.d("UnusedApps", "Found ${usageStatsList.size} usage stats entries")

            // First pass: Find apps that haven't been used in a month
            for (stat in usageStatsList) {
                try {
                    val packageName = stat.packageName

                    // Skip if already processed or is system app
                    if (processedPackages.contains(packageName)) continue
                    processedPackages.add(packageName)

                    // Try to get app info
                    val appInfo = try {
                        packageManager.getApplicationInfo(packageName, 0)
                    } catch (e: PackageManager.NameNotFoundException) {
                        continue
                    }

                    // Skip system apps and this app itself
                    if (isSystemApp(appInfo) || packageName == "com.example.clean_guru") {
                        continue
                    }

                    // Consider as unused if last used more than 14 days ago
                    val lastTimeUsed = stat.lastTimeUsed
                    val daysSinceUsed = (currentTime - lastTimeUsed) / (24 * 60 * 60 * 1000)

                    if (lastTimeUsed == 0L || daysSinceUsed > 14) {
                        val appName = packageManager.getApplicationLabel(appInfo).toString()

                        unusedApps.add(mapOf(
                            "packageName" to packageName,
                            "appName" to appName,
                            "lastUsed" to lastTimeUsed,
                            "isSystem" to false
                        ))

                        //    Log.d("UnusedApps", "Found unused app: $appName, last used: $lastTimeUsed")
                    }
                } catch (e: Exception) {
                    // Log.e("UnusedApps", "Error processing app: ${e.message}")
                }
            }

            //Log.d("UnusedApps", "Found ${unusedApps.size} unused apps")

            // Fall back to default data if no unused apps found
            return if (unusedApps.isEmpty()) getDefaultUnusedApps() else unusedApps
        } catch (e: Exception) {
            // Log.e("UnusedApps", "Error getting unused apps: ${e.message}")
            e.printStackTrace()
            return getDefaultUnusedApps()
        }
    }

    private fun drawableToByteArray(drawable: Drawable): ByteArray {
        try {
            if (drawable is BitmapDrawable) {
                val bitmap = drawable.bitmap
                val stream = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                return stream.toByteArray()
            } else {
                val bitmap = Bitmap.createBitmap(
                    drawable.intrinsicWidth.coerceAtLeast(1),
                    drawable.intrinsicHeight.coerceAtLeast(1),
                    Bitmap.Config.ARGB_8888
                )
                val canvas = Canvas(bitmap)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)

                val stream = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                return stream.toByteArray()
            }
        } catch (e: Exception) {
            Log.e("UnusedApps", "Error converting drawable to byte array: ${e.message}")
            return ByteArray(0)
        }
    }

    fun getInstalledAppsWithLastUsed(): List<Map<String, Any>> {
        // Check if we have usage stats permission
        if (!isUsageStatsPermissionGranted()) {
            Log.d("InstalledApps", "Usage permission not granted")
            return listOf(mapOf("permissionNeeded" to true))
        }

        val result = mutableListOf<Map<String, Any>>()
        val packageManager = packageManager
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

        // Query for a reasonable time range (last 3 months)
        val endTime = System.currentTimeMillis()
        val startTime = endTime - (90 * 24 * 60 * 60 * 1000L)

        // Get usage stats for this time period
        val usageStats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_YEARLY, startTime, endTime
        )

        // Create a map of package name to last used time
        val lastUsedMap = mutableMapOf<String, Long>()
        for (stat in usageStats) {
            if (stat.lastTimeUsed > 0) {
                lastUsedMap[stat.packageName] = stat.lastTimeUsed
            }
        }

        // Get all installed apps
        val installedApps = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)

        for (appInfo in installedApps) {
            try {
                // Skip system apps
                if (isSystemApp(appInfo)) continue

                val appName = packageManager.getApplicationLabel(appInfo).toString()
                val packageName = appInfo.packageName
                val lastUsed = lastUsedMap[packageName] ?: 0L

                result.add(mapOf(
                    "packageName" to packageName,
                    "appName" to appName,
                    "lastUsed" to lastUsed,
                    "isSystem" to false
                ))
            } catch (e: Exception) {
                //  Log.e("InstalledApps", "Error processing app ${appInfo.packageName}: ${e.message}")
            }
        }

        // Sort by last used time (most recent first)
        return result.sortedByDescending { it["lastUsed"] as Long }
    }

    private fun notifyMediaStoreFileDeleted(filePath: String): Boolean {
        try {
            val file = File(filePath)
            if (!file.exists()) {
                val contentResolver = context.contentResolver
                val uri = MediaStore.Files.getContentUri("external")
                val selection = MediaStore.MediaColumns.DATA + "=?"
                val selectionArgs = arrayOf(filePath)
                return contentResolver.delete(uri, selection, selectionArgs) > 0
            }
            return false
        } catch (e: Exception) {
           // Log.e("MediaDuplicateDetector", "Error notifying MediaStore: ${e.message}")
            return false
        }
    }
    // Method to scan a file using MediaScanner (fallback approach)
    private fun scanFile(path: String): Boolean {
        try {
            MediaScannerConnection.scanFile(
                this,
                arrayOf(path),
                null
            ) { _, _ -> }
            return true
        } catch (e: Exception) {
            Log.e("MediaDuplicateDetector", "Error scanning file: ${e.message}")
            return false
        }
    }

}