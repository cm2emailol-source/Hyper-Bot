package com.hyperbot.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.util.TypedValue
import android.view.Display
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
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
        stopListening()
        try { recognizer?.close() } catch (_: Exception) {}
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
        addButton(p, "Chat test") { sendChat("Hyper-Bot chat test (I'm a bot)", test = true) }
        addButton(p, "Mood: " + mood().label) { showMoodPanel() }
        addButton(p, "Look around") { lookAround() }
        shiftButtonView = addButton(p, shiftLabel()) { toggleShiftLock() }
        addButton(p, "Moves") { showMovesPanel() }
        listenButton = addButton(p, listenLabel()) { toggleListen() }
        addButton(p, "Listen test") { readChat(true) }
        addButton(p, if (markers.isEmpty()) "Calibrate" else "Save calibration") { toggleCalibration() }
        addButton(p, "STOP", Color.rgb(200, 40, 40)) { stopAuto(); stopFollow(); hidePanel(); toast("Hyper-Bot stopped") }

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
        listenButton = null
        shiftButtonView = null
    }

    // ---------------------------------------------------------------- moods

    private var shiftButtonView: Button? = null
    private var moodSince = System.currentTimeMillis()

    private fun mood(): Mood {
        val m = Moods.byId(prefs.mood)
        return if (m.id == "normal" || m.id in prefs.enabledMoods) m else Moods.NORMAL
    }

    private fun availableMoods(): List<Mood> = Moods.ALL.filter { it.id == "normal" || it.id in prefs.enabledMoods }

    private fun setMood(m: Mood, announce: Boolean) {
        prefs.mood = m.id
        moodSince = System.currentTimeMillis()
        if (announce) toast("Hyper-Bot mood: " + m.label)
    }

    private fun showMoodPanel() {
        hidePanel()
        val p = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), dp(8), dp(8), dp(8))
            background = round(DARK, 12, CYAN)
        }
        p.addView(TextView(this).apply {
            text = "Mood"
            setTextColor(CYAN)
            textSize = 15f
            setPadding(dp(4), 0, dp(4), dp(6))
        })
        val cur = mood().id
        for (m in availableMoods()) {
            val sel = m.id == cur
            addButton(p, (if (sel) "> " else "") + m.label, if (sel) Color.rgb(0, 150, 90) else CYAN) {
                setMood(m, true)
                hidePanel()
                togglePanel()
            }
        }
        if (availableMoods().size == 1) p.addView(TextView(this).apply {
            text = "Tick moods in the Hyper-Bot app"
            setTextColor(Color.LTGRAY)
            textSize = 11f
        })
        addButton(p, "Back", Color.GRAY) { hidePanel(); togglePanel() }
        val blp = bubbleLp ?: return
        val lp = overlayParams(
            WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
            blp.x + dp(62), blp.y
        )
        wm.addView(p, lp)
        panel = p
    }

    // ---------------------------------------------------------------- camera: look around + Shift Lock mode

    private fun shiftLabel() = if (prefs.shiftLock) "Shift Lock: ON" else "Shift Lock: OFF"

    private fun toggleShiftLock() {
        prefs.shiftLock = !prefs.shiftLock
        if (prefs.shiftButton) {
            val (x, y) = pos("SHIFT")
            tap(x, y)
        }
        shiftButtonView?.text = shiftLabel()
        toast(if (prefs.shiftLock) "Shift Lock mode ON" else "Shift Lock mode OFF")
    }

    /** Swipes on an empty part of the screen (CAM) to turn the camera: a glance to one side and partly back.
     *  In Shift Lock the character turns with the camera, so this becomes a shift-lock look-around. */
    fun lookAround() {
        if (System.currentTimeMillis() < busyUntil) return
        val (cx, cy) = pos("CAM")
        val w = screenW()
        val hgt = screenH()
        val dir = if (Random.nextBoolean()) 1f else -1f
        val far = dir * w * Random.nextDouble(0.06, 0.22).toFloat()
        val back = far * Random.nextDouble(0.0, 0.8).toFloat()
        val dy = hgt * Random.nextDouble(-0.03, 0.03).toFloat()
        val ms = Random.nextLong(700, 1600)
        val path = Path().apply {
            moveTo(cx, cy)
            lineTo((cx + far).coerceIn(w * 0.45f, w * 0.98f), (cy + dy).coerceIn(hgt * 0.1f, hgt * 0.6f))
            lineTo((cx + far - back).coerceIn(w * 0.45f, w * 0.98f), cy)
        }
        dispatchGesture(
            GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(path, 0, ms)).build(),
            null, null
        )
        busyUntil = System.currentTimeMillis() + ms + 150
    }

    /** Shift Lock walk: hold the joystick forward and (sometimes) steer with the camera at the same time,
     *  so the character walks a smooth arc while always facing where it looks. */
    private fun shiftWalk() {
        val (jx, jy) = pos("JOY")
        val (cx, cy) = pos("CAM")
        val w = screenW()
        val r = dp(60) * mood().stick
        val ang = -Math.PI / 2 + Random.nextDouble(-0.35, 0.35)
        val ms = Random.nextLong(900, 2400)
        val joy = Path().apply {
            moveTo(jx, jy)
            lineTo(jx + (cos(ang) * r).toFloat(), jy + (sin(ang) * r).toFloat())
        }
        val b = GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(joy, 0, ms))
        if (Random.nextBoolean()) { // turn while walking (half the time walk straight, so stuck detection still works)
            val dx = (if (Random.nextBoolean()) 1f else -1f) * w * Random.nextDouble(0.05, 0.18).toFloat()
            val cam = Path().apply {
                moveTo(cx, cy)
                lineTo((cx + dx).coerceIn(w * 0.45f, w * 0.98f), cy)
            }
            b.addStroke(GestureDescription.StrokeDescription(cam, 100, ms - 100))
        }
        dispatchGesture(b.build(), null, null)
        busyUntil = System.currentTimeMillis() + ms + 150
        lastWalkAt = System.currentTimeMillis()
        lastWalkAngle = ang
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
    private fun listenLabel() = if (listening) "Listen: ON" else "Listen: OFF"

    private fun removeAllViews() {
        hidePanel()
        bubble?.let { try { wm.removeView(it) } catch (_: Exception) {} }
        bubble = null
        for ((_, m) in markers) try { wm.removeView(m.first) } catch (_: Exception) {}
        diagView?.let { try { wm.removeView(it) } catch (_: Exception) {} }
        diagView = null
        markers.clear()
        recLayer?.let { try { wm.removeView(it) } catch (_: Exception) {} }
        recBar?.let { try { wm.removeView(it) } catch (_: Exception) {} }
        recLayer = null
        recBar = null
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
            toast("Drag JOY, JUMP, CHAT, BOX, SEND (and SHIFT) onto Roblox's buttons, CAM onto an empty spot, then Save calibration")
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

    /** Pushes the joystick and sweeps it in a gentle arc, so the character walks a curve (0.8-2.2 s). */
    fun walkRandom() {
        val (cx, cy) = pos("JOY")
        val a1 = Random.nextDouble(0.0, Math.PI * 2)
        val a2 = a1 + Random.nextDouble(-0.9, 0.9) // up to ~50 degrees of turning
        val r = dp(60) * mood().stick
        val ms = Random.nextLong(800, 2200)
        val path = Path().apply {
            moveTo(cx, cy)
            lineTo(cx + (cos(a1) * r * 0.6).toFloat(), cy + (sin(a1) * r * 0.6).toFloat())
            quadTo(
                cx + (cos((a1 + a2) / 2) * r * 1.1).toFloat(), cy + (sin((a1 + a2) / 2) * r * 1.1).toFloat(),
                cx + (cos(a2) * r).toFloat(), cy + (sin(a2) * r).toFloat()
            )
        }
        dispatchGesture(
            GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(path, 0, ms)).build(),
            null, null
        )
        busyUntil = System.currentTimeMillis() + ms + 150
        lastWalkAt = System.currentTimeMillis()
        lastWalkAngle = a2
    }

    // ---------------------------------------------------------------- moves: playback

    /** Replays a recorded move. Strokes that overlap in time (e.g. joystick held while tapping jump)
     *  are sent together as one multi-finger gesture; separate ones are sent at their recorded times. */
    fun playMove(m: Move) {
        if (m.strokes.isEmpty()) return
        val w = screenW()
        val hh = screenH()
        val maxStrokes = GestureDescription.getMaxStrokeCount()
        val maxDur = GestureDescription.getMaxGestureDuration()
        val groups = mutableListOf<MutableList<Stroke>>()
        var groupEnd = -1L
        for (st in m.strokes.sortedBy { it.start }) {
            if (groups.isEmpty() || st.start > groupEnd) {
                groups.add(mutableListOf(st))
                groupEnd = st.end
            } else {
                groups.last().add(st)
                groupEnd = maxOf(groupEnd, st.end)
            }
        }
        for (g in groups) {
            val g0 = g.first().start
            h.postDelayed({
                val b = GestureDescription.Builder()
                var added = 0
                for (st in g) {
                    if (added >= maxStrokes) break
                    val offset = st.start - g0
                    if (offset >= maxDur - 50) continue
                    val path = Path()
                    st.points.forEachIndexed { i, pt ->
                        val x = pt.x * w
                        val y = pt.y * hh
                        if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                    }
                    if (st.points.size == 1) path.lineTo(st.points[0].x * w, st.points[0].y * hh)
                    val dur = maxOf(50L, st.end - st.start).coerceAtMost(maxDur - offset - 1)
                    b.addStroke(GestureDescription.StrokeDescription(path, offset, dur))
                    added++
                }
                if (added > 0) try { dispatchGesture(b.build(), null, null) } catch (_: Exception) {}
            }, g0)
        }
        busyUntil = System.currentTimeMillis() + m.durationMs + 400
    }

    // ---------------------------------------------------------------- moves: panel

    private fun showMovesPanel() {
        hidePanel()
        val p = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), dp(8), dp(8), dp(8))
            background = round(DARK, 12, CYAN)
        }
        p.addView(TextView(this).apply {
            text = "Moves"
            setTextColor(CYAN)
            textSize = 15f
            setPadding(dp(4), 0, dp(4), dp(6))
        })
        val moves = MoveStore.load(this)
        if (moves.isEmpty()) {
            p.addView(TextView(this).apply {
                text = "No moves yet"
                setTextColor(Color.LTGRAY)
                textSize = 12f
                setPadding(dp(4), 0, dp(4), dp(4))
            })
        }
        for (m in moves.take(8)) addButton(p, "Play: " + m.name) { playMove(m) }
        if (moves.size > 8) p.addView(TextView(this).apply {
            text = "(+${moves.size - 8} more, used by Auto)"
            setTextColor(Color.LTGRAY)
            textSize = 11f
        })
        addButton(p, "+ Record new move", Color.rgb(0, 150, 90)) { startRecording() }
        addButton(p, "Back", Color.GRAY) { hidePanel(); togglePanel() }
        val blp = bubbleLp ?: return
        wm.addView(p, overlayParams(
            WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT, blp.x + dp(62), blp.y
        ))
        panel = p
    }

    // ---------------------------------------------------------------- moves: recording

    private var recLayer: View? = null
    private var recBar: View? = null
    private var recMove: Move? = null
    private var recStart = -1L
    private val recActive = mutableMapOf<Int, Stroke>()

    /** Covers the screen with a see-through layer that records your taps/swipes (Roblox doesn't receive them). */
    @SuppressLint("ClickableViewAccessibility")
    private fun startRecording() {
        hidePanel()
        stopAuto()
        val move = Move(MoveStore.nextName(MoveStore.load(this)))
        recMove = move
        recStart = -1L
        recActive.clear()
        val layer = View(this).apply { setBackgroundColor(Color.argb(45, 0, 150, 230)) }
        layer.setOnTouchListener { _, e -> recordEvent(e); true }
        wm.addView(layer, overlayParams(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT, 0, 0))
        recLayer = layer

        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), dp(6), dp(10), dp(6))
            background = round(DARK, 12, Color.rgb(220, 50, 50))
        }
        bar.addView(TextView(this).apply {
            text = "REC  ${move.name}   "
            setTextColor(Color.rgb(255, 90, 90))
            textSize = 14f
        })
        val save = Button(this).apply {
            text = "Stop & save"; isAllCaps = false; textSize = 13f; setTextColor(Color.WHITE)
            background = round(Color.rgb(0, 150, 90), 8); setPadding(dp(10), dp(4), dp(10), dp(4))
            setOnClickListener { stopRecording(true) }
        }
        val cancel = Button(this).apply {
            text = "Cancel"; isAllCaps = false; textSize = 13f; setTextColor(Color.WHITE)
            background = round(Color.GRAY, 8); setPadding(dp(10), dp(4), dp(10), dp(4))
            setOnClickListener { stopRecording(false) }
        }
        bar.addView(save)
        bar.addView(cancel, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { leftMargin = dp(6) })
        wm.addView(bar, overlayParams(
            WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
            (screenW() / 2 - dp(160)).toInt(), dp(8)
        ))
        recBar = bar
        toast("Recording ${move.name}: do your taps and swipes, then Stop & save")
    }

    private fun recordEvent(e: MotionEvent) {
        if (recStart < 0) recStart = e.eventTime
        val t = e.eventTime - recStart
        val offX = e.rawX - e.x
        val offY = e.rawY - e.y
        fun point(i: Int) = TouchPoint((e.getX(i) + offX) / screenW(), (e.getY(i) + offY) / screenH(), t)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val i = e.actionIndex
                recActive[e.getPointerId(i)] = Stroke(mutableListOf(point(i)))
            }
            MotionEvent.ACTION_MOVE -> {
                for (i in 0 until e.pointerCount) {
                    val st = recActive[e.getPointerId(i)] ?: continue
                    if (t - st.points.last().t >= 30) st.points.add(point(i))
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                val i = e.actionIndex
                val st = recActive.remove(e.getPointerId(i))
                if (st != null) {
                    st.points.add(point(i))
                    recMove?.strokes?.add(st)
                }
            }
            MotionEvent.ACTION_CANCEL -> {
                for ((_, st) in recActive) recMove?.strokes?.add(st)
                recActive.clear()
            }
        }
    }

    private fun stopRecording(save: Boolean) {
        for ((_, st) in recActive) recMove?.strokes?.add(st)
        recActive.clear()
        recLayer?.let { try { wm.removeView(it) } catch (_: Exception) {} }
        recBar?.let { try { wm.removeView(it) } catch (_: Exception) {} }
        recLayer = null
        recBar = null
        val m = recMove
        recMove = null
        if (save && m != null) {
            if (m.strokes.isEmpty()) {
                toast("Nothing recorded")
            } else {
                val all = MoveStore.load(this)
                all.add(m)
                MoveStore.save(this, all)
                toast("Saved ${m.name}: ${m.strokes.size} taps/swipes, ${"%.1f".format(m.durationMs / 1000.0)} s")
            }
        }
        showMovesPanel()
    }

    // ---------------------------------------------------------------- chat

    /** Step-by-step record of the last chat attempt (shown by "Chat test", saved for the app screen). */
    private var diag = StringBuilder()

    /** Opens chat, types the text into Roblox's chat box and sends it.
     *  Method 1: set the box's text. Method 2: paste. Method 3: tap the letters on the on-screen keyboard. */
    fun sendChat(text: String, test: Boolean = false) {
        val now = System.currentTimeMillis()
        if (now < busyUntil && !test) return
        lastOwnChat = now
        brain.noteOwn(text)
        busyUntil = now + 12_000 + text.length * 140L
        diag = StringBuilder()
        diag.append("text: \"").append(text).append("\"\n")
        val (cx, cy) = pos("CHAT")
        diag.append("tap CHAT at ${cx.toInt()},${cy.toInt()}\n")
        tap(cx, cy)
        h.postDelayed({ tapBoxAndWait(text, test, 1) }, 700)
    }

    /** Taps the chat box, then checks every 0.25 s (up to 3 s) until a text box or keyboard is ready.
     *  Attempt 2 taps the box again; attempt 3 reopens the chat first. */
    private fun tapBoxAndWait(text: String, test: Boolean, attempt: Int) {
        val (bx, by) = pos("BOX")
        diag.append("attempt $attempt: tap BOX at ${bx.toInt()},${by.toInt()}\n")
        tap(bx, by)
        val start = System.currentTimeMillis()
        val poll = object : Runnable {
            override fun run() {
                val node = findChatBox(quiet = true)
                val keys = keyboardKeys().size
                val waited = System.currentTimeMillis() - start
                if (node != null || keys >= 10) {
                    diag.append("ready after ${waited} ms (text box: ${node != null}, keyboard keys: $keys)\n")
                    h.postDelayed({ typeAndSend(text, test) }, 250)
                    return
                }
                if (waited < 3000) {
                    h.postDelayed(this, 250)
                    return
                }
                when (attempt) {
                    1 -> tapBoxAndWait(text, test, 2)
                    2 -> {
                        val (cx, cy) = pos("CHAT")
                        diag.append("reopening chat\n")
                        tap(cx, cy)
                        h.postDelayed({ tapBoxAndWait(text, test, 3) }, 800)
                    }
                    else -> {
                        findChatBox() // log what was visible
                        diag.append("keyboard keys visible: $keys\n")
                        report("FAILED - chat box / keyboard never became ready (check BOX calibration)", true)
                    }
                }
            }
        }
        h.postDelayed(poll, 400)
    }

    private fun typeAndSend(text: String, test: Boolean) {
        val node = findChatBox()
        if (node != null && typeInto(node, text)) {
            h.postDelayed({ finishSend(node, test) }, 450)
        } else {
            diag.append("trying method 3: tapping the on-screen keyboard\n")
            typeWithKeyboard(text) { ok ->
                if (ok) h.postDelayed({ finishSend(node, test) }, 300)
                else report("FAILED - could not type (no text box and no usable keyboard keys)", true)
            }
        }
    }

    private fun finishSend(node: AccessibilityNodeInfo?, test: Boolean) {
        when {
            node != null && pressEnter(node) -> diag.append("send: keyboard Enter action\n")
            tapKeyboardEnter() -> diag.append("send: tapped the keyboard's Enter key\n")
            else -> {
                val (sx, sy) = pos("SEND")
                tap(sx, sy)
                diag.append("send: tapped SEND at ${sx.toInt()},${sy.toInt()}\n")
            }
        }
        report("done - check whether the message appeared in chat", test)
    }

    // ---- method 3: on-screen keyboard ----

    private fun keyboardRoot(): AccessibilityNodeInfo? = try {
        windows.firstOrNull { it.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD }?.root
    } catch (_: Exception) { null }

    private fun keyLabel(n: AccessibilityNodeInfo): String =
        (n.text?.toString()?.takeIf { it.isNotBlank() } ?: n.contentDescription?.toString() ?: "").trim()

    private fun collectKeys(n: AccessibilityNodeInfo?, out: MutableList<AccessibilityNodeInfo>) {
        if (n == null) return
        if (n.isVisibleToUser && keyLabel(n).isNotEmpty()) out.add(n)
        for (i in 0 until n.childCount) collectKeys(n.getChild(i), out)
    }

    private fun keyboardKeys(): List<AccessibilityNodeInfo> {
        val out = mutableListOf<AccessibilityNodeInfo>()
        collectKeys(keyboardRoot(), out)
        return out
    }

    private fun findKey(c: Char): AccessibilityNodeInfo? {
        val keys = keyboardKeys()
        if (c == ' ') return keys.firstOrNull { val l = keyLabel(it).lowercase(); l == "space" || l.contains("space") }
        val want = c.toString()
        return keys.firstOrNull { keyLabel(it).equals(want, ignoreCase = true) }
    }

    private fun tapNode(n: AccessibilityNodeInfo) {
        val r = Rect()
        n.getBoundsInScreen(r)
        tap(r.exactCenterX(), r.exactCenterY())
    }

    /** Taps each character's key, ~0.13 s apart. Characters not on the current keyboard page are skipped. */
    private fun typeWithKeyboard(text: String, done: (Boolean) -> Unit) {
        val count = keyboardKeys().size
        diag.append("keyboard keys visible: $count\n")
        if (count < 10) {
            done(false)
            return
        }
        var i = 0
        var typed = 0
        val skipped = StringBuilder()
        fun step() {
            if (i >= text.length) {
                diag.append("typed $typed of ${text.length} characters")
                if (skipped.isNotEmpty()) diag.append(" (skipped: ").append(skipped).append(")")
                diag.append("\n")
                done(typed > 0)
                return
            }
            val c = text[i++]
            val k = findKey(c)
            if (k != null) {
                tapNode(k)
                typed++
            } else if (!skipped.contains(c)) {
                skipped.append(c)
            }
            h.postDelayed({ step() }, 130)
        }
        step()
    }

    private fun tapKeyboardEnter(): Boolean {
        val names = listOf("enter", "done", "send", "go", "return", "next")
        val k = keyboardKeys().firstOrNull { key -> val l = keyLabel(key).lowercase(); names.any { l == it || l.startsWith(it) } }
            ?: return false
        tapNode(k)
        return true
    }

    /** Looks through every window (not just the active one: the keyboard can be the active window). */
    private fun findChatBox(quiet: Boolean = false): AccessibilityNodeInfo? {
        val log: (String) -> Unit = { if (!quiet) diag.append(it) }
        val roots = mutableListOf<AccessibilityNodeInfo>()
        try {
            for (w in windows) {
                val r = w.root ?: continue
                val isKeyboard = w.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD
                log("window: ${r.packageName}${if (isKeyboard) " (keyboard)" else ""}\n")
                if (!isKeyboard && r.packageName != packageName) roots.add(r)
            }
        } catch (e: Exception) {
            log("windows list error: ${e.message}\n")
        }
        rootInActiveWindow?.let { if (it.packageName != packageName && roots.none { r -> r == it }) roots.add(it) }
        for (r in roots) {
            val f = r.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            if (f != null) {
                log("focused input: ${f.className} (${f.packageName}) editable=${f.isEditable}\n")
                if (f.isEditable) return f
            }
        }
        for (r in roots) {
            val e = findEditable(r)
            if (e != null) {
                log("editable box: ${e.className} (${e.packageName})\n")
                return e
            }
        }
        log("no editable text box found in any window\n")
        return null
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

    /** Sets the text directly; if Roblox refuses, pastes it from the clipboard instead. */
    private fun typeInto(node: AccessibilityNodeInfo, text: String): Boolean {
        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        if (node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)) {
            diag.append("typed: set text OK\n")
            return true
        }
        diag.append("set text refused, trying paste\n")
        try {
            val cm = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
            cm.setPrimaryClip(ClipData.newPlainText("Hyper-Bot", text))
        } catch (e: Exception) {
            diag.append("clipboard error: ${e.message}\n")
            return false
        }
        node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        if (node.performAction(AccessibilityNodeInfo.ACTION_PASTE)) {
            diag.append("typed: paste OK\n")
            return true
        }
        diag.append("paste refused\n")
        return false
    }

    private fun pressEnter(node: AccessibilityNodeInfo): Boolean {
        if (Build.VERSION.SDK_INT < 30) return false
        return node.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id)
    }

    private fun report(result: String, show: Boolean) {
        diag.append("result: ").append(result).append("\n")
        prefs.lastChatDiag = diag.toString()
        if (show) showDiag(diag.toString()) else if (result.startsWith("FAILED")) toast("Hyper-Bot: chat failed - use Chat test for details")
    }

    private var diagView: TextView? = null

    /** On-screen report of the chat attempt. Tap it to close (it also closes after 25 s). */
    private fun showDiag(text: String) {
        diagView?.let { try { wm.removeView(it) } catch (_: Exception) {} }
        val v = TextView(this).apply {
            this.text = "Hyper-Bot (tap to close)\n\n$text"
            textSize = 12f
            setTextColor(Color.WHITE)
            setPadding(dp(12), dp(10), dp(12), dp(10))
            background = round(DARK, 10, CYAN)
        }
        val lp = overlayParams(
            (screenW() * 0.55f).toInt(), WindowManager.LayoutParams.WRAP_CONTENT,
            (screenW() * 0.4f).toInt(), dp(16)
        )
        v.setOnClickListener { try { wm.removeView(v) } catch (_: Exception) {}; diagView = null }
        wm.addView(v, lp)
        diagView = v
        h.postDelayed({ if (diagView === v) { try { wm.removeView(v) } catch (_: Exception) {}; diagView = null } }, 25_000)
    }

    fun sayRandomLine(force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && now - lastChat < (prefs.chatIntervalSec * 1000L * mood().chatScale).toLong()) return
        if (force && now - lastChat < 5000) {
            toast("Hyper-Bot: wait a few seconds between messages")
            return
        }
        val ml = if (prefs.moodLines) mood().lines else emptyList()
        val lines = if (ml.isNotEmpty() && (prefs.lines.isEmpty() || Random.nextBoolean())) ml else prefs.lines
        if (lines.isEmpty()) return
        lastChat = now
        sendChat(lines.random())
    }

    fun emoteRandom(force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && now - lastEmote < 60_000) return
        lastEmote = now
        sendChat("/e " + mood().emotes.ifEmpty { Prefs.EMOTES }.random())
    }

    // ---------------------------------------------------------------- listening (reply when talked to)

    private val brain = ChatBrain()
    private val lh = Handler(Looper.getMainLooper()) // separate timer: stopping Auto doesn't stop Listen
    private var listening = false
    private var listenButton: Button? = null
    private var lastOwnChat = 0L
    private val chatQueue = ArrayDeque<String>()
    private var recognizer: TextRecognizer? = null

    private fun toggleListen() {
        if (listening) stopListening() else startListening()
        listenButton?.text = listenLabel()
    }

    private fun startListening() {
        if (Build.VERSION.SDK_INT < 30) {
            toast("Listening needs Android 11 or newer")
            return
        }
        listening = true
        brain.reset()
        ensureVision()
        toast("Hyper-Bot: listening to chat")
    }

    private fun stopListening() {
        listening = false
        chatQueue.clear()
        listenButton?.text = listenLabel()
    }

    // ---- shared vision timer: about one screenshot every 1.2 s (Android allows ~1/s),
    //      shared by Listen (every 2nd tick), Follow, Face and Stuck detection. Idle = no screenshots.

    private var visionRunning = false
    private var visionCount = 0
    private var shotBusy = false
    private var lastShot = 0L
    private var testPending = false

    private fun ensureVision() {
        if (visionRunning || Build.VERSION.SDK_INT < 30) return
        visionRunning = true
        lh.post(visionTick)
    }

    private val visionTick = object : Runnable {
        override fun run() {
            val now = System.currentTimeMillis()
            visionCount++
            val test = testPending
            val needChat = test || (listening && visionCount % 2 == 0 && now >= busyUntil && recLayer == null)
            val needTags = followTarget != null || faceTarget != null
            val needStuck = prefs.stuckOn && (auto || followTarget != null) && recLayer == null
            if (needChat || needTags || needStuck) {
                capture { bmp ->
                    if (needStuck) checkStuck(bmp)
                    if (needTags) seekTags(bmp)
                    if (needChat) {
                        testPending = false
                        ocrChat(bmp, test)
                    }
                }
            }
            if (listening || auto || followTarget != null || faceTarget != null || testPending) {
                lh.postDelayed(this, 1200)
            } else {
                visionRunning = false
            }
        }
    }

    /** Screenshot (Android 11+, no extra permission for accessibility services). */
    private fun capture(onShot: (Bitmap) -> Unit) {
        if (Build.VERSION.SDK_INT < 30) return
        val now = System.currentTimeMillis()
        if (shotBusy || now - lastShot < 1050) return
        shotBusy = true
        lastShot = now
        takeScreenshot(Display.DEFAULT_DISPLAY, mainExecutor, object : AccessibilityService.TakeScreenshotCallback {
            override fun onSuccess(result: AccessibilityService.ScreenshotResult) {
                shotBusy = false
                var bmp: Bitmap? = null
                try {
                    val hw = Bitmap.wrapHardwareBuffer(result.hardwareBuffer, result.colorSpace)
                    bmp = hw?.copy(Bitmap.Config.ARGB_8888, false)
                    hw?.recycle()
                } catch (_: Exception) {
                } finally {
                    try { result.hardwareBuffer.close() } catch (_: Exception) {}
                }
                bmp?.let(onShot)
            }

            override fun onFailure(errorCode: Int) {
                shotBusy = false
            }
        })
    }

    /** Listen test: reads the chat once, on the next vision tick. */
    private fun readChat(test: Boolean) {
        if (Build.VERSION.SDK_INT < 30) {
            if (test) showDiag("Listening needs Android 11 or newer")
            return
        }
        if (test) testPending = true
        ensureVision()
    }

    // ---------------------------------------------------------------- vision lite: follow, face, stuck

    private var followTarget: String? = null
    private var followUntil = 0L
    private var followLost = 0
    private var faceTarget: String? = null
    private var faceUntil = 0L
    private var lastWalkAt = 0L
    private var lastWalkAngle = 0.0
    private var prevThumb: IntArray? = null
    private var stuckCount = 0

    /** Follows ONLY the player who asked ("bot follow me"), for a limited time. "bot stop" ends it. */
    fun startFollow(name: String) {
        followTarget = name
        followUntil = System.currentTimeMillis() + prefs.followSec * 1000L
        followLost = 0
        ensureVision()
    }

    fun stopFollow() {
        followTarget = null
    }

    /** Small joystick nudge towards someone who talked to the bot, so it turns to face them. */
    fun faceToward(name: String) {
        if (!prefs.faceTalker || followTarget != null) return
        faceTarget = name
        faceUntil = System.currentTimeMillis() + 4000
        ensureVision()
    }

    private fun normName(s: String) = s.lowercase().filter { it.isLetterOrDigit() }

    private fun levenshtein(a: String, b: String): Int {
        val dp = IntArray(b.length + 1) { it }
        for (i in 1..a.length) {
            var prev = dp[0]
            dp[0] = i
            for (j in 1..b.length) {
                val tmp = dp[j]
                dp[j] = minOf(dp[j] + 1, dp[j - 1] + 1, prev + if (a[i - 1] == b[j - 1]) 0 else 1)
                prev = tmp
            }
        }
        return dp[b.length]
    }

    private fun similar(a: String, b: String): Boolean {
        if (a.isEmpty() || b.isEmpty()) return false
        if (a.length < 3 || b.length < 3) return a == b
        if (a == b || a.contains(b) || b.contains(a)) return true
        return 1.0 - levenshtein(a, b).toDouble() / maxOf(a.length, b.length) >= 0.75
    }

    /** Reads the whole screen (outside the chat area) and looks for the target's name tag above their head. */
    private fun seekTags(bmp: Bitmap) {
        val now = System.currentTimeMillis()
        if (followTarget != null && now > followUntil) {
            followTarget = null
            toast("Hyper-Bot: done following")
            return
        }
        if (faceTarget != null && now > faceUntil) faceTarget = null
        val target = followTarget ?: faceTarget ?: return
        val scale = minOf(1f, 1280f / bmp.width)
        val img = if (scale < 1f) Bitmap.createScaledBitmap(bmp, (bmp.width * scale).toInt(), (bmp.height * scale).toInt(), true) else bmp
        val (lx1, ly1) = prefs.point("LOG1")
        val (lx2, ly2) = prefs.point("LOG2")
        val want = normName(target)
        val rec = recognizer ?: TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS).also { recognizer = it }
        rec.process(InputImage.fromBitmap(img, 0)).addOnSuccessListener { text ->
            var best: Rect? = null
            for (block in text.textBlocks) {
                for (line in block.lines) {
                    val box = line.boundingBox ?: continue
                    val fx = box.exactCenterX() / img.width
                    val fy = box.exactCenterY() / img.height
                    val inChat = fx in minOf(lx1, lx2)..maxOf(lx1, lx2) && fy in minOf(ly1, ly2)..maxOf(ly1, ly2)
                    if (!inChat && similar(normName(line.text), want)) {
                        best = box
                        break
                    }
                }
                if (best != null) break
            }
            val b = best
            if (b == null) {
                if (followTarget != null && ++followLost >= 4) {
                    followTarget = null
                    toast("Hyper-Bot: lost $target")
                }
                return@addOnSuccessListener
            }
            followLost = 0
            steerToward(b.exactCenterX() / scale, b.exactCenterY() / scale, b.height() / scale)
        }
    }

    /** Joystick towards a point on screen. The bot's own character is roughly at the screen centre. */
    private fun steerToward(sx: Float, sy: Float, tagH: Float) {
        val w = screenW()
        val hgt = screenH()
        val dx = sx - w * 0.5f
        val dy = sy - hgt * 0.55f
        val angle = atan2(dy.toDouble(), dx.toDouble())
        if (faceTarget != null && followTarget == null) {
            faceTarget = null
            nudge(angle, 180)
            return
        }
        val close = tagH > hgt * 0.04f || (abs(dx) < w * 0.08f && tagH > hgt * 0.03f)
        if (close) return // near enough: wait for them to move
        nudge(angle, 700)
    }

    private fun nudge(angle: Double, ms: Long) {
        val (cx, cy) = pos("JOY")
        val r = dp(60).toFloat()
        stroke(cx, cy, cx + (cos(angle) * r).toFloat(), cy + (sin(angle) * r).toFloat(), ms)
        lastWalkAt = System.currentTimeMillis()
        lastWalkAngle = angle
        busyUntil = maxOf(busyUntil, lastWalkAt + ms + 100)
    }

    /** Tiny greyscale samples from the left and right edges (not the centre, where our own character animates). */
    private fun thumbnail(bmp: Bitmap): IntArray {
        val out = IntArray(240)
        var k = 0
        for (side in 0..1) {
            val x0 = if (side == 0) 0.05f else 0.67f
            for (gy in 0 until 10) for (gx in 0 until 12) {
                val x = ((x0 + gx * 0.28f / 11) * (bmp.width - 1)).toInt()
                val y = ((0.15f + gy * 0.55f / 9) * (bmp.height - 1)).toInt()
                val c = bmp.getPixel(x, y)
                out[k++] = ((c shr 16 and 255) * 3 + (c shr 8 and 255) * 6 + (c and 255)) / 10
            }
        }
        return out
    }

    /** If the bot was walking but the screen edges didn't change in two checks, it's stuck: turn around + jump. */
    private fun checkStuck(bmp: Bitmap) {
        val thumb = thumbnail(bmp)
        val prev = prevThumb
        prevThumb = thumb
        if (prev == null) return
        if (System.currentTimeMillis() - lastWalkAt > 1600) {
            stuckCount = 0
            return
        }
        var diff = 0L
        for (i in thumb.indices) diff += abs(thumb[i] - prev[i])
        if (diff.toDouble() / thumb.size < 3.0) stuckCount++ else stuckCount = 0
        if (stuckCount >= 2) {
            stuckCount = 0
            stuckEscapes++
            val away = lastWalkAngle + Math.PI + Random.nextDouble(-0.6, 0.6)
            nudge(away, 900)
            lh.postDelayed({ jump() }, 300)
        }
    }

    private var stuckEscapes = 0

    /** Cuts out the chat area (LOG1 = top-left, LOG2 = bottom-right) and reads it with on-device text recognition. */
    private fun ocrChat(bmp: Bitmap, test: Boolean) {
        val (ax, ay) = prefs.point("LOG1")
        val (bx, by) = prefs.point("LOG2")
        val x1 = (minOf(ax, bx) * bmp.width).toInt().coerceIn(0, bmp.width - 20)
        val y1 = (minOf(ay, by) * bmp.height).toInt().coerceIn(0, bmp.height - 20)
        val x2 = (maxOf(ax, bx) * bmp.width).toInt().coerceIn(x1 + 20, bmp.width)
        val y2 = (maxOf(ay, by) * bmp.height).toInt().coerceIn(y1 + 20, bmp.height)
        var crop = Bitmap.createBitmap(bmp, x1, y1, x2 - x1, y2 - y1)
        if (crop.height < 500) crop = Bitmap.createScaledBitmap(crop, crop.width * 2, crop.height * 2, true)
        val rec = recognizer ?: TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS).also { recognizer = it }
        rec.process(InputImage.fromBitmap(crop, 0))
            .addOnSuccessListener { text ->
                val lines = text.textBlocks.flatMap { block -> block.lines.map { it.text } }
                handleChat(lines, test)
            }
            .addOnFailureListener { e ->
                if (test) showDiag("Listen test: text recognition failed: ${e.message}")
            }
    }

    private fun handleChat(lines: List<String>, test: Boolean) {
        if (test) {
            val sb = StringBuilder("Listen test: read ${lines.size} line(s) from the chat area\n\n")
            for (l in lines.take(12)) {
                val c = brain.parse(l)
                sb.append(if (c != null) "- ${c.name}: ${c.message}\n" else "- (no name) $l\n")
            }
            if (lines.isEmpty()) sb.append("(nothing read - is the chat open, and are LOG1 / LOG2 around the messages?)\n")
            showDiag(sb.toString())
            return
        }
        val now = System.currentTimeMillis()
        for (l in brain.newLines(lines)) {
            val c = brain.parse(l) ?: continue
            if (prefs.commandsOn) {
                val cmd = brain.command(c, prefs.botName, now)
                if (cmd != null) {
                    runCommand(cmd, now)
                    break // at most one action per read
                }
            }
            if (!brain.shouldReply(c, prefs.botName, lastOwnChat, now)) continue
            val replies = moodReplies()
            if (replies.isEmpty()) break
            faceToward(c.name)
            if (prefs.waveOnReply) queueChat("/e wave")
            queueChat(brain.fill(replies.random(), c.name))
            break // at most one reply per read
        }
    }

    private fun moodReplies(): List<String> {
        val mr = if (prefs.moodLines) mood().replies else emptyList()
        return if (mr.isNotEmpty() && (prefs.replyLines.isEmpty() || Random.nextBoolean())) mr else prefs.replyLines
    }

    /** Commands are mostly silent actions (emotes, jumps, moves); only help/hi type in chat. */
    private fun runCommand(cmd: ChatBrain.Command, now: Long) {
        when (cmd.name) {
            "help", "commands" -> {
                val moves = MoveStore.load(this).map { it.name.lowercase() }.take(4)
                val extra = if (moves.isNotEmpty()) " or a move: " + moves.joinToString(" ") else ""
                queueChat("bot commands: wave dance cheer laugh point jump walk hi follow stop mood$extra")
            }
            "follow", "come" -> {
                if (followTarget == null) {
                    startFollow(cmd.from)
                    queueChat("/e point")
                }
            }
            "stop" -> stopFollow()
            "mood" -> if (brain.allowChatAnswer(cmd.from, now)) queueChat("bot mood: " + mood().label.lowercase())
            "hi", "hello", "hey" -> {
                faceToward(cmd.from)
                val replies = moodReplies()
                if (replies.isNotEmpty() && brain.allowChatAnswer(cmd.from, now)) queueChat(brain.fill(replies.random(), cmd.from))
                else queueChat("/e wave")
            }
            "wave", "cheer", "laugh", "point" -> {
                if (cmd.name == "wave") faceToward(cmd.from)
                queueChat("/e " + cmd.name)
            }
            "dance" -> queueChat("/e " + listOf("dance", "dance2", "dance3").random())
            "jump" -> whenFree {
                val times = Random.nextInt(1, 4)
                for (i in 0 until times) lh.postDelayed({ jump() }, i * 650L)
                busyUntil = System.currentTimeMillis() + times * 650L + 200
            }
            "walk" -> whenFree { walkRandom() }
            else -> { // "move": play a saved move by name (or a random one)
                val moves = MoveStore.load(this)
                val want = cmd.arg.removePrefix("move").trim()
                val m = moves.firstOrNull { it.name.equals(want, ignoreCase = true) }
                    ?: moves.firstOrNull { want.isNotEmpty() && it.name.lowercase().contains(want) }
                    ?: if (want.isEmpty() || want == "random") moves.randomOrNull() else null
                if (m != null) whenFree { playMove(m) }
            }
        }
    }

    /** Runs an action as soon as the bot isn't busy typing or moving. */
    private fun whenFree(action: () -> Unit) {
        val wait = (busyUntil - System.currentTimeMillis()).coerceAtLeast(0L)
        lh.postDelayed({ action() }, wait + 50)
    }

    private fun queueChat(text: String) {
        chatQueue.addLast(text)
        lh.post(pump)
    }

    private val pump = object : Runnable {
        override fun run() {
            if (chatQueue.isEmpty()) return
            if (System.currentTimeMillis() >= busyUntil) sendChat(chatQueue.removeFirst())
            if (chatQueue.isNotEmpty()) lh.postDelayed(this, 500)
        }
    }

    // ---------------------------------------------------------------- auto mode

    private val tick = object : Runnable {
        override fun run() {
            if (!auto) return
            autoStep()
            val m = mood()
            h.postDelayed(this, Random.nextLong(m.gapMin, m.gapMax))
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
        ensureVision()
        toast("Hyper-Bot: Auto ON")
    }

    fun stopAuto() {
        auto = false
        h.removeCallbacksAndMessages(null)
        autoButton?.text = autoLabel()
    }

    private fun autoStep() {
        val now = System.currentTimeMillis()
        if (now < busyUntil || followTarget != null) return
        // always (re)announce that this is a bot: on start and every 10 minutes
        if (prefs.chatOn && now - lastIntro > 10 * 60_000L) {
            lastIntro = now
            lastChat = now
            sendChat(prefs.safeIntro())
            return
        }
        if (prefs.chatOn && now - lastChat > (prefs.chatIntervalSec * 1000L * mood().chatScale).toLong()) {
            sayRandomLine()
            return
        }
        // optional: change mood by itself every ~10 minutes, only among the moods you ticked
        if (prefs.moodRotate && now - moodSince > 10 * 60_000L) {
            val pool = availableMoods().filter { it.id != mood().id }
            if (pool.isNotEmpty()) setMood(pool.random(), false) else moodSince = now
        }
        val m = mood()
        val look = if (prefs.lookAround) m.look else 0
        val moves = if (prefs.movesInAuto && m.move > 0) MoveStore.load(this) else mutableListOf()
        val weights = listOf(
            "walk" to m.walk, "idle" to m.idle, "jump" to m.jump,
            "emote" to if (prefs.emotesOn) m.emote else 0,
            "move" to if (moves.isNotEmpty()) m.move else 0,
            "look" to look
        )
        val total = weights.sumOf { it.second }
        var roll = if (total > 0) Random.nextInt(total) else 0
        val pick = weights.firstOrNull { roll -= it.second; roll < 0 }?.first ?: "walk"
        when (pick) {
            "walk" -> if (prefs.shiftLock) shiftWalk() else walkRandom()
            "idle" -> busyUntil = now + Random.nextLong(2500, 6000) // just stand around for a bit
            "jump" -> jump()
            "emote" -> emoteRandom()
            "move" -> playMove(moves.random())
            "look" -> lookAround()
        }
    }
}
