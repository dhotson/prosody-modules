# Introduction #

This module provides a built-in web interface to view chatroom logs stored by [mod\_muc\_log](mod_muc_log.md).

# Installation #

Just copy the folder muc\_log\_http as it is, into the modules folder of your Prosody installation.

# Configuration Details #

You need to add muc\_log\_http to your global modules\_enabled, and the configuration options similarly must be put into your global (server-wide) options section:

```
	Component "conference.example.com" "muc"
	modules_enabled = {
		.....
		"muc_log";
		"muc_log_http";
		.....
	}

	muc_log_http = { -- These are the defaults
		show_join = true;
		show_presences = true;
		show_status = true;
		theme = "prosody";
		url_base = "muc_log";
	}
```

**show\_join** sets the default for showing joins or leaves.
**show\_status** sets the default for showing status changes.

The web interface would then be reachable at the address:
```
http://conference.example.com:5280/muc_log/
```


# TODO #
  * Log bans correctly
  * Quota ~ per day ?!
  * Testing testing :)