# Introduction #

This module provides a built-in web interface to view chatroom logs stored by [mod\_mam\_muc](mod_mam_muc.md).

# Installation #

Just copy the folder muc\_log\_http as it is, into the modules folder of your Prosody installation.

# Configuration Details #

You need to add muc\_log\_http to your global modules\_enabled, and the configuration options similarly must be put into your global (server-wide) options section:

```
	Component "conference.example.com" "muc"
	modules_enabled = {
		.....
		"mam_muc";
		"http_muc_log";
		.....
	}
	storage = {
		muc_log = "sql2"; -- for example
	}
```

The web interface would then be reachable at the address:
```
http://conference.example.com:5280/muc_log/
```

See [the page about Prosodys HTTP server](http://prosody.im/doc/http) for info about the address.

# Compatibility #

Requires Prosody 0.10 or above and a storage backend with support for stanza archives.