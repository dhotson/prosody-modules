
/* jsonstreams plugin
**
** This plugin upgrades Strophe to support XEP-0295: JSON Encodings for XMPP
**
*/

Strophe.addConnectionPlugin('jsonstreams', {
    init: function (conn) {

        var parseXMLString = function(xmlStr) {
			var xmlDoc = null;
			if (window.ActiveXObject) {
				xmlDoc = new ActiveXObject("Microsoft.XMLDOM"); 
				xmlDoc.async=false;
				xmlDoc.loadXML(xmlStr);
			} else {
				var parser = new DOMParser();
				xmlDoc = parser.parseFromString(xmlStr, "text/xml");
			}
			return xmlDoc;
        }

        // replace Strophe.Request._newXHR with new jsonstreams version
        // if JSON is detected
        if (window.JSON) {
        	var _newXHR = Strophe.Request.prototype._newXHR;
            Strophe.Request.prototype._newXHR = function () {
            	var _xhr = _newXHR.apply(this, arguments);
                var xhr = {
                	readyState: 0,
                	responseText: null,
                	responseXML: null,
                	status: null,
                	open: function(a, b, c) { return _xhr.open(a, b, c) },
                	abort: function() { _xhr.abort(); },
                	send: function(data) {
                		data = JSON.stringify({"s":data});
                		return _xhr.send(data);
                	}
                };
                var req = this;
                xhr.onreadystatechange = this.func.bind(null, this);
                _xhr.onreadystatechange = function() {
                	xhr.readyState = _xhr.readyState;
                	if (xhr.readyState != 4) {
                		xhr.status = 0;
                		xhr.responseText = "";
                		xhr.responseXML = null;
                	} else {
	                	xhr.status = _xhr.status;
	               		xhr.responseText = _xhr.responseText;
	               		xhr.responseXML = _xhr.responseXML;
	                	if (_xhr.responseText && !(_xhr.responseXML
	                			&& _xhr.responseXML.documentElement
	                			&& _xhr.responseXML.documentElement.tagName != "parsererror")) {
	                		var data = JSON.parse(_xhr.responseText);
	                		if (data && data.s) {
	                			xhr.responseText = data.s;
	                			xhr.responseXML = parseXMLString(data.s);
	                		}
	                	}
	                }
                	if ("function" == typeof xhr.onreadystatechange) { xhr.onreadystatechange(req); }
                }
                return xhr;
            };
        } else {
            Strophe.error("jsonstreams plugin loaded, but JSON not found." +
                          "  Falling back to native XHR implementation.");
        }
    }
});
