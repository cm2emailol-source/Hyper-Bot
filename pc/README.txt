Hyper-Bot PC v1.0
=================
A friendly, clearly-disclosed hangout bot for Roblox on Windows. Same Smart Brain, moods and
rules as Hyper-Bot for Android.

Input-only: it presses keys, moves the mouse and reads the screen (Windows' built-in OCR).
No injection, no memory reading, no modified Roblox, no internet. Chat is read in memory only.

USE IT ON AN ALT ACCOUNT ONLY, and never while your main account is playing or macroing.

Start
  Double-click "Start Hyper-Bot.bat" (uses the included AutoHotkey64.exe).
  Or, if you have AutoHotkey v2 installed, double-click HyperBot.ahk.

Setup (once)
  1. Open Roblox on your alt and join a game. Keep the chat window visible.
  2. Control tab > "Calibrate chat area": click the top-left, then the bottom-right corner of the chat messages.
  3. Chat & Brain tab: type the bot's display name, Save.
  4. "Chat test" (it should type in chat) and "Listen test" (it should list the chat lines it read).
  5. For Shift Lock mode: turn on "Shift Lock Switch" in Roblox's settings.

Hotkeys
  F6 show/hide window   F8 Auto   F9 Listen   F10 STOP everything   F11 record a move
  Ctrl+F8 follow nearest player   Ctrl+F10 stop following

The bot only acts while the Roblox window is the active window. Click any other window and it pauses
and lets go of all keys.

Built-in rules
  - Announces it's a bot on start and every 10 minutes; always says "yes" when asked if it's a bot.
  - Chat limits: max 5 answers a minute, 10 s per person, random lines at most every 30 s.
  - Follow: only the player who asked ("bot follow me"), or one you pick, for max 60 s.
    Follows you start: 10 min cooldown and max 3 per player per day; it tells them, and if they say
    stop it stops and won't follow them for an hour (follow_log.ini keeps only names + times).

Files
  settings.ini      your settings
  moves\*.txt       your recorded moves
  follow_log.ini    follow cooldowns

Credits: OCR library by Descolada (MIT, lib\OCR_LICENSE.txt). AutoHotkey v2 (GPL v2, AutoHotkey_license.txt).
