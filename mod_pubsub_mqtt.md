# Introduction #

[MQTT](http://mqtt.org/) is a lightweight binary pubsub protocol suited to embedded devices. This module provides a way for MQTT clients to connect to Prosody and publish or subscribe to local pubsub nodes.

# Details #

MQTT has the concept of 'topics' (similar to XMPP's pubsub 'nodes'). mod\_pubsub\_mqtt maps pubsub nodes to MQTT topics of the form `HOST/NODE', e.g. `pubsub.example.org/mynode`.

## Limitations ##
The current implementation is quite basic, and in particular:

  * Authentication is not supported
  * SSL/TLS is not supported
  * Only QoS level 0 is supported

## Payloads ##
XMPP payloads are always XML, but MQTT does not define a payload format. Therefore mod\_pubsub\_mqtt will attempt to convert data of certain recognised payload types. Currently supported:

  * JSON (see [XEP-0335](http://xmpp.org/extensions/xep-0335.html) for the format)
  * Plain UTF-8 text (wrapped inside `<data xmlns="https://prosody.im/protocol/mqtt"/>`)

All other XMPP payload types are sent to the client directly as XML. Data published by MQTT clients is currently never translated, and always treated as UTF-8 text.

# Configuration #

There is no special configuration for this module. Simply load it on your pubsub host like so:

```
Component "pubsub.example.org" "pubsub"
    modules_enabled = { "pubsub_mqtt" }
```

You may also configure which port(s) mod\_pubsub\_mqtt listens on using Prosody's standard config directives, such as `mqtt_ports`. Network settings **must** be specified in the global section of the config file, not under any particular pubsub component. The default port is 1883 (MQTT's standard port number).

# Compatibility #
| trunk | Works |
|:------|:------|
| 0.9   | Works |
| 0.8   | Doesn't work |