package com.tickora.crm

import android.net.Uri
import android.os.Build
import android.telecom.CallRedirectionService
import android.telecom.PhoneAccountHandle
import android.util.Log
import androidx.annotation.RequiresApi

/**
 * Modern Telecom CallRedirectionService introduced in Android 10 (API 29).
 * Intercepts outgoing calls placed from any dialer, extracts destination phone number,
 * displays the floating card overlay, and allows the call to proceed unmodified.
 */
@RequiresApi(Build.VERSION_CODES.Q)
class AppCallRedirectionService : CallRedirectionService() {

    companion object {
        private const val TAG = "AppCallRedirection"
    }

    override fun onPlaceCall(
        handle: Uri,
        initialPhoneAccount: PhoneAccountHandle,
        allowInteractiveResponse: Boolean
    ) {
        try {
            val raw = handle.schemeSpecificPart ?: handle.toString().removePrefix("tel:")
            val phoneNumber = Uri.decode(raw).removePrefix("tel:").trim()

            Log.d(TAG, "onPlaceCall: outgoing=$phoneNumber")

            if (phoneNumber.isNotBlank()) {
                CallReceiver.startNewCall(phoneNumber, isOutgoing = true)

                if (!CallReceiver.isCurrentCallDismissed) {
                    FloatingOverlayManager.show(
                        context = applicationContext,
                        phoneNumber = phoneNumber
                    )
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in onPlaceCall", e)
        }

        // Always let the call proceed unmodified
        placeCallUnmodified()
    }
}
