# Introduction #

[mod\_muc\_log](mod_muc_log.md) provided logging of chatrooms running on the server to Prosody's data store. This module gives access to this data using the 0.10+ stanza archive API, allowing legacy log data to be used with [mod\_mam\_muc](mod_mam_muc.md) and [mod\_http\_muc\_log](mod_http_muc_log.md).

# Details #

Replace mod\_muc\_log (and mod\_muc\_log\_http) in your config with

```
Component "conference.example.org" "muc"
	modules_enabled = {
		-- "muc_log"; -- functionality replaced by mod_mam_muc + mod_storage_muc_log
		"mam_muc"; -- Does logging to storage backend configured below

		-- "muc_log_http"; -- Replaced by the mod_http_muc_log
		"http_muc_log";
	}
	storage = {
		muc_log = "muc_log";
	}
```

# Compatibility #

Requires Prosody 0.10 or above.