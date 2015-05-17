Community repository for non-core, unofficial and/or experimental plugins for [Prosody](http://prosody.im/).

If you are a developer and would like to host your Prosody module in this repository, or want to contribute to existing modules, simply introduce yourself and request commit access on our [mailing list](http://prosody.im/discuss).

## Notes for users ##
There are lots of fun and exciting modules to be found here, we know you'll like it. However please note that each module is in a different state of development. Some are proof-of-concept, others are quite stable and ready for production use. Be sure to read the wiki page of any module before installing it on your server.

We are working on methods to easily download and install modules from this repository. In the meantime most modules are either a single file and easy to install, or contain installation instructions on their wiki page. You can browse the files stored in this repository at http://prosody-modules.googlecode.com/hg/ .

### Prosody 0.8x compatibility ###
Due to a number of backwards-incompatible API changes in Prosody 0.9, prosody-modules for 0.8 are now maintained separately at http://0-8.prosody-modules.googlecode.com/hg/ .

## Guidelines for developers ##

  * Each module should be contained in a folder of its name (e.g. mod\_ping/mod\_ping.lua)
  * Each module should have a wiki page with a description, usage, configuration and todo sections (feel free to copy an existing one as a template)
  * Commit messages should begin with the name of the plugin they are for (e.g. "mod\_ping: Set correct namespace on pongs")

Instructions on cloning the repository are at http://code.google.com/p/prosody-modules/source/checkout - if you have commit access you will also see a link on that page to view your Google Code password (not the same as your Google account password) to push your changes.