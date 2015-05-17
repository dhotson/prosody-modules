# Introduction #

Implementation of [XEP-0136: Message Archiving](http://xmpp.org/extensions/xep-0136.html) for [mod\_mam](mod_mam.md).


# Details #

See [mod\_mam](mod_mam.md) for details.

# Usage #

First configure mod\_mam as specified in it's [wiki](mod_mam.md). Make sure it uses sql2 storage backend.

Then add "mam\_archive" to your modules\_enabled list:
```
    modules_enabled = {
        -- ...
        "mam_archive",
        -- ...
    }
```

# Configuration #

Because of the fact that [XEP-0136](http://xmpp.org/extensions/xep-0136.html) defines a 'conversation' concept not present in [XEP-0313](http://xmpp.org/extensions/xep-0313.html), we have to assume some periods of chat history as 'conversations'.

Conversation interval defaults to one day, to provide for a convenient usage.

```
archive_conversation_interval = 86400; -- defined in seconds. One day by default
```

That is the only reason SQL database is required as well.

# Compatibility #
| 0.10 | Works |
|:-----|:------|
| 0.9  | Does not work |

| PostgreSQL | Tested |
|:-----------|:-------|
| MySQL      | Not tested |
| SQLite     | Tested |