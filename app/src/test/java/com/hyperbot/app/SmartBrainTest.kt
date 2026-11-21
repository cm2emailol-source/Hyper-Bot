package com.hyperbot.app

import org.junit.Assert.assertTrue
import org.junit.Test

/** Prints a sample conversation (visible in the GitHub build log) and checks a few must-haves. */
class SmartBrainTest {
    @Test
    fun transcript() {
        val b = SmartBrain()
        val custom = listOf("who is your owner" to "my owner is a cool person who builds bots")
        val msgs = listOf(
            "Alex" to "bot hi", "Alex" to "bot hru", "Alex" to "bot r u a real person??", "Alex" to "bot are u hacking",
            "Alex" to "bot whats ur fav colour", "Alex" to "bot why", "Alex" to "bot my favorite color is green",
            "Alex" to "bot whats my favorite color", "Alex" to "bot tell me a joke", "Alex" to "bot rps", "Alex" to "rock",
            "Alex" to "bot guess", "Alex" to "5", "Alex" to "bot 3", "Alex" to "bot 8", "Alex" to "bot trivia", "Alex" to "jupiter",
            "Alex" to "bot will i win the lottery", "Alex" to "bot flip a coin", "Alex" to "bot who is your owner",
            "Sam" to "hello bot", "Sam" to "bot free robux pls", "Sam" to "bot ur so cool", "Sam" to "bot asdfgh qwerty",
            "Sam" to "bot what can u do", "Sam" to "bot whats ur name", "Sam" to "bot whats up", "Alex" to "bot hi",
            "Sam" to "bot i love pizza", "Sam" to "bot what do i like", "Sam" to "bot bye"
        )
        var isBotOk = false
        for ((n, m) in msgs) {
            val r = b.reply(n, m, "normal", custom)!!
            println("BRAIN  $n: $m  ->  [${r.topic}] ${r.text}")
            if (m.contains("real person")) isBotOk = r.topic == "isbot"
        }
        println("BRAIN  sleepy: " + b.reply("Kim", "bot how are you", "sleepy", custom)!!.text)
        println("BRAIN  hyper: " + b.reply("Kim", "bot joke", "hyper", custom)!!.text)
        assertTrue("must admit it's a bot", isBotOk)
    }
}
