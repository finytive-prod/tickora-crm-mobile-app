package com.tickora.crm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.CallLog
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.content.ContextCompat

class CallReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "CallReceiver"

        @Volatile
        var lastRingingNumber: String? = null

        @Volatile
        var lastOutgoingNumber: String? = null

        @Volatile
        var lastState: String? = null

        @Volatile
        var currentCallStartTime: Long = 0L

        @Volatile
        var isCurrentCallDismissed: Boolean = false

        fun startNewCall(number: String, isOutgoing: Boolean) {
            val clean = number.trim()
            if (clean.isBlank() || clean.equals("Unknown Number", ignoreCase = true)) return

            isCurrentCallDismissed = false
            currentCallStartTime = System.currentTimeMillis()

            if (isOutgoing) {
                lastOutgoingNumber = clean
                lastRingingNumber = null
            } else {
                lastRingingNumber = clean
                lastOutgoingNumber = null
            }
            Log.d(TAG, "startNewCall: number=$clean, isOutgoing=$isOutgoing")
        }

        fun clearCallData() {
            Log.d(TAG, "clearCallData")
            lastRingingNumber = null
            lastOutgoingNumber = null
            lastState = null
            currentCallStartTime = 0L
            isCurrentCallDismissed = false
        }

        fun dismissCurrentCall() {
            Log.d(TAG, "dismissCurrentCall")
            isCurrentCallDismissed = true
            lastRingingNumber = null
            lastOutgoingNumber = null
        }

        fun handleCallConnected(context: Context, activeNumber: String) {
            val displayNum = if (activeNumber.isNotBlank()) activeNumber else "Incoming Call"
            Log.d(TAG, "handleCallConnected: showing overlay for $displayNum")
            FloatingOverlayManager.show(
                context = context,
                phoneNumber = displayNum
            )
        }

        fun queryLatestCallLogNumber(context: Context): String? {
            if (ContextCompat.checkSelfPermission(context, android.Manifest.permission.READ_CALL_LOG)
                != PackageManager.PERMISSION_GRANTED) {
                return null
            }
            return try {
                val projection = arrayOf(CallLog.Calls.NUMBER)
                context.contentResolver.query(
                    CallLog.Calls.CONTENT_URI,
                    projection,
                    null,
                    null,
                    "${CallLog.Calls.DATE} DESC LIMIT 1"
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        cursor.getString(0) ?: ""
                    } else null
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error querying CallLog fallback", e)
                null
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        Log.d(TAG, "onReceive: action=$action")

        if (action == "com.tickora.crm.TEST_OVERLAY") {
            val phone = intent.getStringExtra("phoneNumber") ?: "8925966055"
            Log.d(TAG, "Test overlay requested for $phone")
            startNewCall(phone, isOutgoing = false)
            FloatingOverlayManager.show(context, phone)
            return
        }

        if (action == Intent.ACTION_NEW_OUTGOING_CALL) {
            val outgoingNumber = intent.getStringExtra(Intent.EXTRA_PHONE_NUMBER)
            Log.d(TAG, "ACTION_NEW_OUTGOING_CALL: number=$outgoingNumber")
            if (!outgoingNumber.isNullOrBlank()) {
                startNewCall(outgoingNumber, isOutgoing = true)
                handleCallConnected(context, outgoingNumber)
            }
            return
        }

        if (action == TelephonyManager.ACTION_PHONE_STATE_CHANGED) {
            val stateStr = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
            val incomingNumber = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
            Log.d(TAG, "ACTION_PHONE_STATE_CHANGED: state=$stateStr, incomingNumber=$incomingNumber")

            val prevState = lastState
            if (stateStr == prevState) return
            lastState = stateStr

            when (stateStr) {
                TelephonyManager.EXTRA_STATE_RINGING -> {
                    isCurrentCallDismissed = false
                    val number = if (!incomingNumber.isNullOrBlank() && incomingNumber != "Unknown Number") {
                        incomingNumber
                    } else if (!lastRingingNumber.isNullOrBlank() && lastRingingNumber != "Unknown Number") {
                        lastRingingNumber!!
                    } else {
                        queryLatestCallLogNumber(context) ?: ""
                    }
                    val finalNumber = if (number.isNotBlank() && number != "Unknown Number") number else "Unknown Number"
                    if (finalNumber != "Unknown Number") {
                        startNewCall(finalNumber, isOutgoing = false)
                    }
                    handleCallConnected(context, finalNumber)
                }

                TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                    var activeNumber = if (!lastRingingNumber.isNullOrBlank() && lastRingingNumber != "Unknown Number") {
                        lastRingingNumber!!
                    } else if (!lastOutgoingNumber.isNullOrBlank() && lastOutgoingNumber != "Unknown Number") {
                        lastOutgoingNumber!!
                    } else {
                        ""
                    }
                    if (activeNumber.isBlank() || activeNumber == "Unknown Number") {
                        val queryNum = queryLatestCallLogNumber(context) ?: ""
                        if (queryNum.isNotBlank() && queryNum != "Unknown Number") activeNumber = queryNum
                    }
                    val finalNumber = if (activeNumber.isNotBlank() && activeNumber != "Unknown Number") activeNumber else "Unknown Number"
                    isCurrentCallDismissed = false
                    if (!FloatingOverlayManager.isShowing) {
                        handleCallConnected(context, finalNumber)
                    } else if (FloatingOverlayManager.currentPhoneNumber.isBlank() || FloatingOverlayManager.currentPhoneNumber == "Unknown Number") {
                        if (finalNumber != "Unknown Number") {
                            handleCallConnected(context, finalNumber)
                        }
                    }
                }

                TelephonyManager.EXTRA_STATE_IDLE -> {
                    val wasMissed = prevState == TelephonyManager.EXTRA_STATE_RINGING
                    val rawNum = if (wasMissed) lastRingingNumber else (lastOutgoingNumber ?: lastRingingNumber)
                    FloatingOverlayManager.hide()
                    clearCallData()

                    MainActivity.methodChannelInstance?.let { ch ->
                        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                            val finalNum = if (!rawNum.isNullOrBlank() && rawNum != "Unknown Number") {
                                rawNum
                            } else {
                                queryLatestCallLogNumber(context) ?: ""
                            }
                            Log.d(TAG, "Call ended broadcast to Flutter: number=$finalNum, isMissed=$wasMissed")
                            ch.invokeMethod("onCallEnded", mapOf(
                                "phoneNumber" to finalNum,
                                "isMissed" to wasMissed
                            ))
                        }, 800)
                    }
                }
            }
        }
    }
}
