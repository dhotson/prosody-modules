# Introduction #
This is a very simple demo module showing how to serve a BOSH-using web app from prosody.

# Installation #

[Install](http://prosody.im/doc/installing_modules) and [enable](http://prosody.im/doc/modules_enabled) the module just like any other.  Note the included HTML file in the www\_files directory, this directory needs to be in the same place as the module.

You then need to download Candy and unpack it into the www\_files directory, for example with curl:

```
curl -L http://github.com/candy-chat/candy/tarball/master | tar xzfv - --strip-components=1
```

After the module has been loaded, Candy will by default be reachable from `http://example.com:5280/candy/`

# Compatibility #
|trunk|Works|
|:----|:----|
|0.9  |Works|