# Introduction #

This module implements PKI-style client certificate authentication.
You will therefore need your own Certificate Authority.
How to set that up is beyond the current scope of this document.

# Configuration #

```

authentication = "ccert"
certificate_match = "xmppaddr" -- or "email"

c2s_ssl = {
	capath = "/path/to/dir/with/your/ca"
}

```

`capath` should be pointed to a directory with your own CA certificate.  You will need to run `c_rehash` in it.

# Compatibility #

|trunk|Works|
|:----|:----|
|0.9 and earlier|Doesn't work|
|0.10 and later|Works|