# Introduction #

This plugin encodes XMPP as JSON. This is an implementation of [XEP-0295: JSON Encodings for XMPP](http://xmpp.org/extensions/xep-0295.html).

Simply loading this module makes Prosody accept JSON on C2S streams (legacy XML clients are still supported).

For BOSH, it requires mod\_bosh be loaded, and JSON should be directed at the `/jsonstreams` HTTP path.

JSON for S2S isn't supported due to the lack of a discovery mechanism, so we have left that disabled to stay compatible with legacy XML servers.

# Configuration #
Just add `"json_streams"` in your config's global `modules_enabled` list, for example:

```
modules_enabled = {
	...
	"json_streams";
}
```

# Strophe.js plugin #
We also developed a [JSON streams plugin](http://prosody-modules.googlecode.com/hg/mod_json_streams/strophe.jsonstreams.js) for the popular [strophe.js](http://code.stanziq.com/strophe) library.

Just include it like this after including the strophe library, and your strophe-based client will be speaking JSON:
```
<script type="text/javascript" src="strophe.jsonstreams.js"></script>
```
Be sure to set the HTTP path to `/jsonstreams`. No other changes are required.

# Compatibility #
|0.8|Works|
|:--|:----|
|trunk|Works|

# Quirks #
  * This plugin does not currently work with Prosody's [port multiplexing](http://prosody.im/doc/port_multiplexing) feature