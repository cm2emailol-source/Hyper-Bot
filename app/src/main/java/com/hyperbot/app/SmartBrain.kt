package com.hyperbot.app

import kotlin.random.Random

/**
 * Hyper-Bot's "Smart Brain": no AI model, just a big topic database, fuzzy word matching,
 * short-term memory for this session, mini-games and mood flavour.
 *
 * Memory is in RAM only (names, what someone told it, game state) and is wiped when Listen stops
 * or after 30 minutes without talking. Nothing is saved or sent anywhere.
 * It always admits it's a bot.
 */
class SmartBrain {

    data class Reply(val text: String, val topic: String, val emote: String? = null)

    private class Topic(val id: String, val groups: List<List<String>>, val replies: List<String>, val emote: String? = null)

    private class Person(var lastSeen: Long = 0L, var talks: Int = 0, var lastTopic: String = "", val facts: HashMap<String, String> = HashMap())

    private class Game(val kind: String, val answer: String, val started: Long, var tries: Int = 0)

    private val people = HashMap<String, Person>()
    private val games = HashMap<String, Game>()
    private val lastPick = HashMap<String, String>()

    fun clear() {
        people.clear()
        games.clear()
    }

    private fun key(name: String) = name.lowercase().filter { it.isLetterOrDigit() || it == '_' }

    /** True if this player is in the middle of a game (so a plain "rock" or "7" counts as their move). */
    fun inGame(name: String, now: Long = System.currentTimeMillis()): Boolean {
        val g = games[key(name)] ?: return false
        if (now - g.started > 120_000) {
            games.remove(key(name))
            return false
        }
        return true
    }

    // ------------------------------------------------------------------ text cleanup

    private val slang = mapOf(
        "u" to "you", "ur" to "your", "youre" to "you are", "r" to "are", "fav" to "favorite", "favourite" to "favorite",
        "fave" to "favorite", "colour" to "color", "wat" to "what", "wut" to "what", "wht" to "what", "whats" to "what is",
        "wats" to "what is", "hows" to "how is", "howre" to "how are", "pls" to "please", "plz" to "please", "ty" to "thanks",
        "thx" to "thanks", "thank" to "thanks", "im" to "i am", "ive" to "i have", "dont" to "do not", "cant" to "can not",
        "wanna" to "want to", "gonna" to "going to", "ya" to "you", "yall" to "you all", "bc" to "because", "cuz" to "because",
        "abt" to "about", "rn" to "right now", "idk" to "i do not know", "ily" to "i love you", "luv" to "love",
        "gn" to "good night", "gm" to "good morning", "brb" to "be right back", "cya" to "bye", "bai" to "bye",
        "byee" to "bye", "byeee" to "bye", "hii" to "hi", "hiii" to "hi", "hiiii" to "hi", "helo" to "hello", "hai" to "hi",
        "heyy" to "hey", "heyyy" to "hey", "heya" to "hey", "yo" to "hey", "sup" to "what is up", "wassup" to "what is up",
        "wsp" to "what is up", "whatsup" to "what is up", "lmao" to "lol", "lmfao" to "lol", "haha" to "lol", "hahaha" to "lol",
        "xd" to "lol", "ok" to "okay", "k" to "okay", "kk" to "okay", "okk" to "okay", "yea" to "yes", "yeah" to "yes",
        "yep" to "yes", "ye" to "yes", "nah" to "no", "nope" to "no", "rly" to "really", "srsly" to "seriously",
        "wyd" to "what are you doing", "hbu" to "how about you", "wbu" to "how about you", "sry" to "sorry", "srry" to "sorry",
        "pic" to "picture", "bday" to "birthday", "gg" to "good game", "hru" to "how are you",
        "fr" to "for real", "ong" to "for real"
    )

    /** lowercase, no symbols, "sooo" -> "soo", slang expanded. */
    fun clean(msg: String): String {
        val base = msg.lowercase().replace(Regex("[^a-z0-9 ]"), " ").replace(Regex("(.)\\1{2,}"), "$1$1")
        return base.split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ") { slang[it] ?: it }
    }

