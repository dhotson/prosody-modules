# Introduction #

This module implements [HTTP Strict Transport Security](https://tools.ietf.org/html/rfc6797)
and responds to all non-HTTPS requests with a `301 Moved Permanently` redirect to the HTTPS
equivalent of the path.

# Configuration #

Add the module to the `modules_enabled` list and optionally configure the specific header sent.

```
	modules_enabled = {
		...
			"strict_https";
	}
	hsts_header = "max-age=31556952"
```

# Compatibility #
|trunk|Works|
|:----|:----|
|0.9  |Works|
|0.8  |Doesn't work|