# Introduction #

This module adds the functionality of blacklist and whitelist for new server to server connections (federation).


# Details #

If the configuration is changed then you can use console to issue "config:reload()" and this plugin will automatically reload the black/whitelists.

You can either choose whitelist or blacklist functionality (both can't co-exist).

Note: If a host with existing connections is blacklisted then this module will not tear down existing connection since that was created when the connection agreement was valid. You will need to use "s2s:close" command on console to manually close those connections.

# Configuration #

First define whether you need blacklist or whitelist,

```
s2s_enable_blackwhitelist = "whitelist" -- enable whitelist. use blacklist to use blacklists
```

Now create populate an array of domains in those lists

For whitelist,

```
s2s_whitelist = { "abc.net", "gmail.com", "xyz.net" }
```

For blacklist,

```
s2s_blacklist = { "gmail.com", "xyz.com" }
```

You can change configuration at runtime but need to use console plugin to reload configuration via "config:reload" command.

# Compatibility #

| 0.9 | Doesn't work |
|:----|:-------------|
| 0.8 | Unknown      |
| 0.7 | tested to work with dialbacks |