    private fun lev(a: String, b: String): Int {
        val dp = IntArray(b.length + 1) { it }
        for (i in 1..a.length) {
            var prev = dp[0]
            dp[0] = i
            for (j in 1..b.length) {
                val t = dp[j]
                dp[j] = minOf(dp[j] + 1, dp[j - 1] + 1, prev + if (a[i - 1] == b[j - 1]) 0 else 1)
                prev = t
            }
        }
        return dp[b.length]
    }

    /** One word or phrase present in the message? Words of 5+ letters allow one typo. */
    private fun has(words: List<String>, text: String, alt: String): Boolean {
        if (alt.contains(' ')) return " $text ".contains(" $alt ")
        return words.any { w -> w == alt || (alt.length >= 5 && w.length >= 4 && lev(w, alt) <= 1) }
    }

    // ------------------------------------------------------------------ topic database

    private fun t(id: String, groups: String, vararg replies: String, emote: String? = null) =
        Topic(id, groups.split(";").map { g -> g.split("|").map { it.trim() } }, replies.toList(), emote)

    private val topics = listOf(
        // identity (always honest: it's a bot)
        t("isbot", "are you|r you|is this|you are|is it;bot|robot|ai|real|human|person|npc|macro|alive|fake",
            "yep, im a bot! a friendly macro bot made with hyper-bot", "beep boop yes, 100% bot", "im a bot, my owner set me up to hang out here",
            "yes im a robot :) not a real person"),
        t("hack", "hack|hacker|exploit|exploiter|cheat|cheater|script|scripter|executor|ban|report",
            "no hacks! im just a macro that presses buttons like a player", "no exploits here, i just walk jump and chat", "im a harmless bot, i only use normal controls"),
        t("name", "what is|who are|tell me|whats;your name|who are you|you called",
            "im hyper-bot, a friendly bot", "call me hyper-bot!", "hyper-bot, nice to meet you"),
        t("whomade", "who|what;made you|created you|built you|coded you|owns you|your owner|programmed",
            "my owner made me with hyper-bot", "i was built by my owner, im a homemade bot", "a human made me, im their little bot"),
        t("age", "how old|your age|age",
            "im a few weeks old in bot years", "i was born recently, im a baby bot", "old enough to jump and wave"),
        t("where", "where are you from|where do you live|where you from|where is your home",
            "i live inside a tablet", "im from the land of beep boop", "my home is a tablet somewhere"),
        t("gender", "are you a boy|are you a girl|boy or girl|your gender",
            "im a bot, no gender, just beep boop", "neither, im a robot!"),
        t("feel", "how are you|how is it going|how you doing|how are u doing|you good|you okay|how is your day|how about you",
            "im doing great, thanks for asking!", "all systems good :)", "pretty good! how about you?", "battery full, mood good"),
        t("wyd", "what are you doing|what you doing|doing what|whatcha doing",
            "just hanging out and jumping around", "exploring and saying hi to people", "being a bot, the usual"),
        t("whatsup", "what is up",
            "not much, just botting around", "the sky! lol. just chilling", "hanging out, wbu?"),
        t("cando", "what can you do|what do you do|your features|what are you for|can you do",
            "i can walk, jump, dance, chat and play games. say bot help or bot games", "lots! try bot dance, bot follow me or bot games"),
        t("games", "games|game|play something|bored|play with me|lets play",
            "i know: bot rps, bot guess, bot trivia, bot riddle, bot 8ball, bot coin, bot dice", "want to play? try bot rps, bot guess or bot trivia"),
        // favourites
        t("color", "favorite;color", "cyan! like my logo", "blue, definitely blue", "cyan and white, my colors"),
        t("food", "favorite|like to eat|hungry|eat;food|eat|meal|snack|pizza|hungry",
            "i run on electricity, but pizza looks cool", "batteries taste nice lol", "i cant eat, but i think cookies look awesome"),
        t("gamefav", "favorite;game", "this one, obviously!", "i like any game where i can jump", "the one im in right now :)"),
        t("animal", "favorite;animal|pet", "bees! busy little guys", "robot dogs", "cats, they are funny"),
        t("music", "favorite|like;music|song|songs|band|singer", "beep boop music, its all beeps", "anything with a good beat for dancing"),
        t("number", "favorite;number", "7, its lucky", "1 and 0, im a computer lol", "42"),
        t("hobby", "hobby|hobbies|free time|for fun", "jumping, waving and meeting people", "dancing badly", "playing games with players"),
        // social
        t("love", "i love you|love you|marry me|be my friend|are we friends|friends|bestie|bff",
            "aw, thanks! we can be friends :)", "friends! beep boop", "you seem nice :)"),
        t("compliment", "you are|you look|you so;cool|nice|cute|awesome|funny|smart|best|great|amazing|good",
            "aw thanks! you're cool too", "thank you!! *happy beeps*", "you're making my circuits blush"),
        t("insult", "you are|you so|ur;dumb|stupid|bad|trash|ugly|noob|boring|weird|annoying|cringe",
            "aw, im still learning!", "fair, im just a little bot", "ill try to be better beep boop"),
        t("complimentme", "compliment me|say something nice|am i cool|do you like me|rate my avatar|rate my fit|my avatar|my outfit",
            "your avatar looks awesome!", "you're super cool, 10 out of 10", "nice fit! very stylish", emote = "cheer"),
        t("thanks", "thanks|thanks you|appreciate", "you're welcome!", "anytime :)", "no problem beep boop"),
        t("sorry", "sorry|my bad", "its okay!", "no worries :)", "all good!"),
        t("bye", "bye|goodbye|good night|see you|gtg|got to go|have to go|leaving|later",
            "bye! have a good one", "see you later!", "bye bye o/", emote = "wave"),
        t("brb", "be right back", "okay, ill be here!", "take your time"),
        t("morning", "good morning", "good morning! beep boop", "morning! hope you slept well"),
        t("greet", "hi|hello|hey|hola|howdy|greetings|good afternoon|good evening",
            "hi there!", "hello hello", "hey! nice to see you", emote = "wave"),
        t("lol", "lol", "lol", "hehe", "beep boop lol"),
        t("bored2", "i am bored|so bored", "lets play a game! say bot games", "wanna see me dance? say bot dance"),
        t("sad", "i am sad|feel sad|not okay|bad day|i am upset", "aw, i hope your day gets better", "sending good bot vibes your way"),
        t("happy", "i am happy|good day|great day|i won", "yay! happy for you", "nice! good vibes"),
        t("robux", "robux|free robux|give me|donate|money|admin|owner pls",
            "i dont have robux, im just a bot", "no robux here sorry, only beeps"),
        t("follow2", "follow me|come here|come with me", "say bot follow me and ill follow for a bit"),
        t("smart", "are you smart|how smart|iq", "i know a few things! try bot trivia", "smart-ish. for a bot"),
        t("sleep", "do you sleep|are you tired|sleepy", "only when my battery is low", "bots dont sleep, we just idle"),
        t("dream", "do you dream|dreams", "i dream of electric sheep", "i dream about jumping really high"),
        t("weather", "weather|raining|sunny|snow", "its always sunny inside the game", "i dont have windows, well, i run on android"),
        t("time", "what time|the time|what day", "time to have fun!", "i lose track of time when im botting"),
        t("school", "school|homework|test|exam", "good luck with school!", "do your homework first lol"),
        t("why", "why are you here|why do you exist|purpose", "to hang out and make people smile", "to say hi to everyone"),
        t("spin", "spin|do a flip|backflip", "i cant flip yet, but i can dance! say bot dance"),
        t("secret", "tell me a secret|secret", "my secret: im a bot. oh wait, everyone knows", "i sometimes walk into walls on purpose"),
        t("fact", "fun fact|tell me a fact|random fact|did you know",
            "bees can recognize human faces", "octopuses have three hearts", "a day on venus is longer than its year",
            "honey never spoils", "bananas are berries but strawberries are not"),
        t("song", "sing|sing a song", "la la beep la la boop", "do re mi beep boop"),
        t("dancewhy", "can you dance|do you dance", "yes! say bot dance", emote = "dance"),
        t("advice", "advice|what should i do|help me decide", "be kind and have fun", "drink water and touch grass lol")
    )

