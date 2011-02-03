#!/bin/sh
cd www_files/js
test -e jquery-1.4.4.min.js || wget http://code.jquery.com/jquery-1.4.4.min.js
test -e adhoc.js || wget http://cgit.babelmonkeys.de/cgit.cgi/adhocweb/plain/js/adhoc.js
test -e strophe.js || (wget --no-check-certificate https://github.com/metajack/strophejs/tarball/release-1.0.1 && \
	tar xzf *.tar.gz && rm *.tar.gz && cd metajack-strophejs* && make strophe.js && cp strophe.js ../strophe.js && \
	cd .. && rm -rf metajack-strophejs*)

