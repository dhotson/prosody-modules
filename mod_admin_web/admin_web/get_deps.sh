#!/bin/sh
cd www_files/js
wget http://code.jquery.com/jquery-1.4.4.min.js
git clone git://github.com/metajack/strophejs.git strophejs
cd strophejs
make strophe.js && cp strophe.js ../strophe.js
cd ..
rm -rf strophejs
