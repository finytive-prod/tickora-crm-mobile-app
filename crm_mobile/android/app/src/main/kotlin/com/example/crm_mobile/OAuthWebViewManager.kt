package com.tickora.crm

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.app.Activity
import android.app.Dialog
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.os.Build
import android.util.Log
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.animation.LinearInterpolator
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ProgressBar

object OAuthWebViewManager {
    private const val TAG = "OAuthWebViewManager"
    private var activeDialog: Dialog? = null

    @SuppressLint("SetJavaScriptEnabled")
    fun open(
        activity: Activity,
        url: String,
        redirectUri: String,
        onComplete: (callbackUrl: String?) -> Unit
    ) {
        activity.runOnUiThread {
            try {
                activeDialog?.dismiss()
                activeDialog = null

                val dialog = Dialog(activity, android.R.style.Theme_DeviceDefault_Light_NoActionBar_Fullscreen)
                dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)
                activeDialog = dialog

                // Root fullscreen container
                val rootLayout = FrameLayout(activity).apply {
                    layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                    )
                    setBackgroundColor(0xFFFFFFFF.toInt())
                }

                // In-App WebView (full screen without top bar)
                val webView = WebView(activity).apply {
                    layoutParams = FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                    )
                }

                // Thin progress bar indicator at the top edge
                val progressBar = ProgressBar(activity, null, android.R.attr.progressBarStyleHorizontal).apply {
                    layoutParams = FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        dpToPx(activity, 3)
                    ).apply {
                        gravity = Gravity.TOP
                    }
                    max = 100
                    progress = 0
                }

                // Custom Orbit Loader Overlay View
                val loadingContainer = FrameLayout(activity).apply {
                    layoutParams = FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                    )
                    setBackgroundColor(0xFFFFFFFF.toInt())
                }

                val loaderView = OrbitLoaderView(activity, 64f).apply {
                    layoutParams = FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                    )
                }
                loadingContainer.addView(loaderView)

                rootLayout.addView(webView)
                rootLayout.addView(progressBar)
                rootLayout.addView(loadingContainer)

                webView.settings.apply {
                    javaScriptEnabled = true
                    domStorageEnabled = true
                    databaseEnabled = true
                    useWideViewPort = true
                    loadWithOverviewMode = true
                    cacheMode = WebSettings.LOAD_DEFAULT
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
                    }
                }

                fun hideLoader() {
                    if (loadingContainer.visibility == View.VISIBLE) {
                        loadingContainer.animate()
                            .alpha(0f)
                            .setDuration(250)
                            .withEndAction {
                                loadingContainer.visibility = View.GONE
                                loaderView.stop()
                            }
                            .start()
                    }
                }

                fun showLoader() {
                    loadingContainer.alpha = 1f
                    loadingContainer.visibility = View.VISIBLE
                    loaderView.start()
                }

                webView.webChromeClient = object : WebChromeClient() {
                    override fun onProgressChanged(view: WebView?, newProgress: Int) {
                        super.onProgressChanged(view, newProgress)
                        progressBar.progress = newProgress
                        if (newProgress >= 90) {
                            hideLoader()
                            progressBar.visibility = View.GONE
                        } else {
                            progressBar.visibility = View.VISIBLE
                        }
                    }
                }

                var hasIntercepted = false

                webView.webViewClient = object : WebViewClient() {
                    private fun checkUrl(checkUrl: String?): Boolean {
                        if (checkUrl == null || hasIntercepted) return false
                        Log.d(TAG, "WebView loading URL: $checkUrl")

                        val cleanCheck = checkUrl.trim()
                        val isCallback = cleanCheck.startsWith(redirectUri, ignoreCase = true) ||
                                (cleanCheck.contains("/callback", ignoreCase = true) && cleanCheck.contains("code="))

                        if (isCallback) {
                            hasIntercepted = true
                            Log.d(TAG, "Intercepted OAuth callback URL: $cleanCheck")
                            showLoader()
                            dialog.dismiss()
                            onComplete(cleanCheck)
                            return true
                        }
                        return false
                    }

                    override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                        val reqUrl = request?.url?.toString()
                        if (checkUrl(reqUrl)) return true
                        return false
                    }

                    @Deprecated("Deprecated in Java")
                    override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
                        if (checkUrl(url)) return true
                        return false
                    }

                    override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                        super.onPageStarted(view, url, favicon)
                        checkUrl(url)
                    }

                    override fun onPageFinished(view: WebView?, url: String?) {
                        super.onPageFinished(view, url)
                        checkUrl(url)
                        hideLoader()
                    }

                    override fun doUpdateVisitedHistory(view: WebView?, url: String?, isReload: Boolean) {
                        super.doUpdateVisitedHistory(view, url, isReload)
                        checkUrl(url)
                    }
                }

                dialog.setContentView(rootLayout)

                // Back button / gesture navigation
                dialog.setOnKeyListener { _, keyCode, event ->
                    if (keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_UP) {
                        if (webView.canGoBack()) {
                            webView.goBack()
                        } else {
                            dialog.dismiss()
                            if (!hasIntercepted) {
                                onComplete(null)
                            }
                        }
                        true
                    } else {
                        false
                    }
                }

                dialog.setOnCancelListener {
                    if (!hasIntercepted) {
                        onComplete(null)
                    }
                }

                dialog.show()
                webView.loadUrl(url)
            } catch (e: Exception) {
                Log.e(TAG, "Error opening OAuth WebView Dialog", e)
                onComplete(null)
            }
        }
    }

    fun dismiss() {
        activeDialog?.dismiss()
        activeDialog = null
    }

    private fun dpToPx(activity: Activity, dp: Int): Int {
        val density = activity.resources.displayMetrics.density
        return (dp * density).toInt()
    }
}

