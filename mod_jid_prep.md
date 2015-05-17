# Introduction #

This is a plugin that implements the JID prep protocol defined in http://xmpp.org/extensions/inbox/jidprep.html

# Details #

JID prep requests can happen over XMPP using the protocol defined in the document linked above, or alternatively over HTTP. Simply request:

```
http://server:5280/jid_prep/USER@HOST
```

The result will be the stringprepped JID, or a 400 Bad Request if the given JID is invalid.

# Compatibility #

| 0.9 | Works |
|:----|:------|