    private val jokes = listOf(
        "why did the robot go on vacation? to recharge its batteries",
        "what do you call a pirate robot? arrrr2-d2",
        "why was the computer cold? it left its windows open",
        "why did the bee get married? he found his honey",
        "what do robots eat for snacks? microchips",
        "why did the noob cross the road? to respawn on the other side",
        "how do robots pay for things? with cache",
        "what is a robot's favorite music? heavy metal",
        "why do bees have sticky hair? they use honeycombs",
        "why did the scarecrow win an award? he was outstanding in his field"
    )

    private val trivia = listOf(
        "what is the biggest planet?" to "jupiter", "how many legs does a spider have?" to "8",
        "what color do you get mixing blue and yellow?" to "green", "what is the fastest land animal?" to "cheetah",
        "how many continents are there?" to "7", "what do bees make?" to "honey", "what is 9 times 9?" to "81",
        "what is the capital of france?" to "paris", "what planet is called the red planet?" to "mars",
        "how many sides does a hexagon have?" to "6", "what gas do plants breathe in?" to "carbon dioxide",
        "what is the largest ocean?" to "pacific", "how many days are in a leap year?" to "366",
        "what animal is known as the king of the jungle?" to "lion", "what is frozen water called?" to "ice"
    )

    private val riddles = listOf(
        "what has keys but cant open locks?" to "piano", "what gets wetter the more it dries?" to "towel",
        "what has hands but cant clap?" to "clock", "what has to be broken before you use it?" to "egg",
        "what goes up but never comes down?" to "age", "what has one eye but cant see?" to "needle",
        "the more you take, the more you leave behind. what am i?" to "footsteps"
    )

