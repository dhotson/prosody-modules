# Introduction #

This module provides a basic web administration interface.
It currently gives you access to Ad-Hoc commands on any virtual host or component that you are set as an administrator for in the Prosody config file. It also provides a live list of all S2S and C2S connections.

# Installation #

  1. Copy the admin\_web directory into a directory Prosody will check for plugins. (cf. [Installing modules](http://prosody.im/doc/installing_modules))
  1. Execute the contained get\_deps.sh script from within the admin\_web directory. (Requires wget, tar, and a basic shell)

# Configuration Details #

"admin\_web" needs to be added to the modules\_enabled table of the host you want to load this module on.

By default the interface will then be reachable under `http://example.com:5280/admin`, or `https://example.com:5281/admin`.

The module will automatically enable two other modules if they aren't already: mod\_bosh (used to connect to the server from the web), and mod\_admin\_adhoc (which provides admin commands over XMPP).

```
VirtualHost "example.com"
   modules_enabled = {
       .....
       "admin_web";
       .....
   }
```

# Compatibility #
|trunk|Works|
|:----|:----|
|0.9  |Works|
|<= 0.8|Not supported|