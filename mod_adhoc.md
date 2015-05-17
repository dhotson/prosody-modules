# Introduction #

implementation of [XEP-0050: Ad-Hoc Commands](http://xmpp.org/extensions/xep-0050.html), which allows clients to execute commands on the Prosody server. This plugin adds no commands itself, see the other `mod_adhoc_*` plugins for those.

This module along with the other adhoc modules in prosody-modules are included in Prosody as of 0.8, making this plugin unnecessary for users of this version and later.

# Details #

Will offer any adhoc command registered via 'module:add\_item("adhoc", ....)'.



# Usage #

First copy (or symlink) the directory "adhoc" which contains mod\_adhoc to your plugins directory.
Load mod\_adhoc and then any module which provides an adhoc command, such as
mod\_adhoc\_cmd\_ping.

If you want to build your own adhoc command, just register your adhoc command module with
module:add\_item and a descriptor for your command.

A descriptor can be created like this:
```
local adhoc_new = module:require "adhoc".new;
local descriptor = adhoc_new("Name", "node", handler);
module:add_item ("adhoc", descriptor)
```

A handler gets 2 parameters. A data table and a state.

The data table has 4 fields:
|to|The to attribute of the stanza to be handled|
|:-|:-------------------------------------------|
|from|The from attribute of the stanza to be handled|
|action|The action to be performed as specified in the stanza to be handled|
|form|If the to be handled stanza contains a form this will contain the form element|

The handler should return two items. A data table and a state.
The state will be saved and passed to the handler on invocation for any adhoc stanza with the same sessionid. If a session has ended the state returned should be nil.

The returned table can have the following fields:
|**Name**|**Explanation**|**Required?**|
|:-------|:--------------|:------------|
|status  |Status of the command (One of: "completed", "canceled", "error")|yes          |
|error   |A table with the fields "type", "condition" and "message"|when status is "error"|
|info    |Informational text for display to the user|no           |
|warn    |A warning for the user|no           |
|actions |The actions avaiable to the client|no           |
|form    |A dataform to be filled out by the user|no           |
|result  |A dataform of type result to be presented to the user|no           |
|other   |Any other XML to be included in the response to the user|no           |

For a simple module and details have a look at mod\_adhoc\_cmd\_ping.

# Compatibility #
|0.6|Most commands work|
|:--|:-----------------|
|0.7|Works             |
|0.8|Included in Prosody|