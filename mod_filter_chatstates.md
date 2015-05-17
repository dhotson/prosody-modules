# Introduction #

Some mobile XMPP client developers consider
[Chat State Notifications](http://xmpp.org/extensions/xep-0085.html) to be
a waste of power and bandwidth, especially when the user is not actively
looking at their device.  This module will filter them out while the
session is considered inactive.  It depends on `mod_csi` for deciding
when to begin and end filtering.

# Configuration #

There is no configuration for this module, just add it to modules\_enabled as normal.

# Compatibility #
|0.9|Works|
|:--|:----|
