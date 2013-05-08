#!/bin/sh
JQUERY_VERSION="1.7.2"
STROPHE_VERSION="1.0.2"
BOOTSTRAP_VERSION="1.4.0"
ADHOC_COMMITISH="87bfedccdb91e2ff7cfb165e989e5259c155b513"

cd www_files/js

rm -f jquery-$JQUERY_VERSION.min.js
wget http://code.jquery.com/jquery-$JQUERY_VERSION.min.js

rm -f adhoc.js
wget -O adhoc.js "http://git.babelmonkeys.de/?p=adhocweb.git;a=blob_plain;f=js/adhoc.js;hb=$ADHOC_COMMITISH"

rm -f strophe.min.js
wget https://github.com/downloads/metajack/strophejs/strophejs-$STROPHE_VERSION.tar.gz && tar xzf strophejs-$STROPHE_VERSION.tar.gz strophejs-$STROPHE_VERSION/strophe.min.js --strip-components=1 && rm strophejs-$STROPHE_VERSION.tar.gz

cd ../css
rm -f bootstrap-$BOOTSTRAP_VERSION.min.css
wget http://twitter.github.com/bootstrap/$BOOTSTRAP_VERSION/bootstrap.min.css -O bootstrap-$BOOTSTRAP_VERSION.min.css
