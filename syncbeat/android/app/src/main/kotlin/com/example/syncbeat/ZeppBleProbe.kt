package com.example.syncbeat

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.os.Handler
import android.os.Looper
import java.util.concurrent.atomic.AtomicBoolean

/** Discovery only: never writes characteristics/descriptors or authenticates. */
@SuppressLint("MissingPermission")
internal class ZeppBleProbe(
    private val context: Context,
    private val complete: (List<String>?, String?) -> Unit,
) {
    private val main = Handler(Looper.getMainLooper())
    private val finished = AtomicBoolean(false)
    private var gatt: BluetoothGatt? = null
    private val deadline = Runnable { finish(null, "Il collegamento BLE parallelo non risponde entro 20 secondi.") }

    fun start(device: BluetoothDevice) {
        main.postDelayed(deadline, 20_000)
        try {
            gatt = device.connectGatt(context, false, object : BluetoothGattCallback() {
                override fun onConnectionStateChange(connection: BluetoothGatt, status: Int, newState: Int) {
                    main.post {
                        if (finished.get()) { runCatching { connection.close() }; return@post }
                        if (status != BluetoothGatt.GATT_SUCCESS) {
                            finish(null, "Connessione BLE rifiutata (stato $status).")
                        } else if (newState == BluetoothProfile.STATE_CONNECTED) {
                            try {
                                if (!connection.discoverServices()) finish(null, "Impossibile leggere i servizi BLE.")
                            } catch (_: SecurityException) { finish(null, "Permesso Bluetooth non disponibile.") }
                        } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                            finish(null, "Il collegamento BLE è stato chiuso dall’orologio.")
                        }
                    }
                }

                override fun onServicesDiscovered(connection: BluetoothGatt, status: Int) {
                    main.post {
                        if (finished.get()) return@post
                        if (status != BluetoothGatt.GATT_SUCCESS) {
                            finish(null, "Lettura servizi BLE fallita (stato $status).")
                        } else {
                            try {
                                finish(connection.services.flatMap { service ->
                                    service.characteristics.map { it.uuid.toString() }
                                }.distinct(), null)
                            } catch (_: SecurityException) { finish(null, "Permesso Bluetooth non disponibile.") }
                        }
                    }
                }
            }, BluetoothDevice.TRANSPORT_LE)
            if (gatt == null) finish(null, "Impossibile avviare il collegamento BLE.")
        } catch (_: Exception) {
            finish(null, "Impossibile avviare la verifica BLE. Controlla Bluetooth e permessi.")
        }
    }

    fun cancel() = finish(null, "Verifica BLE annullata.")

    private fun finish(characteristics: List<String>?, error: String?) {
        if (!finished.compareAndSet(false, true)) return
        main.removeCallbacks(deadline)
        try { gatt?.disconnect() } catch (_: Exception) { }
        try { gatt?.close() } catch (_: Exception) { }
        gatt = null
        complete(characteristics, error)
    }
}