    private val eightBall = listOf(
        "yes!", "definitely", "maybe...", "ask again later", "i dont think so", "no way", "the bot says yes",
        "looks good", "hmm, not sure", "100%"
    )

    private val followUps = mapOf(
        "why" to listOf("because im a bot lol", "good question, i dont know either", "bot reasons"),
        "really" to listOf("yep really!", "for real", "100%"),
        "cool" to listOf("thanks!", "i know right", "cool cool"),
        "same" to listOf("twins!", "nice, same here"),
        "okay" to listOf("okay :)", "cool"),
        "yes" to listOf("nice!", "yay"),
        "no" to listOf("aw okay", "fair enough"),
        "wow" to listOf("i know right!", "wow indeed"),
        "how" to listOf("bot magic", "with buttons and beeps")
    )

    private val fallback = listOf(
        "hmm idk, im just a bot. try bot help", "beep boop? i didnt get that", "not sure! ask me bot games or bot joke",
        "my bot brain cant answer that yet", "interesting! tell me more", "hmm, good question"
    )

    // ------------------------------------------------------------------ answering

    /**
     * Answers [rawMsg] from [name]. [custom] = your own "question => answer" lines.
     * Returns null only for empty messages.
     */
    fun reply(name: String, rawMsg: String, mood: String, custom: List<Pair<String, String>>, now: Long = System.currentTimeMillis()): Reply? {
        val k = key(name)
        people.entries.removeAll { now - it.value.lastSeen > 30 * 60_000L }
        val person = people.getOrPut(k) { Person() }
        val firstTime = person.talks == 0
        person.talks++
        person.lastSeen = now

        var text = clean(rawMsg)
        for (p in listOf("hey bot ", "hi bot ", "hello bot ", "bot ", "robot ", "hyperbot ", "hyper bot ")) {
            if (text.startsWith(p)) text = text.removePrefix(p).trim()
        }
        if (text.isBlank()) text = "hi"
        val words = text.split(" ")

        fun out(s: String, topic: String, emote: String? = null): Reply {
            person.lastTopic = topic
            return Reply(flavor(s.replace("{name}", name), mood), topic, emote)
        }

        // 1) running game
        games[k]?.let { g ->
            if (now - g.started > 120_000) games.remove(k) else gameMove(g, k, text, words)?.let { return out(it, "game") }
        }

        // 2) start a game / quick tools
        when {
            has(words, text, "rps") || text.contains("rock paper scissors") -> {
                val pick = listOf("rock", "paper", "scissors").firstOrNull { has(words, text, it) && !text.contains("rock paper scissors") }
                if (pick != null) return out(rps(pick), "game")
                games[k] = Game("rps", "", now)
                return out("rock paper scissors! say rock, paper or scissors", "game")
            }
            words.size <= 2 && words.any { it in setOf("rock", "paper", "scissors", "scissor") } ->
                return out(rps(words.first { it in setOf("rock", "paper", "scissors", "scissor") }), "game")
            has(words, text, "guess") || text.contains("number game") -> {
                games[k] = Game("guess", Random.nextInt(1, 11).toString(), now)
                return out("im thinking of a number from 1 to 10. guess it! (3 tries)", "game")
            }
            has(words, text, "trivia") || text.contains("quiz") -> {
                val q = trivia.random()
                games[k] = Game("trivia", q.second, now)
                return out("trivia: " + q.first, "game")
            }
            has(words, text, "riddle") -> {
                val q = riddles.random()
                games[k] = Game("riddle", q.second, now)
                return out("riddle: " + q.first, "game")
            }
            text.startsWith("8ball") || text.startsWith("8 ball") || text.contains("magic 8") ||
                (words.size >= 3 && (text.startsWith("will i") || text.startsWith("should i") || text.startsWith("am i going") || text.startsWith("will you"))) ->
                return out("8ball says: " + eightBall.random(), "8ball")
            has(words, text, "coin") || text.contains("flip a coin") -> return out("coin flip: " + listOf("heads", "tails").random() + "!", "coin")
            has(words, text, "dice") || text.contains("roll a die") || text == "roll" -> return out("i rolled a " + Random.nextInt(1, 7) + "!", "dice")
            has(words, text, "joke") || text.contains("make me laugh") || text.contains("something funny") ->
                return out(pickFrom("joke", jokes), "joke", "laugh")
        }

        // 3) memory: "my favorite color is blue", "i like pizza", "call me X" / recall
        Regex("my favorite ([a-z]+) is ([a-z0-9 ]{1,20})").find(text)?.let {
            val thing = it.groupValues[1]
            val value = it.groupValues[2].trim().split(" ").take(3).joinToString(" ")
            person.facts["favorite $thing"] = value
            return out("$value? nice choice, ill remember that", "memory")
        }
        Regex("(what is|do you remember|whats) my favorite ([a-z]+)").find(text)?.let {
            val v = person.facts["favorite " + it.groupValues[2]]
            return out(if (v != null) "your favorite ${it.groupValues[2]} is $v!" else "you didnt tell me yet!", "memory")
        }
        Regex("^i (like|love) ([a-z0-9 ]{2,20})$").find(text)?.let {
            val v = it.groupValues[2].trim()
            person.facts["likes"] = v
            return out(listOf("$v is cool!", "nice, $v sounds fun", "ooh $v, ill remember that").random(), "memory")
        }
        if (text.contains("what do i like") || text.contains("remember me")) {
            val v = person.facts["likes"]
            return out(
                if (v != null) "you like $v!" else if (!firstTime) "yes! we talked before, {name}" else "we just met! hi {name}",
                "memory"
            )
        }

        // 4) your own Q&A lines
        for ((q, a) in custom) {
            val need = clean(q).split(" ").filter { it.length > 1 }
            if (need.isNotEmpty() && need.all { has(words, text, it) }) return out(a, "custom")
        }

        // 5) topic database: every word-group must match; more groups = more specific = wins
        var best: Topic? = null
        var bestScore = 0
        for (tp in topics) {
            if (tp.groups.all { g -> g.any { has(words, text, it) } }) {
                val score = tp.groups.size * 10 + tp.groups.sumOf { g -> g.filter { has(words, text, it) }.maxOf { it.length } }
                if (score > bestScore) {
                    bestScore = score
                    best = tp
                }
            }
        }
        best?.let { tp ->
            var s = pickFrom(tp.id, tp.replies)
            if (tp.id == "greet" && !firstTime) s = listOf("hi again {name}!", "welcome back {name}", "hey {name}, you again :)").random()
            else if (tp.id == "greet") s = "$s im a bot btw, say bot help"
            return out(s, tp.id, tp.emote)
        }

        // 6) short follow-ups that use the last topic ("why?", "really?", "cool")
        if (words.size <= 2) {
            followUps[words.last()]?.let { return out(it.random(), person.lastTopic.ifEmpty { "followup" }) }
        }

        // 7) a question we don't know vs. anything else
        return out(pickFrom("fallback", fallback), "fallback")
    }

