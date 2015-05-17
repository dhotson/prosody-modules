# Introduction #

There are various reasons to prefer web registration instead of "in-band" account registration over XMPP. For example the lack of CAPTCHA support in clients and servers.

# Details #

mod\_register\_web has Prosody serve a web page where users can sign up for an account. It implements reCaptcha to prevent automated sign-ups (from bots, etc.).

# Configuration #

The module is served on Prosody's default HTTP ports at the path `/register_web`. More details on configuring HTTP modules in Prosody can be found in our [HTTP documentation](http://prosody.im/doc/http).

To configure the CAPTCHA you need to supply a 'captcha\_options' option:

```
    captcha_options = {
      recaptcha_private_key = "12345";
      recaptcha_public_key = "78901";
    }
```

The keys for reCaptcha are available in your reCaptcha account, visit [recaptcha.net](http://recaptcha.net/) for more info.

If no reCaptcha options are set, a simple built in captcha is used.

# Compatibility #
| 0.9 | Works |
|:----|:------|
| 0.8 | Doesn't work |

# Todo #

Lots. The module is very basic at the moment. In particular I would like to see:

  * Customisation (CSS and/or HTML)
  * Different CAPTCHA implementation support
  * Collection of additional data, such as email address
  * The module kept simple!