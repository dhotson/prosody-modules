var BOSH_SERVICE = '/http-bind/';
var show_log = false;

Strophe.addNamespace('C2SPUBSUB', 'http://prosody.im/streams/c2s');
Strophe.addNamespace('S2SPUBSUB', 'http://prosody.im/streams/s2s');
Strophe.addNamespace('PUBSUB', 'http://jabber.org/protocol/pubsub');
Strophe.addNamespace('CAPS', 'http://jabber.org/protocol/caps');

var localJID = null;
var connection   = null;

var pubsubHost = '%PUBSUBHOST%';

function log(msg) {
    var entry = $('<div></div>').append(document.createTextNode(msg));
    $('#log').append(entry);
}

function rawInput(data) {
    log('RECV: ' + data);
}

function rawOutput(data) {
    log('SENT: ' + data);
}

function _cbNewS2S(e) {
    var items, entry, retract, id, jid;
    items = e.getElementsByTagName('item');
    for (i = 0; i < items.length; i++) {
        id = items[i].attributes['id'].value;
        jid = items[i].getElementsByTagName('session')[0].attributes['jid'].value;

        entry = $('<li id="' + id + '">' + jid + '</li>');
        if (e.getElementsByTagName('encrypted')[0]) {
            entry.append('<img src="images/encrypted.png" title="encrypted" alt=" (encrypted)" />');
        }
        if (e.getElementsByTagName('compressed')[0]) {
            entry.append('<img src="images/compressed.png" title="compressed" alt=" (compressed)" />');
        }

        if (items[i].getElementsByTagName('out')[0]) {
            entry.appendTo('#s2sout');
        } else {
            entry.appendTo('#s2sin');
        }
    }
    retract = e.getElementsByTagName('retract')[0];
    if (retract) {
        id = retract.attributes['id'].value;
        $('#' + id).remove();
    }
    return true;
}

function _cbNewC2S(e) {
    var items, entry, retract, id, jid;
    items = e.getElementsByTagName('item');
    for (i = 0; i < items.length; i++) {
        id = items[i].attributes['id'].value;
        jid = items[i].getElementsByTagName('session')[0].attributes['jid'].value;
        entry = $('<li id="' + id + '">' + jid + '</li>');
        if (e.getElementsByTagName('encrypted')[0]) {
            entry.append('<img src="images/encrypted.png" title="encrypted" alt=" (encrypted)" />');
        }
        if (e.getElementsByTagName('compressed')[0]) {
            entry.append('<img src="images/compressed.png" title="compressed" alt=" (compressed)" />');
        }
        entry.appendTo('#c2s');
    }
    retract = e.getElementsByTagName('retract')[0];
    if (retract) {
        id = retract.attributes['id'].value;
        $('#' + id).remove();
    }
    return true;
}

function _cbPubSub(e) {
    var node = e.getElementsByTagName('items')[0].attributes['node'].value;
    if (node == Strophe.NS.C2SPUBSUB) {
        _cbNewC2S(e);
    } else if (node == Strophe.NS.S2SPUBSUB) {
        _cbNewS2S(e);
    }

    return true;
}

function onConnect(status) {
    if (status == Strophe.Status.CONNECTING) {
        log('Strophe is connecting.');
    } else if (status == Strophe.Status.CONNFAIL) {
        log('Strophe failed to connect.');
        showConnect();
    } else if (status == Strophe.Status.DISCONNECTING) {
        log('Strophe is disconnecting.');
    } else if (status == Strophe.Status.DISCONNECTED) {
        log('Strophe is disconnected.');
        showConnect();
    } else if (status == Strophe.Status.AUTHFAIL) {
        log('Authentication failed');
        if (connection) {
            connection.disconnect();
        }
    } else if (status == Strophe.Status.CONNECTED) {
        log('Strophe is connected.');
        showDisconnect();
	Adhoc.checkFeatures('#adhoc', connection.domain);
        connection.addHandler(_cbPubSub, Strophe.NS.PUBSUB + '#event', 'message');
        connection.send($iq({to: pubsubHost, type: 'set', id: connection.getUniqueId()}).c('pubsub', {xmlns: Strophe.NS.PUBSUB})
                .c('subscribe', {node: Strophe.NS.C2SPUBSUB, jid: connection.jid}));
        connection.send($iq({to: pubsubHost, type: 'set', id: connection.getUniqueId()}).c('pubsub', {xmlns: Strophe.NS.PUBSUB})
                .c('subscribe', {node: Strophe.NS.S2SPUBSUB, jid: connection.jid}));
        connection.sendIQ($iq({to: pubsubHost, type: 'get', id: connection.getUniqueId()}).c('pubsub', {xmlns: Strophe.NS.PUBSUB})
                .c('items', {node: Strophe.NS.S2SPUBSUB}), _cbNewS2S);
        connection.sendIQ($iq({to: pubsubHost, type: 'get', id: connection.getUniqueId()}).c('pubsub', {xmlns: Strophe.NS.PUBSUB})
                .c('items', {node: Strophe.NS.C2SPUBSUB}), _cbNewC2S);

    }
}

function showConnect() {
    var jid = $('#jid');
    var pass = $('#pass');
    var button = $('#connect').get(0);

    button.value = 'connect';
    pass.show();
    jid.show();
    $('#menu').hide();
    $('#adhoc').hide();
    $('#s2sList').hide();
    $('#c2sList').hide();
    $('#cred label').show();
    $('#cred br').show();
    $('#s2sin').empty();
    $('#s2sout').empty();
    $('#c2s').empty();
}

function showDisconnect() {
    var jid = $('#jid');
    var pass = $('#pass');
    var button = $('#connect').get(0);

    button.value = 'disconnect';
    pass.hide();
    jid.hide();
    $('#menu').show();
    $('#adhoc').show();
    $('#cred label').hide();
    $('#cred br').hide();
}

$(document).ready(function () {
    connection = new Strophe.Connection(BOSH_SERVICE);
    if (show_log) {
        $('#log_container').show();
        connection.rawInput = rawInput;
        connection.rawOutput = rawOutput;
    }

    $("#log_toggle").click(function () {
        $("#log").toggle();
    });

    $('#cred').bind('submit', function (event) {
        var button = $('#connect').get(0);
        var jid = $('#jid');
        var pass = $('#pass');
        localJID = jid.get(0).value;

        if (button.value == 'connect') {
            $('#log').empty();
            connection.connect(localJID,
               pass.get(0).value,
               onConnect);
        } else {
            connection.disconnect();
        }
        event.preventDefault();
    });

    $('#adhocMenu').click(function () {
	$('#s2sList').slideUp();
	$('#c2sList').slideUp();
	$('#adhoc').slideDown();
        event.preventDefault();
    });

    $('#serverMenu').click(function () {
	$('#adhoc').slideUp();
	$('#c2sList').slideUp();
	$('#s2sList').slideDown();
        event.preventDefault();
    });

    $('#clientMenu').click(function () {
	$('#adhoc').slideUp();
	$('#s2sList').slideUp();
	$('#c2sList').slideDown();
        event.preventDefault();
    });

});

window.onunload = window.onbeforeunload = function() {
    if (connection) {
        connection.disconnect();
    }
}
