# Introduction #

Sometimes it's useful to have different interfaces to access XMPP.

This is example of sending message using HTTP POST to XMPP. For sure we need user auth information.

# Example usage #

**curl http://example.com:5280/msg/user -u me@example.com:mypassword -H "Content-Type: text/plain" -d "Server@host has just crashed!"**

This would send a message to user@example.com from me@example.com

# Details #

By Kim Alvefur <zash@zash.se>

Some code borrowed from mod\_webpresence

