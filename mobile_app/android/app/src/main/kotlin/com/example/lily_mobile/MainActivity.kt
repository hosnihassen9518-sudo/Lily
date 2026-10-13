package com.example.lily_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter

class MainActivity : FlutterActivity() {
    private val handler = Handler(Looper.getMainLooper())
    private var bondReceiver: BroadcastReceiver? = null
    private var bondResult: MethodChannel.Result? = null
    private var bondTimeout: Runnable? = null

    private fun finishBond(error: String? = null) {
        val result = bondResult
        bondResult = null
        bondTimeout?.let { handler.removeCallbacks(it) }
        bondTimeout = null
        bondReceiver?.let { try { unregisterReceiver(it) } catch (_: IllegalArgumentException) {} }
        bondReceiver = null
        if (error == null) result?.success(true)
        else result?.error("BLE_PAIRING", error, null)
    }

    @Suppress("MissingPermission", "DEPRECATION")
    private fun ensureBonded(address: String?, result: MethodChannel.Result) {
        if (bondResult != null) { result.error("BLE_PAIRING", "Pairing is already running.", null); return }
        try {
            val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
            val device = adapter?.getRemoteDevice(address ?: "")
            if (device == null) { result.error("BLE_PAIRING", "Bluetooth is unavailable.", null); return }
            if (device.bondState == BluetoothDevice.BOND_BONDED) { result.success(true); return }
            bondResult = result
            bondReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent == null) return
                    val peer = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                    if (peer?.address != device.address) return
                    when (device.bondState) {
                        BluetoothDevice.BOND_BONDED -> finishBond()
                        BluetoothDevice.BOND_NONE -> finishBond("Pairing failed or was cancelled. Confirm the Bluetooth pairing request and retry.")
                    }
                }
            }
            val filter = IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
            if (Build.VERSION.SDK_INT >= 33) registerReceiver(bondReceiver, filter, Context.RECEIVER_EXPORTED)
            else registerReceiver(bondReceiver, filter)
            bondTimeout = Runnable { finishBond("Pairing timed out. Complete the Android pairing dialog and retry.") }
            handler.postDelayed(bondTimeout!!, 90000)
            if (device.bondState != BluetoothDevice.BOND_BONDING && !device.createBond()) finishBond("Android could not start pairing. Forget the old Lily bond and retry.")
        } catch (error: Exception) {
            if (bondResult != null) finishBond("Could not pair: ${error.message}")
            else result.error("BLE_PAIRING", "Could not pair: ${error.message}", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        com.example.lily_mobile.widgets.LilyWidgetBridge.install(flutterEngine,this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lily/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "androidSdk" -> result.success(Build.VERSION.SDK_INT)
                    "ensureBonded" -> ensureBonded(call.argument<String>("address"), result)
                    "cancelBondWait" -> { finishBond("Pairing wait cancelled."); result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }
    override fun onDestroy() {
        finishBond("Pairing cancelled because the app closed.")
        super.onDestroy()
    }
}
