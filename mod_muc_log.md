# Introduction #

This module logs the conversation of chatrooms running on the server to Prosody's data store. To view them you will need a module such as [mod\_muc\_log\_http](mod_muc_log_http.md).

# Details #

mod\_muc\_log must be loaded individually for the components that need it. Assuming you have a MUC component already running on conference.example.org then you can add muc\_log to it like so:

```
Component "conference.example.org" "muc"
   modules_enabled = {
      "muc_log";
   }
```

Logging is not enabled by default.  In 0.9+ logging can be enabled per room in the room config form.

To enable logging in older versions, or to enable logging by default for all rooms, set

```
muc_log_by_default = true -- Log all rooms by default
```


# Compatibility #
| 0.6 | Works |
|:----|:------|
| 0.7 | Works |
| 0.8 | Works |
| 0.9 | Works |

**Note** that per-room configuration only works in 0.9+.