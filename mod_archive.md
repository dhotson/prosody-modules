
---

This page is held here for reference only. mod\_archive is no longer supported.

Similar modules:

  * [mod\_mam](mod_mam.md)
  * [mod\_mam\_sql](mod_mam_sql.md)
  * [mod\_log\_messages](http://prosody.im/files/mod_log_messages.lua) (mainly useful as a template for people making their own logging module)

**Note:** If you are an administrator looking for a module just for centrally logging messages passing to/from users on your server, this probably isn't the module you are looking for (mod\_archive is for user-managed archives). We'd really like to hear about your requirements to make a module more tailored to this kind of use-case though (especially how/where you would like the messages stored)... drop us an email at developers@prosody.im to let us know.


---


# Introduction #

Currently many XMPP clients save the messages locally and it's not convenient or even possible to retrieve the historical messages, especially when one switches the clients a lot.

# Details #

This module keeps an archive of incoming and outgoing messages for each user on the server, and allows the user to query and manage this archive using the XMPP extension described in [XEP-0136: Message Archiving](http://xmpp.org/extensions/xep-0136.html).

**Note:** If you are an administrator looking for a module just for centrally logging messages passing to/from users on your server, this probably isn't the module you are looking for (mod\_archive is for user-managed archives). We'd really like to hear about your requirements to make a module more tailored to this kind of use-case though (especially how/where you would like the messages stored)... drop us an email at developers@prosody.im to let us know.

# Usage #

First copy the module to the prosody plugins directory.

Then add "archive" to your modules\_enabled list:
```
    modules_enabled = {
                    -- ...
                    "privacy",
                    "archive",
                    -- ...
```

# Configuration #
| **Name** | **Description** | **Type** | **Default value** |
|:---------|:----------------|:---------|:------------------|
| default\_max | the maximum number of items to return when requesting collection list or archived messages | integer  | 100               |
| force\_archiving | archive every message automatically, and do NOT consider the preferences | boolean  | false             |
| auto\_archiving\_enabled | applied when no any preferences available | boolean  | true              |


# Compatibility #
| 0.7.0 | Works |
|:------|:------|

# TODO #
  * consider '`exactmatch`' attribute when do JID matching.
  * return a `<feature-not-implemented/>` error when the client set the value of the '`save`' attribute to '`stream`'.