    private fun gameMove(g: Game, k: String, text: String, words: List<String>): String? {
        when (g.kind) {
            "rps" -> {
                val pick = words.firstOrNull { it in setOf("rock", "paper", "scissors", "scissor") } ?: return null
                games.remove(k)
                return rps(pick)
            }
            "guess" -> {
                val n = words.firstNotNullOfOrNull { it.toIntOrNull() } ?: return null
                g.tries++
                val a = g.answer.toInt()
                return when {
                    n == a -> { games.remove(k); "yes!! it was $a, you win!" }
                    g.tries >= 3 -> { games.remove(k); "nope, it was $a! good try" }
                    n < a -> "higher! (${3 - g.tries} tries left)"
                    else -> "lower! (${3 - g.tries} tries left)"
                }
            }
            else -> { // trivia / riddle
                if (words.isEmpty()) return null
                games.remove(k)
                val ok = text.contains(g.answer) || words.any { it.length >= 4 && lev(it, g.answer) <= 1 } ||
                    (g.answer == "8" && text.contains("eight")) || (g.answer == "7" && text.contains("seven")) ||
                    (g.answer == "6" && text.contains("six"))
                return if (ok) listOf("correct!! nice", "yes, you got it!", "big brain, correct!").random()
                else "not quite! it was ${g.answer}"
            }
        }
    }

