# Introduction #

Some people find it preferable to close server-to-server connections after they have been silent for a while.


# Configuration #
...is trivial. The default timeout is 300 seconds (5 minutes). To change this simply put in the config:

```
   s2s_idle_timeout = 60 -- or any other number of seconds
```

# Compatibility #
| 0.6 | Works |
|:----|:------|
| 0.7 | Works |