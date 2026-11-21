package com.hyperbot.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.annotation.SuppressLint
import android.graphics.Color
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

/**
 * Hyper-Bot: floating bubble + panel, and the taps/swipes that drive Roblox.
 * Input-only: it touches the screen like a finger would. It never modifies Roblox.
 */
class BotService : AccessibilityService() {

    companion object {
        var instance: BotService? = null
        private val CYAN: Int = Color.rgb(0, 150, 230)
        private val DARK: Int = Color.argb(230, 16, 24, 32)
    }

    private lateinit var wm: WindowManager
    private lateinit var prefs: Prefs
    private val h = Handler(Looper.getMainLooper())

    private var bubble: TextView? = null
    private var bubbleLp: WindowManager.LayoutParams? = null
    private var panel: LinearLayout? = null
    private var autoButton: Button? = null
    private val markers = mutableMapOf<String, Pair<TextView, WindowManager.LayoutParams>>()

    private var auto = false
    private var lastChat = 0L
    private var lastIntro = 0L
    private var lastEmote = 0L
    private var busyUntil = 0L

    // ---------------------------------------------------------------- lifecycle

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        prefs = Prefs(this)
        showBubble()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Not used: Hyper-Bot doesn't read other apps' events.
    }

    override fun onInterrupt() {
        stopAuto()
    }

    override fun onDestroy() {
        stopAuto()
        removeAllViews()
        instance = null
        super.onDestroy()
    }

    // ---------------------------------------------------------------- helpers

    private fun dp(v: Int): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()

    private fun screenW(): Float =
        if (Build.VERSION.SDK_INT >= 30) wm.currentWindowMetrics.bounds.width().toFloat()
        else legacyMetrics().widthPixels.toFloat()

    private fun screenH(): Float =
        if (Build.VERSION.SDK_INT >= 30) wm.currentWindowMetrics.bounds.height().toFloat()
        else legacyMetrics().heightPixels.toFloat()

    @Suppress("DEPRECATION")
    private fun legacyMetrics(): DisplayMetrics {
        val m = DisplayMetrics()
        wm.defaultDisplay.getRealMetrics(m)
        return m
    }

    /** Screen position (pixels) of a calibrated control. */
    private fun pos(name: String): Pair<Float, Float> {
        val f = prefs.point(name)
        return Pair(f.first * screenW(), f.second * screenH())
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()

    private fun overlayParams(w: Int, hgt: Int, x: Int, y: Int) = WindowManager.LayoutParams(
        w, hgt,
        WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
        PixelFormat.TRANSLUCENT
    ).apply {
        gravity = Gravity.TOP or Gravity.START
        this.x = x
        this.y = y
    }

    private fun round(color: Int, radiusDp: Int, stroke: Int = 0): GradientDrawable =
        GradientDrawable().apply {
            setColor(color)
            cornerRadius = dp(radiusDp).toFloat()
            if (stroke != 0) setStroke(dp(2), stroke)
        }

    /** Drag a floating view around; a short tap (no drag) calls onTap. */
    @SuppressLint("ClickableViewAccessibility")
    private fun makeDraggable(v: View, lp: WindowManager.LayoutParams, onTap: (() -> Unit)?) {
        var startX = 0
        var startY = 0
        var touchX = 0f
        var touchY = 0f
        var moved = false
        v.setOnTouchListener { _, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = lp.x; startY = lp.y; touchX = e.rawX; touchY = e.rawY; moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (e.rawX - touchX).toInt()
                    val dy = (e.rawY - touchY).toInt()
                    if (abs(dx) > 10 || abs(dy) > 10) moved = true
                    lp.x = startX + dx
                    lp.y = startY + dy
                    try { wm.updateViewLayout(v, lp) } catch (_: Exception) {}
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) onTap?.invoke()
                    true
                }
                else -> false
            }
        }
    }

    // ---------------------------------------------------------------- bubble + panel

    fun showBubble() {
        if (bubble != null) return
        val size = dp(56)
        val b = TextView(this).apply {
            text = "HB"
            textSize = 16f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            background = round(CYAN, 28, Color.WHITE)
        }
        val lp = overlayParams(size, size, dp(8), dp(120))
        makeDraggable(b, lp) { togglePanel() }
        wm.addView(b, lp)
        bubble = b
        bubbleLp = lp
    }

    private fun togglePanel() {
        if (panel != null) {
            hidePanel()
            return
        }
        val p = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), dp(8), dp(8), dp(8))
            background = round(DARK, 12, CYAN)
        }
        val title = TextView(this).apply {
            text = "Hyper-Bot"
            setTextColor(CYAN)
            textSize = 15f
            setPadding(dp(4), 0, dp(4), dp(6))
        }
        p.addView(title)
        autoButton = addButton(p, autoLabel()) { toggleAuto() }
        addButton(p, "Jump") { jump() }
        addButton(p, "Walk") { walkRandom() }
        addButton(p, "Emote") { emoteRandom(force = true) }
        addButton(p, "Say a line") { sayRandomLine(force = true) }
        addButton(p, "Say intro") { sendChat(prefs.safeIntro()) }
        addButton(p, if (markers.isEmpty()) "Calibrate" else "Save calibration") { toggleCalibration() }
        addButton(p, "STOP", Color.rgb(200, 40, 40)) { stopAuto(); hidePanel(); toast("Hyper-Bot stopped") }

        val blp = bubbleLp ?: return
        val lp = overlayParams(
            WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
            blp.x + dp(62), blp.y
        )
        wm.addView(p, lp)
        panel = p
    }

    private fun hidePanel() {
        panel?.let { try { wm.removeView(it) } catch (_: Exception) {} }
        panel = null
        autoButton = null
    }

    private fun addButton(parent: LinearLayout, label: String, color: Int = CYAN, onClick: () -> Unit): Button {
        val b = Button(this).apply {
            text = label
            isAllCaps = false
            textSize = 13f
            setTextColor(Color.WHITE)
            background = round(color, 8)
            minHeight = 0
            minimumHeight = 0
            setPadding(dp(10), dp(6), dp(10), dp(6))
            setOnClickListener { onClick() }
        }
        val lp = LinearLayout.LayoutParams(dp(140), LinearLayout.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(4)
        }
        parent.addView(b, lp)
        return b
    }

    private fun autoLabel() = if (auto) "Auto: ON" else "Auto: OFF"

    private fun removeAllViews() {
        hidePanel()
        bubble?.let { try { wm.removeView(it) } catch (_: Exception) {} }
        bubble = null
        for ((_, m) in markers) try { wm.removeView(m.first) } catch (_: Exception) {}
        markers.clear()
    }

    // ---------------------------------------------------------------- calibration

    /** Shows draggable markers for each Roblox control. Drag each onto the real button, then Save. */
    private fun toggleCalibration() {
        if (markers.isNotEmpty()) {
            val size = dp(64)
            for ((name, m) in markers) {
                val cx = m.second.x + size / 2f
                val cy = m.second.y + size / 2f
                prefs.setPoint(name, cx / screenW(), cy / screenH())
                try { wm.removeView(m.first) } catch (_: Exception) {}
            }
            markers.clear()
            toast("Calibration saved")
        } else {
            val size = dp(64)
            for (name in Prefs.POINTS.keys) {
                val (x, y) = pos(name)
                val v = TextView(this).apply {
                    text = name
                    textSize = 12f
                    setTextColor(Color.WHITE)
                    gravity = Gravity.CENTER
                    background = round(Color.argb(204, 0, 150, 230), 32, Color.WHITE)
                }
                val lp = overlayParams(size, size, (x - size / 2f).toInt(), (y - size / 2f).toInt())
                makeDraggable(v, lp, null)
                wm.addView(v, lp)
                markers[name] = Pair(v, lp)
            }
            toast("Drag JOY, JUMP, CHAT, BOX, SEND onto Roblox's buttons, then tap Save calibration")
        }
        hidePanel()
        togglePanel()
    }

    // ---------------------------------------------------------------- gestures

    private fun stroke(x1: Float, y1: Float, x2: Float, y2: Float, ms: Long) {
        val path = Path().apply {
            moveTo(x1, y1)
            lineTo(x2, y2)
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, ms.coerceAtLeast(1)))
            .build()
        dispatchGesture(gesture, null, null)
    }

    private fun tap(x: Float, y: Float) = stroke(x, y, x, y, 60)

    fun jump() {
        val (x, y) = pos("JUMP")
        tap(x, y)
    }

    /** Pushes the joystick in a random direction for 0.6-1.6 s. */
    fun walkRandom() {
        val (cx, cy) = pos("JOY")
        val angle = Random.nextDouble(0.0, Math.PI * 2)
        val r = dp(60).toFloat()
        val ms = Random.nextLong(600, 1600)
        stroke(cx, cy, cx + (cos(angle) * r).toFloat(), cy + (sin(angle) * r).toFloat(), ms)
        busyUntil = System.currentTimeMillis() + ms + 150
    }

    // ---------------------------------------------------------------- chat

    /** Opens chat, types the text into the focused chat box and sends it. */
    fun sendChat(text: String) {
        val now = System.currentTimeMillis()
        if (now < busyUntil) return
        busyUntil = now + 3500
        val (cx, cy) = pos("CHAT")
        val (bx, by) = pos("BOX")
        tap(cx, cy)
        h.postDelayed({ tap(bx, by) }, 700)
        h.postDelayed({
            if (!setFocusedText(text)) {
                toast("Hyper-Bot: chat box not found - calibrate CHAT and BOX")
                return@postDelayed
            }
            h.postDelayed({
                if (!pressEnter()) {
                    val (sx, sy) = pos("SEND")
                    tap(sx, sy)
                }
            }, 400)
        }, 1500)
    }

    private fun setFocusedText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: findEditable(root) ?: return false
        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        return node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    private fun findEditable(n: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (n == null) return null
        if (n.isEditable) return n
        for (i in 0 until n.childCount) {
            val r = findEditable(n.getChild(i))
            if (r != null) return r
        }
        return null
    }

    private fun pressEnter(): Boolean {
        if (Build.VERSION.SDK_INT < 30) return false
        val node = rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return false
        return node.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id)
    }

    fun sayRandomLine(force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && now - lastChat < prefs.chatIntervalSec * 1000L) return
        if (force && now - lastChat < 5000) {
            toast("Hyper-Bot: wait a few seconds between messages")
            return
        }
        val lines = prefs.lines
        if (lines.isEmpty()) return
        lastChat = now
        sendChat(lines.random())
    }

    fun emoteRandom(force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && now - lastEmote < 60_000) return
        lastEmote = now
        sendChat("/e " + Prefs.EMOTES.random())
    }

    // ---------------------------------------------------------------- auto mode

    private val tick = object : Runnable {
        override fun run() {
            if (!auto) return
            autoStep()
            h.postDelayed(this, Random.nextLong(1500, 3500))
        }
    }

    private fun toggleAuto() {
        if (auto) stopAuto() else startAuto()
        autoButton?.text = autoLabel()
    }

    private fun startAuto() {
        auto = true
        lastIntro = 0L // announce straight away
        h.post(tick)
        toast("Hyper-Bot: Auto ON")
    }

    fun stopAuto() {
        auto = false
        h.removeCallbacksAndMessages(null)
        autoButton?.text = autoLabel()
    }

    private fun autoStep() {
        val now = System.currentTimeMillis()
        if (now < busyUntil) return
        // always (re)announce that this is a bot: on start and every 10 minutes
        if (prefs.chatOn && now - lastIntro > 10 * 60_000L) {
            lastIntro = now
            lastChat = now
            sendChat(prefs.safeIntro())
            return
        }
        if (prefs.chatOn && now - lastChat > prefs.chatIntervalSec * 1000L) {
            sayRandomLine()
            return
        }
        when (Random.nextInt(10)) {
            in 0..5 -> walkRandom()
            in 6..8 -> jump()
            else -> if (prefs.emotesOn) emoteRandom() else jump()
        }
    }
}