/**
 * Custom Android View that replicates the Flutter [SpinningLogo] loader:
 * - Central rounded app logo
 * - Circular line orbit track (#DCEAF9)
 * - 3 synchronized balls revolving continuously in a circle:
 *   - Top: Vibrant Blue (#147BD1)
 *   - Bottom-Right: Cyan (#00A9CF)
 *   - Bottom-Left: Royal Blue (#3B59D8)
 */
class OrbitLoaderView(context: Context, private val logoSizeDp: Float = 64f) : View(context) {
    private var progress: Float = 0f
    private val animator: ValueAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 2000L
        repeatCount = ValueAnimator.INFINITE
        interpolator = LinearInterpolator()
        addUpdateListener {
            progress = it.animatedValue as Float
            invalidate()
        }
    }

    private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFDCEAF9.toInt()
        style = Paint.Style.STROKE
    }

    private val ballPaints = arrayOf(
        Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF147BD1.toInt(); style = Paint.Style.FILL }, // Top
        Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF00A9CF.toInt(); style = Paint.Style.FILL }, // Bottom-Right
        Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF3B59D8.toInt(); style = Paint.Style.FILL }  // Bottom-Left
    )

    private var logoBitmap: Bitmap? = null
    private val logoPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val logoRect = RectF()
    private val logoPath = Path()

    init {
        loadLogo()
        animator.start()
    }

    fun start() {
        if (!animator.isRunning) {
            animator.start()
        }
    }

    fun stop() {
        if (animator.isRunning) {
            animator.cancel()
        }
    }

    private fun loadLogo() {
        try {
            // 1. Try to load directly from Flutter APK assets
            val assetManager = context.assets
            val inputStream = try {
                assetManager.open("flutter_assets/assets/images/logo.png")
            } catch (_: Exception) {
                try {
                    assetManager.open("flutter_assets/assets/images/logo.webp")
                } catch (_: Exception) {
                    null
                }
            }

            if (inputStream != null) {
                logoBitmap = BitmapFactory.decodeStream(inputStream)
                inputStream.close()
            } else {
                // 2. Fallback to application launcher icon
                val drawable = context.packageManager.getApplicationIcon(context.packageName)
                val sizePx = dpToPx(logoSizeDp).toInt()
                val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bitmap)
                drawable.setBounds(0, 0, sizePx, sizePx)
                drawable.draw(canvas)
                logoBitmap = bitmap
            }
        } catch (e: Exception) {
            Log.e("OrbitLoaderView", "Error loading logo bitmap", e)
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        start()
    }

    override fun onDetachedFromWindow() {
        stop()
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val cx = width / 2f
        val cy = height / 2f

        val logoSizePx = dpToPx(logoSizeDp)
        val orbitRadius = logoSizePx * 0.72f
        val ballRadius = Math.max(dpToPx(3.5f), logoSizePx * 0.085f)
        val strokeWidth = Math.max(dpToPx(1.5f), logoSizePx * 0.025f)

        trackPaint.strokeWidth = strokeWidth

        // 1. Draw circular orbit line track
        canvas.drawCircle(cx, cy, orbitRadius, trackPaint)

        // 2. Draw 3 balls moving synchronously along the circular line
        val baseAngle = progress * 2f * Math.PI.toFloat()
        for (i in 0 until 3) {
            // -Math.PI / 2 starts index 0 at top (12 o'clock)
            val angle = baseAngle - (Math.PI.toFloat() / 2f) + (i * 2f * Math.PI.toFloat() / 3f)
            val bx = cx + orbitRadius * Math.cos(angle.toDouble()).toFloat()
            val by = cy + orbitRadius * Math.sin(angle.toDouble()).toFloat()
            canvas.drawCircle(bx, by, ballRadius, ballPaints[i])
        }

        // 3. Draw Center Logo with rounded squircle corners
        logoBitmap?.let { bmp ->
            val left = cx - (logoSizePx / 2f)
            val top = cy - (logoSizePx / 2f)
            logoRect.set(left, top, left + logoSizePx, top + logoSizePx)
            val cornerRadius = logoSizePx * 0.22f

            canvas.save()
            logoPath.reset()
            logoPath.addRoundRect(logoRect, cornerRadius, cornerRadius, Path.Direction.CW)
            canvas.clipPath(logoPath)
            canvas.drawBitmap(bmp, null, logoRect, logoPaint)
            canvas.restore()
        }
    }

    private fun dpToPx(dp: Float): Float {
        return dp * resources.displayMetrics.density
    }
}
