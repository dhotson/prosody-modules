local secure_interfaces = module:get_option_set("secure_interfaces", { "127.0.0.1" });

module:hook("stream-features", function (event)
	local session = event.origin;
	if session.type ~= "c2s_unauthed" then return; end
	local socket = session.conn:socket();
	if not socket.getsockname then return; end
	local localip = socket:getsockname();
	if secure_interfaces:contains(localip) then
		module:log("debug", "Marking session from %s as secure", session.ip or "[?]");
		session.secure = true;
	end
end, 2500);
