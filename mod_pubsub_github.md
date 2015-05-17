# Introduction #

This module accepts Github web hooks and publishes them to a local pubsub component for XMPP clients to subscribe to.

Entries are pushed as Atom payloads.

# Configuration #

Load the module on a pubsub component:

```
Component "pubsub.example.com" "pubsub"
    modules_enabled = { "pubsub_github" }
```

The module also takes the following config options:

| **Name** | **Default** | **Description** |
|:---------|:------------|:----------------|
| github\_node | "github"    | The pubsub node to publish commits on. |

The URL for Github to post to would be either:

  * http://pubsub.example.com:5280/pubsub_github
  * https://pubsub.example.com:5281/pubsub_github

If your HTTP host doesn't match the pubsub component's address, you will need to inform Prosody. For more info see Prosody's [HTTP server documentation](https://prosody.im/doc/http#virtual_hosts).

# Compatibility #
| 0.9 | Works |
|:----|:------|