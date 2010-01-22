local st = require "util.stanza";

local xmlns_cmd = "http://jabber.org/protocol/commands";

local _M = {};

function _cmdtag(desc, status, sessionid, action)
	local cmd = st.stanza("command", { xmlns = xmlns_cmd, node = desc.node, status = status });
	if sessionid then cmd.attr.sessionid = sessionid; end
	if action then cmd.attr.action = action; end

	return cmd;
end

function _M.new(name, node, handler, permission)
	return { name = name, node = node, handler = handler, cmdtag = _cmdtag, permission = (permission or "user") };
end

function _M.handle_cmd(command, origin, stanza)
	local sessionid = stanza.tags[1].attr.sessionid or nil;
	local dataIn = {};
	dataIn.to = stanza.attr.to;
	dataIn.from = stanza.attr.from;
	dataIn.action = stanza.tags[1].attr.action or nil;
	dataIn.form = stanza.tags[1]:child_with_ns("jabber:x:data");

	local data, sessid = command:handler(dataIn, sessionid);
	local stanza = st.reply(stanza);
	if data.status == "completed" then
		cmdtag = command:cmdtag("completed", sessid);
	elseif data.status == "canceled" then
		cmdtag = command:cmdtag("canceled", sessid);
	elseif data.status == "error" then
		stanza = st.error_reply(stanza, data.error.type, data.error.condition, data.error.message);
		cmdtag = command:cmdtag("canceled", sessid);
	else 
		cmdtag = command:cmdtag("executing", sessid);
	end

	for name, content in pairs(data) do
		if name == "info" then
			cmdtag:tag("note", {type="info"}):text(content);
		elseif name == "error" then
			cmdtag:tag("note", {type="error"}):text(content.message);
		elseif name == "form" then
			cmdtag:add_child(data.form:form());
		elseif name == "other" then
			cmdtag:add_child(content);
		end
	end
	stanza:add_child(cmdtag);
	origin.send(stanza);

	return true;
end

return _M;
