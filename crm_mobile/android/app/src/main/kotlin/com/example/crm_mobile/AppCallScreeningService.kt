package com.tickora.crm

import android.net.Uri
import android.os.Build
import android.telecom.Call
import android.telecom.CallScreeningService
import android.util.Log
import androidx.annotation.RequiresApi

/**
 * Telecom CallScreeningService (Caller ID & Spam role).
 * Detects incoming and outgoing calls and their phone numbers in real time on Android 10+ (API 29+).
 */
@RequiresApi(Build.VERSION_CODES.Q)
class AppCallScreeningService : CallScreeningService() {

    companion object {
        private const val TAG = "AppCallScreening"
    }

    override fun onScreenCall(callDetails: Call.Details) {
        try {
            val handleUri = callDetails.handle
            val gatewayUri = callDetails.gatewayInfo?.originalAddress
            val intentNumber = callDetails.intentExtras?.getString(android.telephony.TelephonyManager.EXTRA_INCOMING_NUMBER)
            val extrasNumber = callDetails.extras?.getString(android.telephony.TelephonyManager.EXTRA_INCOMING_NUMBER)

            val raw = handleUri?.schemeSpecificPart
                ?: gatewayUri?.schemeSpecificPart
                ?: intentNumber
                ?: extrasNumber
                ?: handleUri?.toString()?.removePrefix("tel:")
                ?: ""
            val phoneNumber = Uri.decode(raw).removePrefix("tel:").trim()
            val isOutgoing = callDetails.callDirection != Call.Details.DIRECTION_INCOMING

            Log.d(TAG, "onScreenCall received: phone=$phoneNumber, isOutgoing=$isOutgoing")

            if (phoneNumber.isNotBlank() && !phoneNumber.equals("Unknown Number", ignoreCase = true)) {
                CallReceiver.startNewCall(phoneNumber, isOutgoing = isOutgoing)

                if (!CallReceiver.isCurrentCallDismissed) {
                    FloatingOverlayManager.show(
                        context = applicationContext,
                        phoneNumber = phoneNumber
                    )
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in onScreenCall", e)
        }

        // Always allow the call to ring and connect normally
        val response = CallResponse.Builder()
            .setDisallowCall(false)
            .setRejectCall(false)
            .setSkipCallLog(false)
            .setSkipNotification(false)
            .build()
        respondToCall(callDetails, response)
    }
}
