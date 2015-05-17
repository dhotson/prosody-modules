# Introduction #

This module allows you to control the maximum rate of 'events' in a MUC room. This makes it useful to prevent room floods (whether malicious or accidental).

# Details #

This module limits the following events:

  * Room joins
  * Nick changes
  * Status changes
  * Messages (including private messages)

The limit is for the room as a whole, not individual occupants in the room. Users with an affiliation (members, admins and owners) are not limited.

# Configuration #

Add the module to the MUC host (not the global modules\_enabled):

```
    Component "conference.example.com" "muc"
        modules_enabled = { "muc_limits" }
```

You can define (globally or per-MUC component) the following options:

| **Name** | **Default value** | **Description** |
|:---------|:------------------|:----------------|
| muc\_event\_rate | 0.5               | The maximum number of events per second. |
| muc\_burst\_factor | 6                 | Allow temporary bursts of this multiple. |

For more understanding of how these values are used, see the algorithm section below.

# Algorithm #

A certain number of events are allowed per second, given by muc\_event\_rate. An event rate of 1 allows one event per second, and event rate of 3 allows three events per second, and 0.5 allows one event every two seconds, and so on.

Obviously MUC conversations are not exactly steady streams of events. Sometimes multiple people will talk at once. This is handled by the muc\_burst\_factor option.

A burst factor of 2 will allow 2 times as many events at once, for 2 seconds, before throttling will be triggered. A factor of 5, 5 times as many events for 5 seconds.

When the limit is reached, an error response will be generated telling the user the MUC is overactive, and asking them to try again.

# Compatibility #
| Trunk | Works |
|:------|:------|
| 0.8   | Doesn't work`*` |

`*` This module can be made to work in 0.8 (and _maybe_ previous versions) of Prosody by copying the new [util.throttle](http://hg.prosody.im/trunk/raw-file/fc8a22936b3c/util/throttle.lua) into your Prosody source directory (into the util/ subdirectory).