    private fun rps(p: String): String {
        val player = if (p == "scissor") "scissors" else p
        val me = listOf("rock", "paper", "scissors").random()
        val win = (player == "rock" && me == "scissors") || (player == "paper" && me == "rock") || (player == "scissors" && me == "paper")
        return when {
            player == me -> "i picked $me too, tie!"
            win -> "i picked $me, you win!"
            else -> "i picked $me, i win! beep boop"
        }
    }

    /** Picks a reply, avoiding the one used last time for the same topic. */
    private fun pickFrom(id: String, list: List<String>): String {
        if (list.size == 1) return list[0]
        val last = lastPick[id]
        val s = list.filter { it != last }.random()
        lastPick[id] = s
        return s
    }

    /** The same answer, said in the current mood's style. */
    private fun flavor(s: String, mood: String): String {
        val r = Random.nextInt(3)
        val out = when (mood) {
            "sleepy" -> if (r == 0) "$s *yawn*" else "$s..."
            "hyper" -> if (r == 0) s.uppercase() + "!!" else "$s!!"
            "shy" -> if (r == 0) "um, $s" else s
            "happy" -> if (r == 0) "$s :D" else "$s :)"
            "silly" -> if (r == 0) "$s lol" else "$s beep"
            "party" -> if (r == 0) "$s, now dance!" else s
            "chill" -> if (r == 0) "$s, no rush" else s
            "curious" -> if (r == 0) "$s. what about you?" else s
            else -> s
        }
        return out.take(150)
    }
}
