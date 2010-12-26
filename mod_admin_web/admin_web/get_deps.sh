#!/bin/sh
cd www_files/js
test -e jquery-1.4.4.min.js || wget http://code.jquery.com/jquery-1.4.4.min.js
test -e adhoc.js || wget http://cgit.babelmonkeys.de/cgit.cgi/adhocweb/plain/js/adhoc.js
test -e strophe.js || (git clone git://github.com/metajack/strophejs.git strophejs && \
	cd strophejs && make strophe.js && cp strophe.js ../strophe.js && \
	cd .. && rm -rf strophejs)
