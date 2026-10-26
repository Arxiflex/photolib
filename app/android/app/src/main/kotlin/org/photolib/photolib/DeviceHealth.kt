package org.photolib.photolib

import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.PowerManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Battery, battery saver, heat, memory and the network for app/lib/core/device_health.dart, which decides whether
 * background work runs, what runs and what backup may send, and the notification of a backup that stalled (ADR-0226).
 */
object DeviceHealth {
    private const val CHANNEL = "backup"

    fun register(
        context: Context,
        messenger: BinaryMessenger,
    ) {
        MethodChannel(messenger, "org.photolib/device_health").setMethodCallHandler { call, result ->
            when (call.method) {
                "state" -> {
                    result.success(state(context))
                }

                "notify" -> {
                    fun text(name: String) = call.argument<String>(name) ?: ""
                    notify(context, text("channel"), text("title"), text("body"))
                    result.success(null)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun state(context: Context): Map<String, Any> {
        // The sticky battery broadcast: reading it registers no receiver.
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))

        fun extra(
            name: String,
            default: Int,
        ) = battery?.getIntExtra(name, default) ?: default
        val power = context.getSystemService(PowerManager::class.java)
        val memory = ActivityManager.MemoryInfo()
        context.getSystemService(ActivityManager::class.java).getMemoryInfo(memory)
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        val network = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
        return mapOf(
            "battery" to extra(BatteryManager.EXTRA_LEVEL, 100) * 100 / extra(BatteryManager.EXTRA_SCALE, 100),
            "charging" to (extra(BatteryManager.EXTRA_PLUGGED, 0) != 0),
            "powerSaving" to power.isPowerSaveMode,
            "thermal" to power.currentThermalStatus,
            "temperature" to extra(BatteryManager.EXTRA_TEMPERATURE, 0) / 10.0,
            "memory" to memory.totalMem,
            // Android counts mobile data, hotspots and tethering as metered; without a network it says metered too.
            "metered" to (connectivity.activeNetwork != null && connectivity.isActiveNetworkMetered),
            "roaming" to (network?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_ROAMING) == false),
        )
    }

    /** Posts the notification, where the person allows notifications; the home screen says it either way. */
    private fun notify(
        context: Context,
        channel: String,
        title: String,
        body: String,
    ) {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return
        manager.createNotificationChannel(NotificationChannel(CHANNEL, channel, NotificationManager.IMPORTANCE_DEFAULT))
        val notification =
            android.app.Notification
                .Builder(context, CHANNEL)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setAutoCancel(true)
                .build()
        manager.notify(CHANNEL.hashCode(), notification)
    }
}
