package com.hyperbot.app

import android.content.Context

/**
 * Limits for follows YOU start (nearest player / by name), so the bot can't be used to hound anyone:
 *  - 10 min cooldown per player after a follow starts
 *  - max 3 of your follows per player per day
 *  - if a player tells the bot to stop / go away: blocked for 1 hour
 * Follows a player asks for themselves ("bot follow me") don't use these limits.
 * Only names + times are kept on this device (no chat), and entries older than a day are dropped.
 */
class FollowGuard(ctx: Context) {
    private val p = ctx.getSharedPreferences("hyperbot_follow", Context.MODE_PRIVATE)

    private fun key(name: String) = name.lowercase().filter { it.isLetterOrDigit() || it == '_' }

    private fun starts(name: String, now: Long): List<Long> =
        (p.getString("s_" + key(name), "") ?: "").split(",").mapNotNull { it.toLongOrNull() }
            .filter { now - it < DAY }

    /** null if allowed, otherwise a short reason. */
    fun check(name: String, now: Long = System.currentTimeMillis()): String? {
        val blockedUntil = p.getLong("b_" + key(name), 0L)
        if (now < blockedUntil) return "$name asked the bot to stop (wait ${(blockedUntil - now) / 60_000 + 1} min)"
        val s = starts(name, now)
        if (s.size >= MAX_PER_DAY) return "already followed $name $MAX_PER_DAY times today"
        val last = s.maxOrNull()
        if (last != null && now - last < COOLDOWN) return "cooldown for $name (${(COOLDOWN - (now - last)) / 60_000 + 1} min left)"
        return null
    }

    fun noteStart(name: String, now: Long = System.currentTimeMillis()) {
        val s = starts(name, now) + now
        p.edit().putString("s_" + key(name), s.joinToString(",")).apply()
    }

    fun block(name: String, now: Long = System.currentTimeMillis()) {
        p.edit().putLong("b_" + key(name), now + BLOCK).apply()
    }

    companion object {
        const val COOLDOWN = 10 * 60_000L
        const val BLOCK = 60 * 60_000L
        const val DAY = 24 * 60 * 60_000L
        const val MAX_PER_DAY = 3
    }
}
