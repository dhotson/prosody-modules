# Introduction #

This module provides a console over XMPP.
All the commands of the mod\_admin\_telnet module are available from an XMPP client.

Only the Prosody admins (see the _admins_ list in the Prosody configuration file) can use this console.

# Installation #

Copy the mod\_admin\_message directory into a directory Prosody will check for plugins (cf. [Installing modules](http://prosody.im/doc/installing_modules)) and set up a component:

```
 Component "console@example.com" "admin_message"
```

"console@example.com" is the identifier of the XMPP console.

# Compatibility #
|trunk|Works|
|:----|:----|
|0.9  |Works|
|<= 0.8|Not supported|