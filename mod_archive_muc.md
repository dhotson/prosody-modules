# Introduction #

Implementation of [XEP-xxxx: Message Archive Management](http://matthewwild.co.uk/uploads/message-archive-management.html). Like [mod\_archive](mod_archive.md) but much simpler.

# Details #

The server will have the ability to archive muc messages passing through.

# Usage #

First copy the module to the prosody plugins directory.

Then add "archive\_muc" to your modules\_enabled list:
```
    modules_enabled = {
                    -- ...
                    "privacy",
                    "archive_muc",
                    -- ...
```

# Configuration #

| **Name** | **Description** | **Type** | **Default value** |
|:---------|:----------------|:---------|:------------------|
| auto\_muc\_archiving\_enabled | applied when no any preferences available | boolean  | true              |

# Compatibility #
| 0.7.0 | Works |
|:------|:------|

# TODO #
Test



