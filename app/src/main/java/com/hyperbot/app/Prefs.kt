package com.hyperbot.app

import android.content.Context

/** Saved settings: chat lines, timing, toggles and calibrated Roblox control positions. */
class Prefs(ctx: Context) {
    private val p = ctx.getSharedPreferences("hyperbot", Context.MODE_PRIVATE)

    var intro: String
        get() = p.getString("intro", DEFAULT_INTRO) ?: DEFAULT_INTRO
        set(v) = p.edit().putString("intro", v).apply()

    /** The intro must say it's a bot. If it doesn't, the default intro is used instead. */
    fun safeIntro(): String = if (intro.contains("bot", ignoreCase = true)) intro.trim() else DEFAULT_INTRO

    var linesText: String
        get() = p.getString("lines", DEFAULT_LINES) ?: DEFAULT_LINES
        set(v) = p.edit().putString("lines", v).apply()

    val lines: List<String>
        get() = linesText.split("\n").map { it.trim() }.filter { it.isNotEmpty() }

    /** Seconds between chat lines in Auto mode. Never faster than MIN_CHAT_INTERVAL. */
    var chatIntervalSec: Int
        get() = p.getInt("chatInterval", 45).coerceAtLeast(MIN_CHAT_INTERVAL)
        set(v) = p.edit().putInt("chatInterval", v.coerceAtLeast(MIN_CHAT_INTERVAL)).apply()

    var chatOn: Boolean
        get() = p.getBoolean("chatOn", true)
        set(v) = p.edit().putBoolean("chatOn", v).apply()

    var lastChatDiag: String
        get() = p.getString("lastChatDiag", "") ?: ""
        set(v) = p.edit().putString("lastChatDiag", v).apply()

    var emotesOn: Boolean
        get() = p.getBoolean("emotesOn", true)
        set(v) = p.edit().putBoolean("emotesOn", v).apply()

    /** Control position as fractions (0..1) of the screen width / height. */
    fun point(name: String): Pair<Float, Float> {
        val d = POINTS[name] ?: Pair(0.5f, 0.5f)
        return Pair(p.getFloat("${name}_x", d.first), p.getFloat("${name}_y", d.second))
    }

    fun setPoint(name: String, x: Float, y: Float) {
        p.edit().putFloat("${name}_x", x.coerceIn(0f, 1f)).putFloat("${name}_y", y.coerceIn(0f, 1f)).apply()
    }

    companion object {
        const val MIN_CHAT_INTERVAL = 30
        const val DEFAULT_INTRO = "Hyper-Bot online - I'm a bot! Say hi :)"
        val DEFAULT_LINES = listOf(
            "hey!",
            "beep boop",
            "nice outfit!",
            "hello humans o/",
            "I'm a friendly bot",
            "wave if you see me!",
            "*happy bot noises*",
            "having a great day here"
        ).joinToString("\n")

        val EMOTES = listOf("wave", "point", "cheer", "laugh", "dance", "dance2", "dance3")

        /**
         * Roblox mobile controls (landscape), as fractions of the screen. Rough defaults:
         * calibrate once with the bubble's "Calibrate" button so they match your phone.
         * JOY = joystick centre, JUMP = jump button, CHAT = chat icon, BOX = chat input box, SEND = send button.
         */
        val POINTS: LinkedHashMap<String, Pair<Float, Float>> = linkedMapOf(
            "JOY" to Pair(0.18f, 0.72f),
            "JUMP" to Pair(0.88f, 0.78f),
            "CHAT" to Pair(0.12f, 0.06f),
            "BOX" to Pair(0.30f, 0.38f),
            "SEND" to Pair(0.55f, 0.38f)
        )
    }
}
