package com.example.syncbeat

import android.os.SystemClock
import android.util.Log

/** Fixed codes and counters only. Never pass exception messages or command payloads. */
internal object ZeppDiagnostics {
    fun record(phase: String, detail: String = "") {
        Log.i("SyncBeatZeppDiag", "wallMs=${System.currentTimeMillis()} monoMs=${SystemClock.elapsedRealtime()} layer=native phase=$phase $detail")
    }
}
