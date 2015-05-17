# Introduction #

By default XMPP is as reliable as your network is. Unfortunately in some cases that is not very reliable - in some network conditions disconnects can be frequent and message loss can occur.

To overcome this, XMPP has an optional extension (XEP-0198: Stream Management) which, when supported by both the client and server, can allow a client to resume a disconnected session, and prevent message loss.

# Details #

When using XEP-0198 both the client and the server keep a queue of the most recently sent stanzas - this is cleared when the other end acknowledges they have received the stanzas. If the client disconnects, instead of marking the user offline the server pretends the client is still online for a short (configurable) period of time. If the client reconnects within this period, any stanzas in the queue that the client did not receive are re-sent.

If the client fails to reconnect before the timeout then it is marked offline as normal, and any stanzas in the queue are returned to the sender as a "recipient-unavailable" error.

# Configuration #

| **Option** | **Default** | **Description** |
|:-----------|:------------|:----------------|
| smacks\_hibernation\_time | 300 (5 minutes) | The number of seconds a disconnected session should stay alive for (to allow reconnect) |

# Compatibility #
|0.9|Works|
|:--|:----|
|0.8|Works, use version [7693724881b3](http://prosody-modules.googlecode.com/hg-history/7693724881b3f3cdafa35763f00dd040d02313bf/mod_smacks/mod_smacks.lua)|

# Clients #
Clients that support XEP-0198:
  * Gajim
  * Swift (but not resumption, as of version 2.0 and alphas of 3.0)
  * Psi (in an unreleased branch)
  * Yaxim
