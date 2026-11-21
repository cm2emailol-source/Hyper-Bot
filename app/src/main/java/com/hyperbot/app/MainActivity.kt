package com.hyperbot.app

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.provider.Settings
import android.text.InputType
import android.util.TypedValue
import android.view.Gravity
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

/** Setup screen: turn the service on, edit chat lines and timing, show the bubble. */
class MainActivity : Activity() {

    private lateinit var prefs: Prefs
    private lateinit var status: TextView
    private lateinit var chatDiag: TextView
    private lateinit var introEdit: EditText
    private lateinit var linesEdit: EditText
    private lateinit var intervalEdit: EditText
    private lateinit var chatBox: CheckBox
    private lateinit var emoteBox: CheckBox

    private fun dp(v: Int): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        prefs = Prefs(this)

        val col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(24), dp(20), dp(24))
        }
        fun label(t: String, size: Float = 14f, color: Int = Color.DKGRAY) = TextView(this).apply {
            text = t
            textSize = size
            setTextColor(color)
            setPadding(0, dp(10), 0, dp(4))
        }
        fun button(t: String, onClick: () -> Unit) = Button(this).apply {
            text = t
            isAllCaps = false
            setOnClickListener { onClick() }
        }

        col.addView(label("Hyper-Bot", 26f, Color.rgb(0, 150, 230)))
        col.addView(label("A friendly, clearly-labelled Roblox bot: walks, jumps, emotes and says your lines. It always announces that it's a bot."))
        status = label("")
        col.addView(status)

        col.addView(label("1. Switch Hyper-Bot on in Accessibility (Installed apps > Hyper-Bot).", 15f, Color.BLACK))
        col.addView(button("Open Accessibility settings") {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        })

        col.addView(label("2. Intro line (must contain the word \"bot\"):", 15f, Color.BLACK))
        introEdit = EditText(this).apply { setText(prefs.intro) }
        col.addView(introEdit)

        col.addView(label("3. Chat lines (one per line):", 15f, Color.BLACK))
        linesEdit = EditText(this).apply {
            setText(prefs.linesText)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            minLines = 5
            gravity = Gravity.TOP or Gravity.START
        }
        col.addView(linesEdit)

        col.addView(label("Seconds between chat lines in Auto (30 or more):", 15f, Color.BLACK))
        intervalEdit = EditText(this).apply {
            setText(prefs.chatIntervalSec.toString())
            inputType = InputType.TYPE_CLASS_NUMBER
        }
        col.addView(intervalEdit)

        chatBox = CheckBox(this).apply { text = "Chat in Auto mode"; isChecked = prefs.chatOn }
        emoteBox = CheckBox(this).apply { text = "Emotes in Auto mode"; isChecked = prefs.emotesOn }
        col.addView(chatBox)
        col.addView(emoteBox)

        col.addView(button("Save") { save() })
        col.addView(button("Show the bubble") {
            save()
            val s = BotService.instance
            if (s == null) toast("Switch Hyper-Bot on in Accessibility first") else { s.showBubble(); toast("Bubble shown - open Roblox") }
        })

        col.addView(label(
            "Tips:\n" +
            "- Use an ALT account, not your main.\n" +
            "- In Roblox, tap the bubble > Calibrate, drag JOY/JUMP/CHAT/BOX/SEND onto the real buttons, then Save calibration.\n" +
            "- Chat is limited to one line every 30+ seconds so it never spams.\n" +
            "- STOP on the panel stops everything. Turning the service off in Accessibility removes the bubble.",
            13f
        ))

        col.addView(label("Last chat test (screenshot this if chat doesn't work):", 15f, Color.BLACK))
        chatDiag = label("", 12f)
        col.addView(chatDiag)

        setContentView(ScrollView(this).apply { addView(col) })
    }

    override fun onResume() {
        super.onResume()
        val on = BotService.instance != null
        status.text = if (on) "Status: service ON" else "Status: service OFF - do step 1"
        status.setTextColor(if (on) Color.rgb(0, 140, 60) else Color.rgb(200, 40, 40))
        chatDiag.text = prefs.lastChatDiag.ifEmpty { "(none yet - tap the bubble > Chat test in Roblox)" }
    }

    private fun save() {
        prefs.intro = introEdit.text.toString()
        prefs.linesText = linesEdit.text.toString()
        prefs.chatIntervalSec = intervalEdit.text.toString().toIntOrNull() ?: 45
        prefs.chatOn = chatBox.isChecked
        prefs.emotesOn = emoteBox.isChecked
        intervalEdit.setText(prefs.chatIntervalSec.toString())
        if (!prefs.intro.contains("bot", ignoreCase = true)) {
            toast("Intro must contain \"bot\" - using the default intro")
        } else {
            toast("Saved")
        }
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
}
