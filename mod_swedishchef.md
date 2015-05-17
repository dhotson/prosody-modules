# Introduction #

This module does some conversions on message bodys passed through it causing
them to look like our beloved swedish chef had typed them.


# Details #

To load this on a MUC component do

```
Component "funconference.example.com" "muc"
    modules_enabled = { "swedishchef" }
    swedishchef_trigger = "!chef"; -- optional, converts only when the message starts with "!chef"
```

In theory this also works for whole servers, but that is untested and not recommended ;)

# Compatibility #
|0.6|Works|
|:--|:----|
|0.5|Works|

# Todo #

  * Possibly add xhtml-im (XEP-0071) support