package com.hyperbot.app

/**
 * A mood changes how Auto behaves: how often it walks, idles, jumps, emotes, plays moves and looks around,
 * how fast it walks (joystick push), how long it waits between actions, and (optionally) its chat lines.
 * Moods never change the bot disclosure: the intro is still said on start and every 10 minutes.
 */
data class Mood(
    val id: String,
    val label: String,
    val walk: Int,
    val idle: Int,
    val jump: Int,
    val emote: Int,
    val move: Int,
    val look: Int,
    /** 0.3..1: how far the joystick is pushed (less = slower walk). */
    val stick: Float,
    val gapMin: Long,
    val gapMax: Long,
    /** Multiplies the chat interval (2 = chats half as often). */
    val chatScale: Float,
    val emotes: List<String>,
    val lines: List<String>,
    val replies: List<String>
)

object Moods {
    val NORMAL = Mood(
        "normal", "Normal", walk = 5, idle = 2, jump = 2, emote = 1, move = 2, look = 1,
        stick = 1f, gapMin = 1500, gapMax = 3500, chatScale = 1f,
        emotes = Prefs.EMOTES, lines = emptyList(), replies = emptyList()
    )

    val ALL: List<Mood> = listOf(
        NORMAL,
        Mood("chill", "Chill", 3, 5, 0, 1, 1, 3, 0.55f, 2500, 5000, 1.5f,
            listOf("wave", "point"),
            listOf("just chilling", "nice vibes here", "peaceful bot hours", "taking it slow today"),
            listOf("hey {name} just chilling", "sup {name}", "hi {name} relaxing over here")),
        Mood("happy", "Happy", 4, 1, 3, 3, 2, 1, 1f, 1300, 3000, 1f,
            listOf("cheer", "wave", "dance"),
            listOf("best day ever!", "yay :D", "beep boop :D", "happy bot noises"),
            listOf("hiii {name} :D", "yay hi {name}!", "{name}! hello :D")),
        Mood("hyper", "Hyper", 6, 0, 5, 2, 2, 1, 1f, 700, 1600, 1f,
            listOf("dance", "dance2", "dance3", "cheer"),
            listOf("zoom zoom!", "cant stop wont stop", "WHEEE", "bot speed activated"),
            listOf("HI {name}!!", "{name} hiii zoom", "hey {name} catch me lol")),
        Mood("sleepy", "Sleepy", 1, 7, 0, 1, 0, 2, 0.4f, 4000, 8000, 2f,
            listOf("wave"),
            listOf("*yawn*", "sleepy bot mode zzz", "low battery...", "so eepy"),
            listOf("hi {name}... *yawn*", "mm hi {name} zzz", "hey {name} im so sleepy")),
        Mood("shy", "Shy", 3, 4, 0, 1, 0, 3, 0.6f, 2000, 4500, 2f,
            listOf("wave", "point"),
            listOf("..hi", "o/", "*hides behind a wall*"),
            listOf("oh! hi {name} o/", "..hi {name}", "h-hi {name}")),
        Mood("party", "Party", 2, 0, 3, 6, 3, 0, 1f, 1000, 2500, 1f,
            listOf("dance", "dance2", "dance3", "cheer"),
            listOf("party time!", "dance with me!", "beep boop bass drop", "everybody dance"),
            listOf("{name} dance with me!", "hi {name} its a party", "hey {name} party bot here")),
        Mood("curious", "Curious", 5, 1, 1, 1, 1, 5, 0.8f, 1500, 3200, 1f,
            listOf("point", "wave"),
            listOf("whats over there?", "exploring...", "ooh what is this", "scanning area beep"),
            listOf("hi {name} what are you doing?", "ooh hi {name}", "{name} whats over there?")),
        Mood("silly", "Silly", 3, 1, 4, 3, 2, 2, 1f, 1200, 3000, 1f,
            listOf("laugh", "dance2", "point"),
            listOf("i am a potato bot", "beep boop beep?", "who put me here lol", "i forgot how to walk"),
            listOf("hi {name} im a potato", "{name}! beep?", "hey {name} lol"))
    )

    fun byId(id: String): Mood = ALL.firstOrNull { it.id == id } ?: NORMAL
}
