#!/bin/sh
JQUERY_VERSION="1.7.1"
STROPHE_VERSION="1.0.2"
cd www_files/js
test -e jquery-$JQUERY_VERSION.min.js || wget http://code.jquery.com/jquery-$JQUERY_VERSION.min.js
test -e adhoc.js || wget -O adhoc.js "http://cgit.babelmonkeys.de/cgit.cgi/adhocweb/plain/js/adhoc.js?id=e55b23864a9911c15d930b43ed9afe1df5943bf7"
test -e strophe.min.js || (wget https://github.com/downloads/metajack/strophejs/strophejs-$STROPHE_VERSION.tar.gz && tar xzf strophejs-$STROPHE_VERSION.tar.gz strophejs-$STROPHE_VERSION/strophe.min.js --strip-components=1 && rm strophejs-$STROPHE_VERSION.tar.gz)
