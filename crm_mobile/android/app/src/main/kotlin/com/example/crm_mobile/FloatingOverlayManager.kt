package com.tickora.crm

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.ContactsContract
import android.provider.Settings
import android.util.Log
import android.view.Display
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import androidx.core.content.ContextCompat
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.abs

/**
 * Floating Overlay Manager that renders a draggable CardView overlay
 * directly to WindowManager during active phone calls.
 *
 * Compatible with Android 14+ via WindowContext and direct WindowManager integration.
 */

object FloatingOverlayManager {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var layoutParams: WindowManager.LayoutParams? = null

    @Volatile
    var isShowing: Boolean = false
        private set

    @Volatile
    var currentPhoneNumber: String = ""
        private set

    private fun wakeDevice(context: Context) {
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (pm != null) {
                @Suppress("DEPRECATION")
                val wakeLock = pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                            PowerManager.ACQUIRE_CAUSES_WAKEUP or
                            PowerManager.ON_AFTER_RELEASE,
                    "TickoraCRM:CallOverlayWake"
                )
                wakeLock.acquire(10000L)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not acquire WakeLock", e)
        }
    }

    fun show(
        context: Context,
        phoneNumber: String,
        contactName: String = "",
        isTracked: Boolean = false
    ) {
        wakeDevice(context)
        mainHandler.post {
            showInternal(context.applicationContext, phoneNumber, contactName, isTracked)
        }
    }

    /**
     * Called when the call ends (IDLE). Removes overlay and wipes all call data.
     */
    fun hide() {
        mainHandler.post {
            CallReceiver.clearCallData()
            hideInternal()
        }
    }

    /**
     * Called when the user clicks 'X' or taps an action button ('View Details' / 'Add Lead').
     */
    fun dismissAndReset() {
        mainHandler.post {
            CallReceiver.dismissCurrentCall()
            hideInternal()
        }
    }

    @Volatile
    var currentLeadId: String = ""
        private set

    @Volatile
    var currentLeadName: String = ""
        private set

    @Volatile
    var isCurrentLeadExisting: Boolean = false
        private set

    @Volatile
    var currentBadgeMessage: String = ""
        private set

    @Volatile
    var currentAssignedToName: String = ""
        private set

    @Volatile
    var isAssignedToOther: Boolean = false
        private set

    @Volatile
    var isAssignedToMe: Boolean = false
        private set

    @Volatile
    var isQuickAdding: Boolean = false
        private set

    fun updateLeadInfo(
        phoneNumber: String,
        leadName: String,
        leadId: String,
        isExisting: Boolean,
        badgeMessage: String,
        assignedToName: String = "",
        isAssignedToOther: Boolean = false,
        isAssignedToMe: Boolean = false
    ) {
        mainHandler.post {
            Log.d(TAG, "updateLeadInfo: phone=$phoneNumber, name=$leadName, isExisting=$isExisting, badge=$badgeMessage, assignedTo=$assignedToName, isOther=$isAssignedToOther, isMe=$isAssignedToMe")
            if (isExisting || badgeMessage.contains("FAILED", ignoreCase = true)) {
                isQuickAdding = false
            }
            val cleanCurrent = currentPhoneNumber.replace("[^0-9]".toRegex(), "")
            val cleanIncoming = phoneNumber.replace("[^0-9]".toRegex(), "")
            val last10Current = if (cleanCurrent.length >= 10) cleanCurrent.takeLast(10) else cleanCurrent
            val last10Incoming = if (cleanIncoming.length >= 10) cleanIncoming.takeLast(10) else cleanIncoming

            val matches = currentPhoneNumber.isBlank() ||
                currentPhoneNumber == "Unknown Number" ||
                currentPhoneNumber == phoneNumber ||
                (last10Current.isNotEmpty() && last10Incoming.isNotEmpty() && (last10Current == last10Incoming || cleanCurrent.endsWith(last10Incoming) || cleanIncoming.endsWith(last10Current)))

            if (matches) {
                if (currentPhoneNumber.isBlank() || currentPhoneNumber == "Unknown Number") {
                    currentPhoneNumber = phoneNumber
                }
                currentLeadName = leadName
                currentLeadId = leadId
                isCurrentLeadExisting = isExisting
                currentBadgeMessage = badgeMessage
                currentAssignedToName = assignedToName
                this.isAssignedToOther = isAssignedToOther
                this.isAssignedToMe = isAssignedToMe

                val view = floatingView
                if (view != null) {
                    val appContext = view.context
                    updateCardContent(
                        context = appContext,
                        view = view,
                        phoneNumber = currentPhoneNumber,
                        contactName = if (isExisting && leadName.isNotBlank()) leadName else view.findViewById<TextView>(R.id.tvCallerName)?.text?.toString().orEmpty(),
                        isTracked = isExisting,
                        badgeText = badgeMessage,
                        leadId = leadId,
                        assignedToName = assignedToName,
                        isAssignedToOther = isAssignedToOther,
                        isAssignedToMe = isAssignedToMe
                    )
                }
            }
        }
    }

    private const val TAG = "FloatingOverlayManager"

    @SuppressLint("ClickableViewAccessibility", "InflateParams")
    private fun showInternal(
        appContext: Context,
        phoneNumber: String,
        contactName: String,
        isTracked: Boolean
    ) {
        Log.d(TAG, "showInternal called for number: $phoneNumber")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(appContext)) {
            Log.w(TAG, "Cannot show overlay: SYSTEM_ALERT_WINDOW permission is NOT granted!")
            return
        }

        if (CallReceiver.isCurrentCallDismissed &&
            currentPhoneNumber.isNotBlank() &&
            currentPhoneNumber == phoneNumber) {
            Log.d(TAG, "Call was explicitly dismissed by user. Skipping.")
            return
        }

        val isDifferentNumber = currentPhoneNumber.isNotBlank() && currentPhoneNumber != phoneNumber &&
            !phoneNumber.endsWith(currentPhoneNumber.takeLast(10)) &&
            !currentPhoneNumber.endsWith(phoneNumber.takeLast(10))

        if (isDifferentNumber) {
            currentLeadName = ""
            currentLeadId = ""
            isCurrentLeadExisting = isTracked
            currentBadgeMessage = ""
            currentAssignedToName = ""
            isAssignedToOther = false
            isAssignedToMe = false
            isQuickAdding = false
        }

        currentPhoneNumber = phoneNumber

        // Resolve contact name from device contacts if not provided
        val resolvedName = if (contactName.isNotBlank()) {
            contactName
        } else {
            resolveContactName(appContext, phoneNumber)
        }
        val isRecognized = isTracked || isCurrentLeadExisting
        val displayName = when {
            isCurrentLeadExisting && currentLeadName.isNotBlank() -> currentLeadName
            contactName.isNotBlank() -> contactName
            resolvedName.isNotBlank() -> resolvedName
            else -> "Unknown Caller"
        }
        val displayBadge = when {
            currentBadgeMessage.isNotBlank() -> currentBadgeMessage
            isRecognized -> "LEAD ALREADY EXISTS"
            else -> "NEW NUMBER"
        }

        // Notify Flutter over MethodChannel to check if lead exists in CRM
        try {
            MainActivity.methodChannelInstance?.let { channel ->
                mainHandler.post {
                    channel.invokeMethod("onCallDetected", mapOf("phoneNumber" to phoneNumber))
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error notifying Flutter about call", e)
        }

        val windowType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        // Obtain visual WindowManager (using WindowContext on Android 12+ for lock-screen overlay)
        val visualContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                appContext.createWindowContext(windowType, null)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to create WindowContext, using appContext", e)
                appContext
            }
        } else {
            appContext
        }

        val wm = try {
            visualContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get WindowManager", e)
            null
        } ?: return
        windowManager = wm

        // If overlay is already attached, simply update its content smoothly
        if (floatingView != null) {
            Log.d(TAG, "Overlay already visible, updating content for $phoneNumber")
            updateCardContent(
                context = visualContext,
                view = floatingView!!,
                phoneNumber = phoneNumber,
                contactName = displayName,
                isTracked = isRecognized,
                badgeText = displayBadge,
                leadId = currentLeadId,
                assignedToName = currentAssignedToName,
                isAssignedToOther = isAssignedToOther,
                isAssignedToMe = isAssignedToMe
            )
            return
        }

        // Inflate overlay layout with a themed context wrapper to ensure all theme attributes resolve
        val themedContext = android.view.ContextThemeWrapper(visualContext, android.R.style.Theme_DeviceDefault_DayNight)
        val inflater = LayoutInflater.from(themedContext)
        val view = try {
            inflater.inflate(R.layout.layout_floating_card, null)
        } catch (e: Exception) {
            Log.e(TAG, "Error inflating layout_floating_card", e)
            return
        }
        floatingView = view

        @Suppress("DEPRECATION")
        val overlayFlags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            windowType,
            overlayFlags,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER
            x = 0
            y = 0
        }
        layoutParams = params

        setupInteractions(themedContext, view, params, wm, phoneNumber, displayName, isRecognized)

        try {
            wm.addView(view, params)
            isShowing = true
            Log.i(TAG, "Floating overlay successfully shown for $phoneNumber")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to add overlay view to WindowManager", e)
            floatingView = null
            isShowing = false
        }
    }

    private fun setupInteractions(
        context: Context,
        view: View,
        params: WindowManager.LayoutParams,
        wm: WindowManager,
        phoneNumber: String,
        contactName: String,
        isTracked: Boolean
    ) {
        val cardView = view.findViewById<View>(R.id.floatingCardView) ?: view
        val btnClose = view.findViewById<ImageView>(R.id.btnCloseOverlay)

        val displayBadge = if (currentBadgeMessage.isNotBlank()) currentBadgeMessage else (if (isTracked) "LEAD ALREADY EXISTS" else "NEW NUMBER")
        updateCardContent(
            context = context,
            view = view,
            phoneNumber = phoneNumber,
            contactName = contactName,
            isTracked = isTracked,
            badgeText = displayBadge,
            leadId = currentLeadId,
            assignedToName = currentAssignedToName,
            isAssignedToOther = isAssignedToOther,
            isAssignedToMe = isAssignedToMe
        )

        btnClose?.setOnClickListener {
            dismissAndReset()
        }

        val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var isDragging = false

        cardView.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    isDragging = false
                    false
                }
                MotionEvent.ACTION_MOVE -> {
                    val deltaX = (event.rawX - initialTouchX).toInt()
                    val deltaY = (event.rawY - initialTouchY).toInt()

                    if (!isDragging && (abs(deltaX) > touchSlop || abs(deltaY) > touchSlop)) {
                        isDragging = true
                    }

                    if (isDragging) {
                        params.x = initialX + deltaX
                        params.y = initialY + deltaY
                        try {
                            wm.updateViewLayout(view, params)
                        } catch (e: Exception) {
                            e.printStackTrace()
                        }
                        true
                    } else {
                        false
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    val wasDragging = isDragging
                    isDragging = false
                    wasDragging
                }
                else -> false
            }
        }
    }

    private fun updateCardContent(
        context: Context,
        view: View,
        phoneNumber: String,
        contactName: String,
        isTracked: Boolean,
        badgeText: String = "",
        leadId: String = "",
        assignedToName: String = "",
        isAssignedToOther: Boolean = false,
        isAssignedToMe: Boolean = false
    ) {
        val tvStatusBadge: TextView = view.findViewById(R.id.tvStatusBadge)
        val tvCallerName: TextView = view.findViewById(R.id.tvCallerName)
        val tvCallerNumber: TextView = view.findViewById(R.id.tvCallerNumber)
        val tvLeadMessage: TextView? = view.findViewById(R.id.tvLeadMessage)
        val btnCardAction: Button = view.findViewById(R.id.btnCardAction)

        tvCallerNumber.text = phoneNumber.ifBlank { "Unknown Number" }

        if (isAssignedToOther) {
            // Case 1: Assigned to other user -> Show who it is assigned to, DO NOT allow tapping View button
            val assignedDisplay = if (assignedToName.isNotBlank()) assignedToName else "Another User"
            tvStatusBadge.text = "ASSIGNED TO ${assignedDisplay.uppercase()}"
            tvStatusBadge.setBackgroundResource(R.drawable.bg_badge_tracked)
            tvStatusBadge.setTextColor(ContextCompat.getColor(context, R.color.badge_tracked_text))

            tvCallerName.text = contactName.ifBlank { "Existing Lead" }
            tvLeadMessage?.text = "Assigned to: $assignedDisplay"
            tvLeadMessage?.visibility = View.VISIBLE

            btnCardAction.text = "Assigned to $assignedDisplay"
            btnCardAction.isEnabled = false
            btnCardAction.alpha = 0.65f
            btnCardAction.setOnClickListener(null)
        } else if (isTracked || isCurrentLeadExisting) {
            // Case 2: Assigned to current user or existing in CRM -> allow viewing details
            btnCardAction.alpha = 1.0f
            tvStatusBadge.text = if (badgeText.isNotBlank()) badgeText else "LEAD ALREADY EXISTS"
            tvStatusBadge.setBackgroundResource(R.drawable.bg_badge_tracked)
            tvStatusBadge.setTextColor(ContextCompat.getColor(context, R.color.badge_tracked_text))

            tvCallerName.text = contactName.ifBlank { "Existing Lead" }
            tvLeadMessage?.text = "Lead already exists in CRM"
            tvLeadMessage?.visibility = View.VISIBLE

            btnCardAction.text = "View Details"
            btnCardAction.isEnabled = true
            val targetLeadId = if (leadId.isNotBlank()) leadId else currentLeadId
            btnCardAction.setOnClickListener {
                openAppWithAction(context, "ACTION_VIEW_DETAILS", phoneNumber, targetLeadId)
            }
        } else {
            // Case 3: Not assigned to anyone (or new number) -> ONLY allow tapping the Invite button
            btnCardAction.alpha = 1.0f
            tvStatusBadge.text = if (badgeText.isNotBlank()) badgeText else "NEW NUMBER"
            tvStatusBadge.setBackgroundResource(R.drawable.bg_badge_untracked)
            tvStatusBadge.setTextColor(ContextCompat.getColor(context, R.color.badge_untracked_text))

            tvCallerName.text = contactName.ifBlank { "Unknown Lead" }
            tvLeadMessage?.visibility = View.GONE

            if (isQuickAdding) {
                btnCardAction.text = "Inviting..."
                btnCardAction.isEnabled = false
            } else {
                btnCardAction.text = if (badgeText.contains("FAILED", ignoreCase = true)) "Retry Invite" else "Invite"
                btnCardAction.isEnabled = true
                btnCardAction.setOnClickListener {
                    btnCardAction.text = "Inviting..."
                    btnCardAction.isEnabled = false
                    quickAddLeadFromOverlay(phoneNumber, context)
                }
            }
        }
    }

    private fun quickAddLeadFromOverlay(phoneNumber: String, context: Context) {
        var activePhone = phoneNumber
        if (activePhone.replace("[^0-9]".toRegex(), "").length < 7) {
            val fallback = listOfNotNull(
                CallReceiver.lastRingingNumber,
                CallReceiver.lastOutgoingNumber,
                CallReceiver.queryLatestCallLogNumber(context)
            ).firstOrNull { it.replace("[^0-9]".toRegex(), "").length >= 7 } ?: ""

            if (fallback.isNotBlank()) {
                activePhone = fallback
                currentPhoneNumber = fallback
            }
        }

        val digits = activePhone.replace("[^0-9]".toRegex(), "")
        if (digits.length < 5) {
            isQuickAdding = false
            floatingView?.findViewById<Button>(R.id.btnCardAction)?.apply {
                text = "Invite"
                isEnabled = true
            }
            android.widget.Toast.makeText(context, "Waiting for phone number...", android.widget.Toast.LENGTH_SHORT).show()
            return
        }

        isQuickAdding = true
        val channel = MainActivity.methodChannelInstance
        if (channel != null) {
            mainHandler.post {
                channel.invokeMethod("onQuickAddLeadFromOverlay", mapOf("phoneNumber" to activePhone))
            }
        } else {
            Log.d(TAG, "methodChannelInstance is null, performing direct background invite from overlay")
            performNativeQuickInvite(context, activePhone)
        }
    }

    private fun performNativeQuickInvite(context: Context, phoneNumber: String) {
        Thread {
            try {
                val cleanDigits = phoneNumber.replace("[^0-9]".toRegex(), "")
                val phoneToSave = if (cleanDigits.length >= 10) cleanDigits.takeLast(10) else cleanDigits

                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val token = prefs.getString("flutter.token", "") ?: ""
                val userId = prefs.getString("flutter.userId", "") ?: ""

                val endpoint = "http://50.117.0.165:8080/api/crm/lead-service/leads/quick-invite"
                val url = URL(endpoint)
                val conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 10000
                    readTimeout = 10000
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json; charset=UTF-8")
                    setRequestProperty("Accept", "application/json")
                    if (token.isNotBlank()) {
                        setRequestProperty("Authorization", "Bearer $token")
                    }
                }

                val jsonPayload = JSONObject().apply {
                    put("phone", phoneToSave)
                    put("mobile", phoneToSave)
                    put("mobileNumber", phoneToSave)
                    put("firstName", "quick call user")
                    put("name", "quick call user")
                    if (userId.isNotBlank()) {
                        put("assignedTo", userId)
                        put("ownerUserId", userId)
                    }
                }

                OutputStreamWriter(conn.outputStream, "UTF-8").use { writer ->
                    writer.write(jsonPayload.toString())
                    writer.flush()
                }

                val responseCode = conn.responseCode
                Log.d(TAG, "performNativeQuickInvite: responseCode=$responseCode")

                if (responseCode in 200..204) {
                    mainHandler.post {
                        updateLeadInfo(
                            phoneNumber = phoneNumber,
                            leadName = "quick call user",
                            leadId = "",
                            isExisting = true,
                            badgeMessage = "LEAD ALREADY EXISTS",
                            assignedToName = "You",
                            isAssignedToOther = false,
                            isAssignedToMe = true
                        )
                        android.widget.Toast.makeText(context, "Lead invited successfully", android.widget.Toast.LENGTH_SHORT).show()
                    }
                } else {
                    mainHandler.post {
                        isQuickAdding = false
                        floatingView?.findViewById<Button>(R.id.btnCardAction)?.apply {
                            text = "Retry Invite"
                            isEnabled = true
                        }
                        android.widget.Toast.makeText(context, "Failed to invite lead ($responseCode)", android.widget.Toast.LENGTH_SHORT).show()
                    }
                }
                conn.disconnect()
            } catch (e: Exception) {
                Log.e(TAG, "Error in performNativeQuickInvite", e)
                mainHandler.post {
                    isQuickAdding = false
                    floatingView?.findViewById<Button>(R.id.btnCardAction)?.apply {
                        text = "Retry Invite"
                        isEnabled = true
                    }
                    android.widget.Toast.makeText(context, "Invite error: ${e.message}", android.widget.Toast.LENGTH_SHORT).show()
                }
            }
        }.start()
    }

    private fun openAppWithAction(context: Context, action: String, phoneNumber: String, leadId: String = "") {
        val appIntent = Intent(context, MainActivity::class.java).apply {
            this.action = action
            putExtra("EXTRA_PHONE_NUMBER", phoneNumber)
            putExtra("EXTRA_LEAD_ID", leadId)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        context.startActivity(appIntent)
        dismissAndReset()
    }

    private fun resolveContactName(context: Context, phoneNumber: String): String {
        if (phoneNumber.isBlank()) return ""
        return try {
            val uri = Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                Uri.encode(phoneNumber)
            )
            val projection = arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME)
            context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    cursor.getString(0) ?: ""
                } else ""
            } ?: ""
        } catch (_: Exception) {
            ""
        }
    }

    private fun hideInternal() {
        val view = floatingView
        val wm = windowManager
        if (view != null && wm != null) {
            try {
                wm.removeView(view)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        floatingView = null
        windowManager = null
        layoutParams = null
        isShowing = false
        isQuickAdding = false
        currentPhoneNumber = ""
        currentLeadId = ""
        currentLeadName = ""
        isCurrentLeadExisting = false
        currentBadgeMessage = ""
        currentAssignedToName = ""
        isAssignedToOther = false
        isAssignedToMe = false
    }
}
