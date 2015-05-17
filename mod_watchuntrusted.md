# Introduction #

Similar to mod\_watchregistrations, this module warns admins when an s2s connection fails due for encryption or trust reasons.

The certificate shows the SHA1 hash, so it can easily be used together with mod\_s2s\_auth\_fingerprint.

# Configuration #

```
modules_enabled = {
	-- other modules --
	"watchuntrusted",

}

untrusted_fail_watchers = { "admin@example.lit" }
untrusted_fail_notification = "Establishing a secure connection from $from_host to $to_host failed. Certificate hash: $sha1. $errors"
```

| **Option**                          | **Default** | **Description** |
|:------------------------------------|:------------|:----------------|
| untrusted\_fail\_watchers           | All admins      | The users to send the message to |
| untrusted\_fail\_notification         | "Establishing a secure connection from $from\_host to $to\_host failed. Certificate hash: $sha1. $errors"      | The message to send, $from\_host, $to\_host, $sha1 and $errors are replaced  |


# Compatibility #

|trunk|Works|
|:----|:----|