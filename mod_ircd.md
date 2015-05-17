**NOTE: Consider this module currently more of a fun experiment than a serious project for use in production. Note the 'alpha' tag and have fun!**

# Introduction #

Whether you like it or not, XMPP is the future, but that pesky IRC just won't go away :)

With this module you can set up a special host on your server to allow connections from IRC clients and bots. They are able to join XMPP chatrooms on a specified conference server.

# Usage #
In your config file put something similar to the following:

```
Component "irc2muc.example.com" "ircd"
    conference_server = "conference.example.com" -- required
    listener_port = 7000
```

If you don't want your IRC users to have connectivity outside your server then there is no need for the hostnames you specify to be valid DNS entries.

# Warning #

The plugin stability, and/or serving compatibility with most of the IRC clients is yet to be determined.

# Install #

This release requires the [Verse client library](http://code.matthewwild.co.uk/verse/) as dependancy and [Squish](http://code.matthewwild.co.uk/squish/) to meld it with the plugin.

Instructions (temporarily changed):
  * Clone the Squish repo and/or download the latest tip from it (in that case you'll have to decompress the tip zip/tarball)
  * In your Squish directory type make install
  * Back into your mod\_ircd directory call squish with --verse=./verse/verse.lua
  * Move the mod\_ircd.lua file to your prosody's plugins directory

# Compatibility #
|0.8|Works|
|:--|:----|
|0.7|Uncertain|
|0.6|Doesn't work|

# Todo #
  * Authentication
  * SSL
  * Many improvements to handling of IRC and XMPP