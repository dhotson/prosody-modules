# Introduction #

Pastebins are used very often in IM, especially in chat rooms. You have a long log or command output which you need to send to someone over IM, and don't want to fill their message window with it. Put it on a pastebin site, and give them the URL instead, simple.

Not for everyone... no matter how hard you try, people will be unaware, or not care. They may also be too lazy to visit a pastebin. This is where mod\_pastebin comes in!

# Details #

When someone posts to a room a "large" (the actual limit is configurable) message, Prosody will intercept the message and convert it to a URL pointing to a built-in pastebin server. The URLs are randomly generated, so they can be considered for most purposes to be private, and cannot be discovered by people who are not in the room.

# Usage #

To set up mod\_pastebin for MUC rooms it **must** be explicitly loaded, as in the example below - it won't work when loaded globally, as that will only load it onto normal virtual hosts.

For example:
```
Component "conference.example.com" "muc"
    modules_enabled = { "pastebin" }
```

Pastes will be available by default at `http://<your-prosody>:5280/pastebin/` by default. This can be changed with `pastebin_ports` (see below), or you can forward another external URL from your web server to Prosody, use `pastebin_url` to set that URL.

# Configuration #
|pastebin\_ports|List of ports to run the HTTP server on, same format as mod\_httpserver's http\_ports|
|:--------------|:------------------------------------------------------------------------------------|
|pastebin\_threshold|Maximum length (in characters) of a message that is allowed to skip the pastebin. (default 500 characters)|
|pastebin\_line\_threshold|The maximum number of lines a message may have before it is sent to the pastebin. (default 4 lines)|
|pastebin\_trigger|A string of characters (e.g. "!paste ") which if detected at the start of a message, always sends the message to the pastebin, regardless of length. (default: not set)|
|pastebin\_url  |Base URL to display for pastebin links, must end with / and redirect to Prosody's built-in HTTP server|
|pastebin\_expire\_after|Number of hours after which to expire (remove) a paste, defaults to 24. Set to 0 to store pastes permanently on disk.|

# Compatibility #
|0.9|Works, but pastebin\_ports does not exist anymore, see the 0.9.0 release notes|
|:--|:-----------------------------------------------------------------------------|
|0.8|Works                                                                         |
|0.7|Works                                                                         |
|0.6|Works                                                                         |

# Todo #

  * Maximum paste length
  * Web interface to submit pastes?