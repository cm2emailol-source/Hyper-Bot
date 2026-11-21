package com.hyperbot.app

/**
 * Decides when Hyper-Bot should answer someone in chat.
 * Works only on text read from the screen in memory: nothing is stored or sent anywhere.
 */
class ChatBrain {

    data class ChatLine(val name: String, val message: String)
    data class Command(val name: String, val arg: String, val from: String)

    private val seen = LinkedHashSet<String>()
    private var primed = false
    private val recentOwn = ArrayDeque<String>()
    private val lastReplyTo = HashMap<String, Long>()
    private val replyTimes = ArrayDeque<Long>()
    private var lastReply = 0L
    private var lastCommand = 0L
    private var lastHelp = 0L
    private val lastCommandFrom = HashMap<String, Long>()
    private val commandTimes = ArrayDeque<Long>()

    val knownCommands = setOf("help", "commands", "hi", "hello", "hey", "wave", "dance", "cheer", "laugh", "point", "jump", "walk", "move", "follow", "come", "stop", "mood")

    private val greetings = setOf("hi", "hii", "hiii", "hello", "helo", "hey", "heyy", "heya", "sup", "yo", "hola", "wassup", "howdy", "hai")

    /** Remember what the bot itself said, so it never answers its own messages. */
    fun noteOwn(text: String) {
        recentOwn.addLast(norm(text))
        while (recentOwn.size > 12) recentOwn.removeFirst()
    }

    fun reset() {
        seen.clear()
        primed = false
    }

    /** Returns only chat lines that weren't on screen before. The first read just learns what's already there. */
    fun newLines(rawLines: List<String>): List<String> {
        val fresh = mutableListOf<String>()
        for (l in rawLines) {
            val k = norm(l)
            if (k.length < 2) continue
            if (seen.add(k)) fresh.add(l)
        }
        while (seen.size > 300) seen.remove(seen.first())
        if (!primed) {
            primed = true
            return emptyList()
        }
        return fresh
    }

    /** Roblox chat lines look like "[Name]: message" or "Name: message". */
    fun parse(line: String): ChatLine? {
        val m = Regex("""^\s*\[?([^\]:\[]{1,32})\]?\s*:\s*(.+)$""").find(line) ?: return null
        val name = m.groupValues[1].trim()
        val msg = m.groupValues[2].trim()
        if (name.isEmpty() || msg.isEmpty()) return null
        return ChatLine(name, msg)
    }

    /**
     * Should the bot reply? Yes if someone mentions it, or greets shortly after the bot spoke.
     * Limits: 12 s between replies, 60 s per person, at most 4 replies a minute.
     */
    /** Public version of [ignored] (own messages, slash commands). */
    fun isIgnored(c: ChatLine, botName: String) = ignored(c, botName)

    /** True for the bot's own messages, slash commands and anything it should never react to. */
    private fun ignored(c: ChatLine, botName: String): Boolean {
        val msg = norm(c.message)
        if (botName.isNotBlank() && norm(c.name) == norm(botName)) return true
        if (recentOwn.any { it.isNotEmpty() && (msg == it || it.contains(msg) && msg.length > 6) }) return true
        return msg.startsWith("/")
    }

