package com.hyperbot.app

import android.app.Activity
import android.app.AlertDialog
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
    private lateinit var movesBox: LinearLayout
    private lateinit var botNameEdit: EditText
    private lateinit var followEdit: EditText
    private lateinit var syncEdit: EditText
    private lateinit var qaEdit: EditText
    private lateinit var repliesEdit: EditText
    private lateinit var waveBox: CheckBox
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

        col.addView(label("Listen: reply when someone talks to the bot", 17f, Color.rgb(0, 150, 230)))
        col.addView(label("Bot's Roblox display name (so it knows when it's mentioned):", 15f, Color.BLACK))
        botNameEdit = EditText(this).apply { setText(prefs.botName); setSingleLine() }
        col.addView(botNameEdit)
        col.addView(label("Reply lines ({name} = the player's name), one per line:", 15f, Color.BLACK))
        repliesEdit = EditText(this).apply {
            setText(prefs.replyLinesText)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            minLines = 4
            gravity = Gravity.TOP or Gravity.START
        }
        col.addView(repliesEdit)
        waveBox = CheckBox(this).apply { text = "Wave before replying"; isChecked = prefs.waveOnReply }
        col.addView(waveBox)
        col.addView(CheckBox(this).apply {
            text = "Allow chat commands (\"bot dance\", \"bot help\" ...)"
            isChecked = prefs.commandsOn
            setOnCheckedChangeListener { _, c -> prefs.commandsOn = c }
        })
        col.addView(label(
            "Commands: bot help, bot hi, bot wave / dance / cheer / laugh / point, bot jump, bot walk, " +
            "bot follow me (follows only that player, max 60 s), bot stop, bot mood, " +
            "bot <move name> (plays your saved move). Most are silent actions. Limits: 1 command per 5 s, " +
            "each person every 15 s, 8 per minute.", 13f))
        col.addView(label(
            "It replies when someone says \"bot\" / \"robot\" / its name, or says hi soon after the bot spoke. " +
            "Max one reply every 12 s, one per person per minute, 4 per minute. Chat is read from the screen in memory only - " +
            "nothing is saved or sent. In Roblox: Calibrate, put LOG1 / LOG2 on the corners of the chat messages, then use " +
            "Listen test and Listen: ON in the bubble.", 13f))

        col.addView(label("Smart Brain", 17f, Color.rgb(0, 150, 230)))
        col.addView(CheckBox(this).apply {
            text = "Smart Brain: answer questions, remember people this session, chat games"
            isChecked = prefs.smartOn
            setOnCheckedChangeListener { _, c -> prefs.smartOn = c }
        })
        col.addView(label(
            "No AI model: a built-in topic database with fuzzy matching (typos and slang are fine). " +
            "Players say \"bot ...\" or mention its name: bot how are you, bot are you a bot, bot joke, bot games, " +
            "bot rps / guess / trivia / riddle / 8ball / coin / dice, \"bot my favorite color is blue\" (it remembers until Listen stops). " +
            "Always says it's a bot. Max 5 answers a minute.", 13f))
        col.addView(label("Your own answers (one per line: question => answer):", 13f))
        qaEdit = EditText(this).apply {
            setText(prefs.customQaText)
            minLines = 3
            gravity = android.view.Gravity.TOP
        }
        col.addView(qaEdit)

        col.addView(label("Moods", 17f, Color.rgb(0, 150, 230)))
        col.addView(label("Tick the moods you want. Pick the current one from the bubble's Mood button (Normal is always there).", 13f))
        for (md in Moods.ALL) {
            if (md.id == "normal") continue
            col.addView(CheckBox(this).apply {
                text = md.label
                isChecked = md.id in prefs.enabledMoods
                setOnCheckedChangeListener { _, c ->
                    prefs.enabledMoods = if (c) prefs.enabledMoods + md.id else prefs.enabledMoods - md.id
                }
            })
        }
        col.addView(CheckBox(this).apply {
            text = "Use the mood's own chat lines and replies (mixed with yours)"
            isChecked = prefs.moodLines
            setOnCheckedChangeListener { _, c -> prefs.moodLines = c }
        })
        col.addView(CheckBox(this).apply {
            text = "Change mood by itself every ~10 min (only ticked moods)"
            isChecked = prefs.moodRotate
            setOnCheckedChangeListener { _, c -> prefs.moodRotate = c }
        })

        col.addView(label("Camera", 17f, Color.rgb(0, 150, 230)))
        col.addView(CheckBox(this).apply {
            text = "Look around in Auto (swipes the camera at CAM)"
            isChecked = prefs.lookAround
            setOnCheckedChangeListener { _, c -> prefs.lookAround = c }
        })
        col.addView(CheckBox(this).apply {
            text = "The game has a shift-lock button (bot taps SHIFT when Shift Lock mode toggles)"
            isChecked = prefs.shiftButton
            setOnCheckedChangeListener { _, c -> prefs.shiftButton = c }
        })
        col.addView(label(
            "Shift Lock mode (bubble > Shift Lock): Auto walks forward and steers with the camera, so the avatar always " +
            "faces where it looks, and Look around turns the whole avatar. Calibrate CAM onto an empty spot on the right " +
            "half (not on buttons or chat). If the game has a shift-lock button, calibrate SHIFT on it and tick the box above; " +
            "if the bot's ON/OFF ever gets out of sync with the game, tap the game's button once yourself.", 13f))

        col.addView(label("Follow", 17f, Color.rgb(0, 150, 230)))
        col.addView(label("Player to follow (display name shown above their head):", 13f))
        followEdit = EditText(this).apply { setText(prefs.followName); setSingleLine() }
        col.addView(followEdit)
        col.addView(label(
            "Start it from the bubble: Follow... > Nearest player, this name, or someone who chatted recently. " +
            "Limits: max 60 s per follow, 10 min cooldown per player, max 3 times per player per day. " +
            "The bot tells them it's a bot following them and turns Listen on; if they say stop / go away it stops, " +
            "says sorry and won't follow them again for an hour. It can only follow someone it can see on screen.", 13f))

        col.addView(label("Shadow clone (copies your PC)", 17f, Color.rgb(0, 150, 230)))
        col.addView(label(
            "Play your main on the PC; this tablet's account copies your moves (WASD, jump, arrow-key camera) live over your home Wi-Fi. " +
            "In Hyper-Bot PC open the Sync tab, type this tablet's address and the code below, tick Send. Then tap Clone in the bubble. " +
            "The app only LISTENS on your home network: it never sends anything and ignores anything without your code.", 13f))
        col.addView(label("This tablet's address: " + CloneLink.localIp() + "    port " + CloneLink.PORT, 14f, Color.BLACK))
        col.addView(label("Pairing code:", 13f))
        syncEdit = EditText(this).apply { setText(prefs.syncCode); setSingleLine(); inputType = android.text.InputType.TYPE_CLASS_NUMBER }
        col.addView(syncEdit)

        col.addView(label("Vision lite", 17f, Color.rgb(0, 150, 230)))
        col.addView(CheckBox(this).apply {
            text = "Turn to face people who talk to it"
            isChecked = prefs.faceTalker
            setOnCheckedChangeListener { _, c -> prefs.faceTalker = c }
        })
        col.addView(CheckBox(this).apply {
            text = "Stuck detection (turn around when walking into walls)"
            isChecked = prefs.stuckOn
            setOnCheckedChangeListener { _, c -> prefs.stuckOn = c }
        })
        col.addView(label(
            "Vision finds players by the name tag above their head, so name tags must be visible. " +
            "It takes about one screenshot per second only while Listen, Auto or Follow is on; nothing is saved.", 13f))

        col.addView(label("Moves (record them in Roblox: bubble > Moves > + Record new move):", 15f, Color.BLACK))
        col.addView(CheckBox(this).apply {
            text = "Use my moves in Auto mode"
            isChecked = prefs.movesInAuto
            setOnCheckedChangeListener { _, c -> prefs.movesInAuto = c }
        })
        movesBox = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        col.addView(movesBox)

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
        refreshMoves()
    }

    private fun save() {
        prefs.followName = followEdit.text.toString()
        if (syncEdit.text.toString().length >= 4) prefs.syncCode = syncEdit.text.toString()
        prefs.customQaText = qaEdit.text.toString()
        prefs.intro = introEdit.text.toString()
        prefs.linesText = linesEdit.text.toString()
        prefs.chatIntervalSec = intervalEdit.text.toString().toIntOrNull() ?: 45
        prefs.chatOn = chatBox.isChecked
        prefs.emotesOn = emoteBox.isChecked
        prefs.botName = botNameEdit.text.toString()
        prefs.replyLinesText = repliesEdit.text.toString()
        prefs.waveOnReply = waveBox.isChecked
        intervalEdit.setText(prefs.chatIntervalSec.toString())
        if (!prefs.intro.contains("bot", ignoreCase = true)) {
            toast("Intro must contain \"bot\" - using the default intro")
        } else {
            toast("Saved")
        }
    }

    /** Lists saved moves with rename and delete. */
    private fun refreshMoves() {
        movesBox.removeAllViews()
        val moves = MoveStore.load(this)
        if (moves.isEmpty()) {
            movesBox.addView(TextView(this).apply { text = "No moves yet."; setPadding(0, dp(4), 0, dp(4)) })
            return
        }
        moves.forEachIndexed { i, mv ->
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }
            val nameEdit = EditText(this).apply { setText(mv.name); setSingleLine() }
            row.addView(nameEdit, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            row.addView(Button(this).apply {
                text = "Rename"
                isAllCaps = false
                setOnClickListener {
                    val all = MoveStore.load(this@MainActivity)
                    if (i < all.size) {
                        all[i].name = nameEdit.text.toString().trim().ifEmpty { all[i].name }
                        MoveStore.save(this@MainActivity, all)
                        toast("Renamed")
                        refreshMoves()
                    }
                }
            })
            row.addView(Button(this).apply {
                text = "Delete"
                isAllCaps = false
                setOnClickListener {
                    AlertDialog.Builder(this@MainActivity)
                        .setTitle("Delete ${mv.name}?")
                        .setMessage("This can't be undone.")
                        .setPositiveButton("Delete") { _, _ ->
                            val all = MoveStore.load(this@MainActivity)
                            if (i < all.size) {
                                all.removeAt(i)
                                MoveStore.save(this@MainActivity, all)
                            }
                            refreshMoves()
                        }
                        .setNegativeButton("Cancel", null)
                        .show()
                }
            })
            movesBox.addView(row)
            movesBox.addView(TextView(this).apply {
                text = "   ${mv.strokes.size} taps/swipes, ${"%.1f".format(mv.durationMs / 1000.0)} s"
                textSize = 12f
                setTextColor(Color.GRAY)
            })
        }
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
}
