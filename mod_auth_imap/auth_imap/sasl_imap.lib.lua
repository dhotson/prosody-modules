-- Dovecot authentication backend for Prosody
--
-- Copyright (C) 2011 Kim Alvefur
--

local log = require "util.logger".init("sasl_imap");

local setmetatable = setmetatable;

local s_match, s_gmatch = string.match, string.gmatch
local t_concat = table.concat;
local m_random = math.random;
local tostring, tonumber = tostring, tonumber;

local socket = require "socket"
-- TODO -- local ssl = require "ssl"
local base64 = require "util.encodings".base64;
local b64, unb64 = base64.encode, base64.decode;

local _M = {};

local method = {};
method.__index = method;

-- For extracting the username.
local mitm = {
	PLAIN = function(message)
		return s_match(message, "^[^%z]*%z([^%z]+)%z[^%z]+");
	end,
	["SCRAM-SHA-1"] = function(message)
		return s_match(message, "^[^,]+,[^,]*,n=([^,]*)");
	end,
	["DIGEST-MD5"] = function(message)
		return s_match(message, "username=\"([^\"]*)\"");
	end,
}

local function connect(host, port, ssl)
	port = tonumber(port) or (ssl and 993 or 143);
	log("debug", "connect() to %s:%s:%d", ssl and "ssl" or "tcp", host, tonumber(port));
	local conn = socket.tcp();

	-- Create a connection to imap socket
	log("debug", "connecting to imap at '%s:%d'", host, port);
	local ok, err = conn:connect(host, port);
	conn:settimeout(10);
	if not ok then
		log("error", "error connecting to imap at '%s:%d'. error was '%s'. check permissions", host, port, err);
		return false;
	end

	-- Parse IMAP handshake
	local done = false;
	local supported_mechs = {};
	local line = conn:receive("*l");
	log("debug", "imap handshake: '%s'", line);
	if not line then
		return false;
	end
	local caps = line:match("^%*%s+OK%s+(%b[])");
	if caps then
		caps = caps:sub(2,-2);
		for cap in caps:gmatch("%S+") do
			log("debug", "Capability: %s", cap);
			local mech = cap:match("AUTH=(.*)");
			if mech then
				log("debug", "Supported SASL mechanism: %s", mech);
				supported_mechs[mech] = mitm[mech] and true or nil; 
			end
		end
	end

	return conn, supported_mechs;
end

-- create a new SASL object which can be used to authenticate clients
function _M.new(realm, service_name, host, port, ssl)
	log("debug", "new(%q, %q, %q, %d)", realm or "", service_name or "", host or "", port or 0);
	local sasl_i = {
		realm = realm,
		service_name = service_name,
		_host = host,
		_port = port,
		_ssl = ssl
	};

	local conn, mechs = connect(host, port, ssl);
	if not conn then
		return nil, "Socket connection failure";
	end
	sasl_i.conn, sasl_i.mechs = conn, mechs;
	return setmetatable(sasl_i, method);
end

-- get a fresh clone with the same realm and service name
function method:clean_clone()
	if self.conn then
		self.conn:close();
		self.conn = nil;
	end
	log("debug", "method:clean_clone()");
	return _M.new(self.realm, self.service_name, self._host, self._port)
end

-- get a list of possible SASL mechanisms to use
function method:mechanisms()
	log("debug", "method:mechanisms()");
	return self.mechs;
end

-- select a mechanism to use
function method:select(mechanism)
	log("debug", "method:select(%q)", mechanism);
	if not self.selected and self.mechs[mechanism] then
		self.tag = tostring({}):match("0x(%x*)$");
		self.selected = mechanism;
		local selectmsg = t_concat({ self.tag, "AUTHENTICATE", mechanism }, " ");
		log("debug", "Sending %d bytes: %q", #selectmsg, selectmsg);
		local ok, err = self.conn:send(selectmsg.."\n");
		if not ok then
			log("error", "Could not write to socket: %s", err);
			return "failure", "internal-server-error", err
		end
		local line, err = self.conn:receive("*l");
		if not line then
			log("error", "Could not read from socket: %s", err);
			return "failure", "internal-server-error", err
		end
		log("debug", "Received %d bytes: %q", #line, line);
		return line:match("^+")
	end
end

-- feed new messages to process into the library
function method:process(message)
	local username = mitm[self.selected](message);
	if username then self.username = username; end
	log("debug", "method:process(%d bytes)", #message);
	local ok, err = self.conn:send(b64(message).."\n");
	if not ok then
		log("error", "Could not write to socket: %s", err);
		return "failure", "internal-server-error", err
	end
	log("debug", "Sent %d bytes to socket", ok);
	local line, err = self.conn:receive("*l");
	if not line then
		log("error", "Could not read from socket: %s", err);
		return "failure", "internal-server-error", err
	end
	log("debug", "Received %d bytes from socket: %s", #line, line);

	if line:match("^%+") and #line > 2 then
		local data = line:sub(3);
		data = data and unb64(data);
		return "challenge", unb64(data);
	elseif line:sub(1, #self.tag) == self.tag then
		local ok, rest = line:sub(#self.tag+1):match("(%w+)%s+(.*)");
		ok = ok:lower();
		log("debug", "%s: %s", ok, rest);
		if ok == "ok" then
			return "success"
		elseif ok == "no" then
			return "failure", "not-authorized", rest;
		end
	elseif line:match("^%* BYE") then
		local err = line:match("BYE%s*(.*)");
		return "failure", "not-authorized", err;
	end
end

return _M;