    /**
     * "bot dance", "robot wave", "<botname> jump", "@<botname> spin" ... -> Command, or null.
     * Limits: one command every 5 s, each person every 15 s, at most 8 a minute.
     */
    fun command(c: ChatLine, botName: String, now: Long): Command? {
        if (ignored(c, botName)) return null
        val msg = norm(c.message).replace(Regex("[^a-z0-9 ]"), " ").replace(Regex("\\s+"), " ").trim()
        val prefixes = mutableListOf("bot", "robot", "hyperbot", "hyper bot")
        if (botName.isNotBlank()) prefixes.add(0, norm(botName).replace(Regex("[^a-z0-9 ]"), " ").trim())
        var rest: String? = null
        for (p in prefixes) {
            if (p.isNotEmpty() && msg.startsWith("$p ")) {
                rest = msg.removePrefix(p).trim()
                break
            }
        }
        if (rest.isNullOrEmpty()) return null
        val parts = rest.split(" ", limit = 2)
        val cmd = parts[0]
        val arg = if (parts.size > 1) parts[1].trim() else ""

        val from = norm(c.name)
        if (now - lastCommand < 5_000) return null
        if (now - (lastCommandFrom[from] ?: 0L) < 8_000) return null
        while (commandTimes.isNotEmpty() && now - commandTimes.first() > 60_000) commandTimes.removeFirst()
        if (commandTimes.size >= 8) return null
        if ((cmd == "help" || cmd == "commands") && now - lastHelp < 60_000) return null

        lastCommand = now
        lastCommandFrom[from] = now
        commandTimes.addLast(now)
        if (cmd == "help" || cmd == "commands") lastHelp = now
        // unknown words are treated as a saved move's name: "bot spin" -> move "spin"
        return if (cmd in knownCommands) Command(cmd, arg, c.name) else Command("move", rest, c.name)
    }

    /** Shares the reply limits (12 s, 60 s per person, 4/min) for chat answers to commands like "bot hi". */
    fun allowChatAnswer(name: String, now: Long): Boolean {
        val n = norm(name)
        if (now - lastReply < 12_000) return false
        if (now - (lastReplyTo[n] ?: 0L) < 60_000) return false
        while (replyTimes.isNotEmpty() && now - replyTimes.first() > 60_000) replyTimes.removeFirst()
        if (replyTimes.size >= 4) return false
        lastReply = now
        lastReplyTo[n] = now
        replyTimes.addLast(now)
        return true
    }

    /** Conversation limits for the Smart Brain: 6 s between answers, 10 s per person, max 5 a minute. */
    fun allowTalk(name: String, now: Long): Boolean {
        val n = norm(name)
        if (now - lastReply < 6_000) return false
        if (now - (lastReplyTo[n] ?: 0L) < 10_000) return false
        while (replyTimes.isNotEmpty() && now - replyTimes.first() > 60_000) replyTimes.removeFirst()
        if (replyTimes.size >= 5) return false
        lastReply = now
        lastReplyTo[n] = now
        replyTimes.addLast(now)
        return true
    }

    fun shouldReply(c: ChatLine, botName: String, lastOwnChat: Long, now: Long): Boolean {
        if (ignored(c, botName)) return false
        val msg = norm(c.message)
        val name = norm(c.name)
        if (msg.startsWith("bot ") || msg.startsWith("robot ")) return false // handled as a command

        val words = msg.split(Regex("[^a-z0-9]+")).filter { it.isNotEmpty() }
        val mentioned = words.any { it == "bot" || it == "robot" || it == "bots" } ||
            (botName.isNotBlank() && msg.contains(norm(botName)))
        val greeted = words.any { it in greetings }
        val recentlySpoke = now - lastOwnChat < 120_000
        if (!(mentioned || (greeted && recentlySpoke))) return false

        if (now - lastReply < 12_000) return false
        if (now - (lastReplyTo[name] ?: 0L) < 20_000) return false
        while (replyTimes.isNotEmpty() && now - replyTimes.first() > 60_000) replyTimes.removeFirst()
        if (replyTimes.size >= 5) return false

        lastReply = now
        lastReplyTo[name] = now
        replyTimes.addLast(now)
        return true
    }

    /** Fills {name} with a safe, short version of the player's name. */
    fun fill(template: String, name: String): String {
        val clean = name.filter { it.isLetterOrDigit() || it == '_' }.take(20).ifEmpty { "friend" }
        return template.replace("{name}", clean)
    }

    private fun norm(s: String) = s.lowercase().replace(Regex("\\s+"), " ").trim()
}
