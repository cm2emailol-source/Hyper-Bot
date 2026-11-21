package com.hyperbot.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** One recorded finger position: x, y as fractions (0..1) of the screen, t = ms since the move started. */
data class TouchPoint(val x: Float, val y: Float, val t: Long)

/** One finger's path from touching down to lifting off. */
class Stroke(val points: MutableList<TouchPoint> = mutableListOf()) {
    val start: Long get() = points.first().t
    val end: Long get() = points.last().t
}

/** A saved move: a name plus all the finger strokes recorded for it. */
class Move(var name: String, val strokes: MutableList<Stroke> = mutableListOf()) {
    val durationMs: Long get() = strokes.maxOfOrNull { it.end } ?: 0L
}

/** Saves and loads moves (as JSON in the app's private storage). */
object MoveStore {
    private fun prefs(ctx: Context) = ctx.getSharedPreferences("hyperbot_moves", Context.MODE_PRIVATE)

    fun load(ctx: Context): MutableList<Move> {
        val out = mutableListOf<Move>()
        val raw = prefs(ctx).getString("moves", "[]") ?: "[]"
        try {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                val m = Move(o.optString("name", "Move ${i + 1}"))
                val sa = o.optJSONArray("strokes") ?: JSONArray()
                for (j in 0 until sa.length()) {
                    val pa = sa.getJSONArray(j)
                    val s = Stroke()
                    for (k in 0 until pa.length()) {
                        val p = pa.getJSONArray(k)
                        s.points.add(TouchPoint(p.getDouble(0).toFloat(), p.getDouble(1).toFloat(), p.getLong(2)))
                    }
                    if (s.points.isNotEmpty()) m.strokes.add(s)
                }
                out.add(m)
            }
        } catch (_: Exception) {
        }
        return out
    }

    fun save(ctx: Context, moves: List<Move>) {
        val arr = JSONArray()
        for (m in moves) {
            val sa = JSONArray()
            for (s in m.strokes) {
                val pa = JSONArray()
                for (p in s.points) {
                    pa.put(JSONArray().put(p.x.toDouble()).put(p.y.toDouble()).put(p.t))
                }
                sa.put(pa)
            }
            arr.put(JSONObject().put("name", m.name).put("strokes", sa))
        }
        prefs(ctx).edit().putString("moves", arr.toString()).apply()
    }

    fun nextName(moves: List<Move>): String {
        var n = moves.size + 1
        while (moves.any { it.name == "Move $n" }) n++
        return "Move $n"
    }
}
