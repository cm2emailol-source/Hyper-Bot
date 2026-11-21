package com.hyperbot.app

/**
 * Decides when Hyper-Bot should answer someone in chat.
 * Works only on text read from the screen in memory: nothing is stored or sent anywhere.
 */
class ChatBrain {

    data class ChatLine(val name: String, val message: String)

    private val seen = LinkedHashSet<String>()
    private var primed = false
    private val recentOwn = ArrayDeque<String>()
    private val lastReplyTo = HashMap<String, Long>()
    private val replyTimes = ArrayDeque<Long>()
    private var lastReply = 0L

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
    fun shouldReply(c: ChatLine, botName: String, lastOwnChat: Long, now: Long): Boolean {
        val msg = norm(c.message)
        val name = norm(c.name)
        if (botName.isNotBlank() && name == norm(botName)) return false
        if (recentOwn.any { it.isNotEmpty() && (msg == it || it.contains(msg) && msg.length > 6) }) return false
        if (msg.startsWith("/")) return false

        val words = msg.split(Regex("[^a-z0-9]+")).filter { it.isNotEmpty() }
        val mentioned = words.any { it == "bot" || it == "robot" || it == "bots" } ||
            (botName.isNotBlank() && msg.contains(norm(botName)))
        val greeted = words.any { it in greetings }
        val recentlySpoke = now - lastOwnChat < 120_000
        if (!(mentioned || (greeted && recentlySpoke))) return false

        if (now - lastReply < 12_000) return false
        if (now - (lastReplyTo[name] ?: 0L) < 60_000) return false
        while (replyTimes.isNotEmpty() && now - replyTimes.first() > 60_000) replyTimes.removeFirst()
        if (replyTimes.size >= 4) return false

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
