package.preload['verse'] = (function (...)
package.preload['util.encodings'] = (function (...)
local function not_impl()
	error("Function not implemented");
end

local mime = require "mime";

module "encodings"

stringprep = {};
base64 = { encode = mime.b64, decode = not_impl }; --mime.unb64 is buggy with \0

return _M;
 end)
package.preload['util.hashes'] = (function (...)
local sha1 = require "util.sha1";

return { sha1 = sha1.sha1 };
 end)
package.preload['util.logger'] = (function (...)
local select, tostring = select, tostring;
local io_write = function(...) return io.stderr:write(...) end;
module "logger"

local function format(format, ...)
	local n, maxn = 0, #arg;
	return (format:gsub("%%(.)", function (c) if c ~= "%" and n <= maxn then n = n + 1; return tostring(arg[n]); end end));
end

local function format(format, ...)
	local n, maxn = 0, select('#', ...);
	local arg = { ... };
	return (format:gsub("%%(.)", function (c) if n <= maxn then n = n + 1; return tostring(arg[n]); end end));
end

function init(name)
	return function (level, message, ...)
		io_write(level, "\t", format(message, ...), "\n");
	end
end

return _M;
 end)
package.preload['util.sha1'] = (function (...)
-------------------------------------------------
---      *** SHA-1 algorithm for Lua ***      ---
-------------------------------------------------
--- Author:  Martin Huesser                   ---
--- Date:    2008-06-16                       ---
--- License: You may use this code in your    ---
---          projects as long as this header  ---
---          stays intact.                    ---
-------------------------------------------------

local strlen  = string.len
local strchar = string.char
local strbyte = string.byte
local strsub  = string.sub
local floor   = math.floor
local bit     = require "bit"
local bnot    = bit.bnot
local band    = bit.band
local bor     = bit.bor
local bxor    = bit.bxor
local shl     = bit.lshift
local shr     = bit.rshift
local h0, h1, h2, h3, h4

-------------------------------------------------

local function LeftRotate(val, nr)
	return shl(val, nr) + shr(val, 32 - nr)
end

-------------------------------------------------

local function ToHex(num)
	local i, d
	local str = ""
	for i = 1, 8 do
		d = band(num, 15)
		if (d < 10) then
			str = strchar(d + 48) .. str
		else
			str = strchar(d + 87) .. str
		end
		num = floor(num / 16)
	end
	return str
end

-------------------------------------------------

local function PreProcess(str)
	local bitlen, i
	local str2 = ""
	bitlen = strlen(str) * 8
	str = str .. strchar(128)
	i = 56 - band(strlen(str), 63)
	if (i < 0) then
		i = i + 64
	end
	for i = 1, i do
		str = str .. strchar(0)
	end
	for i = 1, 8 do
		str2 = strchar(band(bitlen, 255)) .. str2
		bitlen = floor(bitlen / 256)
	end
	return str .. str2
end

-------------------------------------------------

local function MainLoop(str)
	local a, b, c, d, e, f, k, t
	local i, j
	local w = {}
	while (str ~= "") do
		for i = 0, 15 do
			w[i] = 0
			for j = 1, 4 do
				w[i] = w[i] * 256 + strbyte(str, i * 4 + j)
			end
		end
		for i = 16, 79 do
			w[i] = LeftRotate(bxor(bxor(w[i - 3], w[i - 8]), bxor(w[i - 14], w[i - 16])), 1)
		end
		a = h0
		b = h1
		c = h2
		d = h3
		e = h4
		for i = 0, 79 do
			if (i < 20) then
				f = bor(band(b, c), band(bnot(b), d))
				k = 1518500249
			elseif (i < 40) then
				f = bxor(bxor(b, c), d)
				k = 1859775393
			elseif (i < 60) then
				f = bor(bor(band(b, c), band(b, d)), band(c, d))
				k = 2400959708
			else
				f = bxor(bxor(b, c), d)
				k = 3395469782
			end
			t = LeftRotate(a, 5) + f + e + k + w[i]	
			e = d
			d = c
			c = LeftRotate(b, 30)
			b = a
			a = t
		end
		h0 = band(h0 + a, 4294967295)
		h1 = band(h1 + b, 4294967295)
		h2 = band(h2 + c, 4294967295)
		h3 = band(h3 + d, 4294967295)
		h4 = band(h4 + e, 4294967295)
		str = strsub(str, 65)
	end
end

-------------------------------------------------

local function sha1(str, hexres)
	str = PreProcess(str)
	h0  = 1732584193
	h1  = 4023233417
	h2  = 2562383102
	h3  = 0271733878
	h4  = 3285377520
	MainLoop(str)
	local hex = ToHex(h0)..ToHex(h1)..ToHex(h2)
	            ..ToHex(h3)..ToHex(h4);
	if hexres then
		return  hex;
	else
		return (hex:gsub("..", function (byte)
			return string.char(tonumber(byte, 16));
		end));
	end
end

_G.sha1 = {sha1 = sha1};
return _G.sha1;

-------------------------------------------------
-------------------------------------------------
-------------------------------------------------
 end)
package.preload['lib.adhoc'] = (function (...)
-- Copyright (C) 2009-2010 Florian Zeitz
--
-- This file is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local st, uuid = require "util.stanza", require "util.uuid";

local xmlns_cmd = "http://jabber.org/protocol/commands";

local states = {}

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
	local sessionid = stanza.tags[1].attr.sessionid or uuid.generate();
	local dataIn = {};
	dataIn.to = stanza.attr.to;
	dataIn.from = stanza.attr.from;
	dataIn.action = stanza.tags[1].attr.action or "execute";
	dataIn.form = stanza.tags[1]:child_with_ns("jabber:x:data");

	local data, state = command:handler(dataIn, states[sessionid]);
	states[sessionid] = state;
	local stanza = st.reply(stanza);
	if data.status == "completed" then
		states[sessionid] = nil;
		cmdtag = command:cmdtag("completed", sessionid);
	elseif data.status == "canceled" then
		states[sessionid] = nil;
		cmdtag = command:cmdtag("canceled", sessionid);
	elseif data.status == "error" then
		states[sessionid] = nil;
		stanza = st.error_reply(stanza, data.error.type, data.error.condition, data.error.message);
		origin.send(stanza);
		return true;
	else
		cmdtag = command:cmdtag("executing", sessionid);
	end

	for name, content in pairs(data) do
		if name == "info" then
			cmdtag:tag("note", {type="info"}):text(content):up();
		elseif name == "warn" then
			cmdtag:tag("note", {type="warn"}):text(content):up();
		elseif name == "error" then
			cmdtag:tag("note", {type="error"}):text(content.message):up();
		elseif name =="actions" then
			local actions = st.stanza("actions");
			for _, action in ipairs(content) do
				if (action == "prev") or (action == "next") or (action == "complete") then
					actions:tag(action):up();
				else
					module:log("error", 'Command "'..command.name..
						'" at node "'..command.node..'" provided an invalid action "'..action..'"');
				end
			end
			cmdtag:add_child(actions);
		elseif name == "form" then
			cmdtag:add_child((content.layout or content):form(content.values));
		elseif name == "result" then
			cmdtag:add_child((content.layout or content):form(content.values, "result"));
		elseif name == "other" then
			cmdtag:add_child(content);
		end
	end
	stanza:add_child(cmdtag);
	origin.send(stanza);

	return true;
end

return _M;
 end)
package.preload['util.stanza'] = (function (...)
-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--


local t_insert      =  table.insert;
local t_concat      =  table.concat;
local t_remove      =  table.remove;
local t_concat      =  table.concat;
local s_format      = string.format;
local s_match       =  string.match;
local tostring      =      tostring;
local setmetatable  =  setmetatable;
local getmetatable  =  getmetatable;
local pairs         =         pairs;
local ipairs        =        ipairs;
local type          =          type;
local next          =          next;
local print         =         print;
local unpack        =        unpack;
local s_gsub        =   string.gsub;
local s_char        =   string.char;
local s_find        =   string.find;
local os            =            os;

local do_pretty_printing = not os.getenv("WINDIR");
local getstyle, getstring;
if do_pretty_printing then
	local ok, termcolours = pcall(require, "util.termcolours");
	if ok then
		getstyle, getstring = termcolours.getstyle, termcolours.getstring;
	else
		do_pretty_printing = nil;
	end
end

local xmlns_stanzas = "urn:ietf:params:xml:ns:xmpp-stanzas";

module "stanza"

stanza_mt = { __type = "stanza" };
stanza_mt.__index = stanza_mt;
local stanza_mt = stanza_mt;

function stanza(name, attr)
	local stanza = { name = name, attr = attr or {}, tags = {} };
	return setmetatable(stanza, stanza_mt);
end
local stanza = stanza;

function stanza_mt:query(xmlns)
	return self:tag("query", { xmlns = xmlns });
end

function stanza_mt:body(text, attr)
	return self:tag("body", attr):text(text);
end

function stanza_mt:tag(name, attrs)
	local s = stanza(name, attrs);
	local last_add = self.last_add;
	if not last_add then last_add = {}; self.last_add = last_add; end
	(last_add[#last_add] or self):add_direct_child(s);
	t_insert(last_add, s);
	return self;
end

function stanza_mt:text(text)
	local last_add = self.last_add;
	(last_add and last_add[#last_add] or self):add_direct_child(text);
	return self;
end

function stanza_mt:up()
	local last_add = self.last_add;
	if last_add then t_remove(last_add); end
	return self;
end

function stanza_mt:reset()
	self.last_add = nil;
	return self;
end

function stanza_mt:add_direct_child(child)
	if type(child) == "table" then
		t_insert(self.tags, child);
	end
	t_insert(self, child);
end

function stanza_mt:add_child(child)
	local last_add = self.last_add;
	(last_add and last_add[#last_add] or self):add_direct_child(child);
	return self;
end

function stanza_mt:get_child(name, xmlns)
	for _, child in ipairs(self.tags) do
		if (not name or child.name == name)
			and ((not xmlns and self.attr.xmlns == child.attr.xmlns)
				or child.attr.xmlns == xmlns) then
			
			return child;
		end
	end
end

function stanza_mt:get_child_text(name, xmlns)
	local tag = self:get_child(name, xmlns);
	if tag then
		return tag:get_text();
	end
	return nil;
end

function stanza_mt:child_with_name(name)
	for _, child in ipairs(self.tags) do
		if child.name == name then return child; end
	end
end

function stanza_mt:child_with_ns(ns)
	for _, child in ipairs(self.tags) do
		if child.attr.xmlns == ns then return child; end
	end
end

function stanza_mt:children()
	local i = 0;
	return function (a)
			i = i + 1
			return a[i];
		end, self, i;
end

function stanza_mt:childtags(name, xmlns)
	xmlns = xmlns or self.attr.xmlns;
	local tags = self.tags;
	local start_i, max_i = 1, #tags;
	return function ()
		for i = start_i, max_i do
			local v = tags[i];
			if (not name or v.name == name)
			and (not xmlns or xmlns == v.attr.xmlns) then
				start_i = i+1;
				return v;
			end
		end
	end;
end

function stanza_mt:maptags(callback)
	local tags, curr_tag = self.tags, 1;
	local n_children, n_tags = #self, #tags;
	
	local i = 1;
	while curr_tag <= n_tags do
		if self[i] == tags[curr_tag] then
			local ret = callback(self[i]);
			if ret == nil then
				t_remove(self, i);
				t_remove(tags, curr_tag);
				n_children = n_children - 1;
				n_tags = n_tags - 1;
			else
				self[i] = ret;
				tags[i] = ret;
			end
			i = i + 1;
			curr_tag = curr_tag + 1;
		end
	end
	return self;
end

local xml_escape
do
	local escape_table = { ["'"] = "&apos;", ["\""] = "&quot;", ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;" };
	function xml_escape(str) return (s_gsub(str, "['&<>\"]", escape_table)); end
	_M.xml_escape = xml_escape;
end

local function _dostring(t, buf, self, xml_escape, parentns)
	local nsid = 0;
	local name = t.name
	t_insert(buf, "<"..name);
	for k, v in pairs(t.attr) do
		if s_find(k, "\1", 1, true) then
			local ns, attrk = s_match(k, "^([^\1]*)\1?(.*)$");
			nsid = nsid + 1;
			t_insert(buf, " xmlns:ns"..nsid.."='"..xml_escape(ns).."' ".."ns"..nsid..":"..attrk.."='"..xml_escape(v).."'");
		elseif not(k == "xmlns" and v == parentns) then
			t_insert(buf, " "..k.."='"..xml_escape(v).."'");
		end
	end
	local len = #t;
	if len == 0 then
		t_insert(buf, "/>");
	else
		t_insert(buf, ">");
		for n=1,len do
			local child = t[n];
			if child.name then
				self(child, buf, self, xml_escape, t.attr.xmlns);
			else
				t_insert(buf, xml_escape(child));
			end
		end
		t_insert(buf, "</"..name..">");
	end
end
function stanza_mt.__tostring(t)
	local buf = {};
	_dostring(t, buf, _dostring, xml_escape, nil);
	return t_concat(buf);
end

function stanza_mt.top_tag(t)
	local attr_string = "";
	if t.attr then
		for k, v in pairs(t.attr) do if type(k) == "string" then attr_string = attr_string .. s_format(" %s='%s'", k, xml_escape(tostring(v))); end end
	end
	return s_format("<%s%s>", t.name, attr_string);
end

function stanza_mt.get_text(t)
	if #t.tags == 0 then
		return t_concat(t);
	end
end

function stanza_mt.get_error(stanza)
	local type, condition, text;
	
	local error_tag = stanza:get_child("error");
	if not error_tag then
		return nil, nil, nil;
	end
	type = error_tag.attr.type;
	
	for child in error_tag:childtags() do
		if child.attr.xmlns == xmlns_stanzas then
			if not text and child.name == "text" then
				text = child:get_text();
			elseif not condition then
				condition = child.name;
			end
			if condition and text then
				break;
			end
		end
	end
	return type, condition or "undefined-condition", text;
end

function stanza_mt.__add(s1, s2)
	return s1:add_direct_child(s2);
end


do
	local id = 0;
	function new_id()
		id = id + 1;
		return "lx"..id;
	end
end

function preserialize(stanza)
	local s = { name = stanza.name, attr = stanza.attr };
	for _, child in ipairs(stanza) do
		if type(child) == "table" then
			t_insert(s, preserialize(child));
		else
			t_insert(s, child);
		end
	end
	return s;
end

function deserialize(stanza)
	-- Set metatable
	if stanza then
		local attr = stanza.attr;
		for i=1,#attr do attr[i] = nil; end
		local attrx = {};
		for att in pairs(attr) do
			if s_find(att, "|", 1, true) and not s_find(att, "\1", 1, true) then
				local ns,na = s_match(att, "^([^|]+)|(.+)$");
				attrx[ns.."\1"..na] = attr[att];
				attr[att] = nil;
			end
		end
		for a,v in pairs(attrx) do
			attr[a] = v;
		end
		setmetatable(stanza, stanza_mt);
		for _, child in ipairs(stanza) do
			if type(child) == "table" then
				deserialize(child);
			end
		end
		if not stanza.tags then
			-- Rebuild tags
			local tags = {};
			for _, child in ipairs(stanza) do
				if type(child) == "table" then
					t_insert(tags, child);
				end
			end
			stanza.tags = tags;
		end
	end
	
	return stanza;
end

local function _clone(stanza)
	local attr, tags = {}, {};
	for k,v in pairs(stanza.attr) do attr[k] = v; end
	local new = { name = stanza.name, attr = attr, tags = tags };
	for i=1,#stanza do
		local child = stanza[i];
		if child.name then
			child = _clone(child);
			t_insert(tags, child);
		end
		t_insert(new, child);
	end
	return setmetatable(new, stanza_mt);
end
clone = _clone;

function message(attr, body)
	if not body then
		return stanza("message", attr);
	else
		return stanza("message", attr):tag("body"):text(body):up();
	end
end
function iq(attr)
	if attr and not attr.id then attr.id = new_id(); end
	return stanza("iq", attr or { id = new_id() });
end

function reply(orig)
	return stanza(orig.name, orig.attr and { to = orig.attr.from, from = orig.attr.to, id = orig.attr.id, type = ((orig.name == "iq" and "result") or orig.attr.type) });
end

do
	local xmpp_stanzas_attr = { xmlns = xmlns_stanzas };
	function error_reply(orig, type, condition, message)
		local t = reply(orig);
		t.attr.type = "error";
		t:tag("error", {type = type}) --COMPAT: Some day xmlns:stanzas goes here
			:tag(condition, xmpp_stanzas_attr):up();
		if (message) then t:tag("text", xmpp_stanzas_attr):text(message):up(); end
		return t; -- stanza ready for adding app-specific errors
	end
end

function presence(attr)
	return stanza("presence", attr);
end

if do_pretty_printing then
	local style_attrk = getstyle("yellow");
	local style_attrv = getstyle("red");
	local style_tagname = getstyle("red");
	local style_punc = getstyle("magenta");
	
	local attr_format = " "..getstring(style_attrk, "%s")..getstring(style_punc, "=")..getstring(style_attrv, "'%s'");
	local top_tag_format = getstring(style_punc, "<")..getstring(style_tagname, "%s").."%s"..getstring(style_punc, ">");
	--local tag_format = getstring(style_punc, "<")..getstring(style_tagname, "%s").."%s"..getstring(style_punc, ">").."%s"..getstring(style_punc, "</")..getstring(style_tagname, "%s")..getstring(style_punc, ">");
	local tag_format = top_tag_format.."%s"..getstring(style_punc, "</")..getstring(style_tagname, "%s")..getstring(style_punc, ">");
	function stanza_mt.pretty_print(t)
		local children_text = "";
		for n, child in ipairs(t) do
			if type(child) == "string" then
				children_text = children_text .. xml_escape(child);
			else
				children_text = children_text .. child:pretty_print();
			end
		end

		local attr_string = "";
		if t.attr then
			for k, v in pairs(t.attr) do if type(k) == "string" then attr_string = attr_string .. s_format(attr_format, k, tostring(v)); end end
		end
		return s_format(tag_format, t.name, attr_string, children_text, t.name);
	end
	
	function stanza_mt.pretty_top_tag(t)
		local attr_string = "";
		if t.attr then
			for k, v in pairs(t.attr) do if type(k) == "string" then attr_string = attr_string .. s_format(attr_format, k, tostring(v)); end end
		end
		return s_format(top_tag_format, t.name, attr_string);
	end
else
	-- Sorry, fresh out of colours for you guys ;)
	stanza_mt.pretty_print = stanza_mt.__tostring;
	stanza_mt.pretty_top_tag = stanza_mt.top_tag;
end

return _M;
 end)
package.preload['util.timer'] = (function (...)
-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--


local ns_addtimer = require "net.server".addtimer;
local event = require "net.server".event;
local event_base = require "net.server".event_base;

local math_min = math.min
local math_huge = math.huge
local get_time = require "socket".gettime;
local t_insert = table.insert;
local t_remove = table.remove;
local ipairs, pairs = ipairs, pairs;
local type = type;

local data = {};
local new_data = {};

module "timer"

local _add_task;
if not event then
	function _add_task(delay, func)
		local current_time = get_time();
		delay = delay + current_time;
		if delay >= current_time then
			t_insert(new_data, {delay, func});
		else
			func();
		end
	end

	ns_addtimer(function()
		local current_time = get_time();
		if #new_data > 0 then
			for _, d in pairs(new_data) do
				t_insert(data, d);
			end
			new_data = {};
		end
		
		local next_time = math_huge;
		for i, d in pairs(data) do
			local t, func = d[1], d[2];
			if t <= current_time then
				data[i] = nil;
				local r = func(current_time);
				if type(r) == "number" then
					_add_task(r, func);
					next_time = math_min(next_time, r);
				end
			else
				next_time = math_min(next_time, t - current_time);
			end
		end
		return next_time;
	end);
else
	local EVENT_LEAVE = (event.core and event.core.LEAVE) or -1;
	function _add_task(delay, func)
		local event_handle;
		event_handle = event_base:addevent(nil, 0, function ()
			local ret = func();
			if ret then
				return 0, ret;
			elseif event_handle then
				return EVENT_LEAVE;
			end
		end
		, delay);
	end
end

add_task = _add_task;

return _M;
 end)
package.preload['util.termcolours'] = (function (...)
-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--


local t_concat, t_insert = table.concat, table.insert;
local char, format = string.char, string.format;
local ipairs = ipairs;
local io_write = io.write;

local windows;
if os.getenv("WINDIR") then
	windows = require "util.windows";
end
local orig_color = windows and windows.get_consolecolor and windows.get_consolecolor();

module "termcolours"

local stylemap = {
			reset = 0; bright = 1, dim = 2, underscore = 4, blink = 5, reverse = 7, hidden = 8;
			black = 30; red = 31; green = 32; yellow = 33; blue = 34; magenta = 35; cyan = 36; white = 37;
			["black background"] = 40; ["red background"] = 41; ["green background"] = 42; ["yellow background"] = 43; ["blue background"] = 44; ["magenta background"] = 45; ["cyan background"] = 46; ["white background"] = 47;
			bold = 1, dark = 2, underline = 4, underlined = 4, normal = 0;
		}

local winstylemap = {
	["0"] = orig_color, -- reset
	["1"] = 7+8, -- bold
	["1;33"] = 2+4+8, -- bold yellow
	["1;31"] = 4+8 -- bold red
}

local fmt_string = char(0x1B).."[%sm%s"..char(0x1B).."[0m";
function getstring(style, text)
	if style then
		return format(fmt_string, style, text);
	else
		return text;
	end
end

function getstyle(...)
	local styles, result = { ... }, {};
	for i, style in ipairs(styles) do
		style = stylemap[style];
		if style then
			t_insert(result, style);
		end
	end
	return t_concat(result, ";");
end

local last = "0";
function setstyle(style)
	style = style or "0";
	if style ~= last then
		io_write("\27["..style.."m");
		last = style;
	end
end

if windows then
	function setstyle(style)
		style = style or "0";
		if style ~= last then
			windows.set_consolecolor(winstylemap[style] or orig_color);
			last = style;
		end
	end
	if not orig_color then
		function setstyle(style) end
	end
end

return _M;
 end)
package.preload['util.uuid'] = (function (...)
-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--


local m_random = math.random;
local tostring = tostring;
local os_time = os.time;
local os_clock = os.clock;
local sha1 = require "util.hashes".sha1;

module "uuid"

local last_uniq_time = 0;
local function uniq_time()
	local new_uniq_time = os_time();
	if last_uniq_time >= new_uniq_time then new_uniq_time = last_uniq_time + 1; end
	last_uniq_time = new_uniq_time;
	return new_uniq_time;
end

local function new_random(x)
	return sha1(x..os_clock()..tostring({}), true);
end

local buffer = new_random(uniq_time());
local function _seed(x)
	buffer = new_random(buffer..x);
end
local function get_nibbles(n)
	if #buffer < n then _seed(uniq_time()); end
	local r = buffer:sub(0, n);
	buffer = buffer:sub(n+1);
	return r;
end
local function get_twobits()
	return ("%x"):format(get_nibbles(1):byte() % 4 + 8);
end

function generate()
	-- generate RFC 4122 complaint UUIDs (version 4 - random)
	return get_nibbles(8).."-"..get_nibbles(4).."-4"..get_nibbles(3).."-"..(get_twobits())..get_nibbles(3).."-"..get_nibbles(12);
end
seed = _seed;

return _M;
 end)
package.preload['net.dns'] = (function (...)
-- Prosody IM
-- This file is included with Prosody IM. It has modifications,
-- which are hereby placed in the public domain.


-- todo: quick (default) header generation
-- todo: nxdomain, error handling
-- todo: cache results of encodeName


-- reference: http://tools.ietf.org/html/rfc1035
-- reference: http://tools.ietf.org/html/rfc1876 (LOC)


local socket = require "socket";
local timer = require "util.timer";

local _, windows = pcall(require, "util.windows");
local is_windows = (_ and windows) or os.getenv("WINDIR");

local coroutine, io, math, string, table =
      coroutine, io, math, string, table;

local ipairs, next, pairs, print, setmetatable, tostring, assert, error, unpack, select, type=
      ipairs, next, pairs, print, setmetatable, tostring, assert, error, unpack, select, type;

local ztact = { -- public domain 20080404 lua@ztact.com
	get = function(parent, ...)
		local len = select('#', ...);
		for i=1,len do
			parent = parent[select(i, ...)];
			if parent == nil then break; end
		end
		return parent;
	end;
	set = function(parent, ...)
		local len = select('#', ...);
		local key, value = select(len-1, ...);
		local cutpoint, cutkey;

		for i=1,len-2 do
			local key = select (i, ...)
			local child = parent[key]

			if value == nil then
				if child == nil then
					return;
				elseif next(child, next(child)) then
					cutpoint = nil; cutkey = nil;
				elseif cutpoint == nil then
					cutpoint = parent; cutkey = key;
				end
			elseif child == nil then
				child = {};
				parent[key] = child;
			end
			parent = child
		end

		if value == nil and cutpoint then
			cutpoint[cutkey] = nil;
		else
			parent[key] = value;
			return value;
		end
	end;
};
local get, set = ztact.get, ztact.set;

local default_timeout = 15;

-------------------------------------------------- module dns
module('dns')
local dns = _M;


-- dns type & class codes ------------------------------ dns type & class codes


local append = table.insert


local function highbyte(i)    -- - - - - - - - - - - - - - - - - - -  highbyte
	return (i-(i%0x100))/0x100;
end


local function augment (t)    -- - - - - - - - - - - - - - - - - - - -  augment
	local a = {};
	for i,s in pairs(t) do
		a[i] = s;
		a[s] = s;
		a[string.lower(s)] = s;
	end
	return a;
end


local function encode (t)    -- - - - - - - - - - - - - - - - - - - - -  encode
	local code = {};
	for i,s in pairs(t) do
		local word = string.char(highbyte(i), i%0x100);
		code[i] = word;
		code[s] = word;
		code[string.lower(s)] = word;
	end
	return code;
end


dns.types = {
	'A', 'NS', 'MD', 'MF', 'CNAME', 'SOA', 'MB', 'MG', 'MR', 'NULL', 'WKS',
	'PTR', 'HINFO', 'MINFO', 'MX', 'TXT',
	[ 28] = 'AAAA', [ 29] = 'LOC',   [ 33] = 'SRV',
	[252] = 'AXFR', [253] = 'MAILB', [254] = 'MAILA', [255] = '*' };


dns.classes = { 'IN', 'CS', 'CH', 'HS', [255] = '*' };


dns.type      = augment (dns.types);
dns.class     = augment (dns.classes);
dns.typecode  = encode  (dns.types);
dns.classcode = encode  (dns.classes);



local function standardize(qname, qtype, qclass)    -- - - - - - - standardize
	if string.byte(qname, -1) ~= 0x2E then qname = qname..'.';  end
	qname = string.lower(qname);
	return qname, dns.type[qtype or 'A'], dns.class[qclass or 'IN'];
end


local function prune(rrs, time, soft)    -- - - - - - - - - - - - - - -  prune
	time = time or socket.gettime();
	for i,rr in pairs(rrs) do
		if rr.tod then
			-- rr.tod = rr.tod - 50    -- accelerated decripitude
			rr.ttl = math.floor(rr.tod - time);
			if rr.ttl <= 0 then
				table.remove(rrs, i);
				return prune(rrs, time, soft); -- Re-iterate
			end
		elseif soft == 'soft' then    -- What is this?  I forget!
			assert(rr.ttl == 0);
			rrs[i] = nil;
		end
	end
end


-- metatables & co. ------------------------------------------ metatables & co.


local resolver = {};
resolver.__index = resolver;

resolver.timeout = default_timeout;

local function default_rr_tostring(rr)
	local rr_val = rr.type and rr[rr.type:lower()];
	if type(rr_val) ~= "string" then
		return "<UNKNOWN RDATA TYPE>";
	end
	return rr_val;
end

local special_tostrings = {
	LOC = resolver.LOC_tostring;
	MX  = function (rr)
		return string.format('%2i %s', rr.pref, rr.mx);
	end;
	SRV = function (rr)
		local s = rr.srv;
		return string.format('%5d %5d %5d %s', s.priority, s.weight, s.port, s.target);
	end;
};

local rr_metatable = {};   -- - - - - - - - - - - - - - - - - - -  rr_metatable
function rr_metatable.__tostring(rr)
	local rr_string = (special_tostrings[rr.type] or default_rr_tostring)(rr);
	return string.format('%2s %-5s %6i %-28s %s', rr.class, rr.type, rr.ttl, rr.name, rr_string);
end


local rrs_metatable = {};    -- - - - - - - - - - - - - - - - - -  rrs_metatable
function rrs_metatable.__tostring(rrs)
	local t = {};
	for i,rr in pairs(rrs) do
		append(t, tostring(rr)..'\n');
	end
	return table.concat(t);
end


local cache_metatable = {};    -- - - - - - - - - - - - - - - -  cache_metatable
function cache_metatable.__tostring(cache)
	local time = socket.gettime();
	local t = {};
	for class,types in pairs(cache) do
		for type,names in pairs(types) do
			for name,rrs in pairs(names) do
				prune(rrs, time);
				append(t, tostring(rrs));
			end
		end
	end
	return table.concat(t);
end


function resolver:new()    -- - - - - - - - - - - - - - - - - - - - - resolver
	local r = { active = {}, cache = {}, unsorted = {} };
	setmetatable(r, resolver);
	setmetatable(r.cache, cache_metatable);
	setmetatable(r.unsorted, { __mode = 'kv' });
	return r;
end


-- packet layer -------------------------------------------------- packet layer


function dns.random(...)    -- - - - - - - - - - - - - - - - - - -  dns.random
	math.randomseed(math.floor(10000*socket.gettime()));
	dns.random = math.random;
	return dns.random(...);
end


local function encodeHeader(o)    -- - - - - - - - - - - - - - -  encodeHeader
	o = o or {};
	o.id = o.id or dns.random(0, 0xffff); -- 16b	(random) id

	o.rd = o.rd or 1;		--  1b  1 recursion desired
	o.tc = o.tc or 0;		--  1b	1 truncated response
	o.aa = o.aa or 0;		--  1b	1 authoritative response
	o.opcode = o.opcode or 0;	--  4b	0 query
				--  1 inverse query
				--	2 server status request
				--	3-15 reserved
	o.qr = o.qr or 0;		--  1b	0 query, 1 response

	o.rcode = o.rcode or 0;	--  4b  0 no error
				--	1 format error
				--	2 server failure
				--	3 name error
				--	4 not implemented
				--	5 refused
				--	6-15 reserved
	o.z = o.z  or 0;		--  3b  0 resvered
	o.ra = o.ra or 0;		--  1b  1 recursion available

	o.qdcount = o.qdcount or 1;	-- 16b	number of question RRs
	o.ancount = o.ancount or 0;	-- 16b	number of answers RRs
	o.nscount = o.nscount or 0;	-- 16b	number of nameservers RRs
	o.arcount = o.arcount or 0;	-- 16b  number of additional RRs

	-- string.char() rounds, so prevent roundup with -0.4999
	local header = string.char(
		highbyte(o.id), o.id %0x100,
		o.rd + 2*o.tc + 4*o.aa + 8*o.opcode + 128*o.qr,
		o.rcode + 16*o.z + 128*o.ra,
		highbyte(o.qdcount),  o.qdcount %0x100,
		highbyte(o.ancount),  o.ancount %0x100,
		highbyte(o.nscount),  o.nscount %0x100,
		highbyte(o.arcount),  o.arcount %0x100
	);

	return header, o.id;
end


local function encodeName(name)    -- - - - - - - - - - - - - - - - encodeName
	local t = {};
	for part in string.gmatch(name, '[^.]+') do
		append(t, string.char(string.len(part)));
		append(t, part);
	end
	append(t, string.char(0));
	return table.concat(t);
end


local function encodeQuestion(qname, qtype, qclass)    -- - - - encodeQuestion
	qname  = encodeName(qname);
	qtype  = dns.typecode[qtype or 'a'];
	qclass = dns.classcode[qclass or 'in'];
	return qname..qtype..qclass;
end


function resolver:byte(len)    -- - - - - - - - - - - - - - - - - - - - - byte
	len = len or 1;
	local offset = self.offset;
	local last = offset + len - 1;
	if last > #self.packet then
		error(string.format('out of bounds: %i>%i', last, #self.packet));
	end
	self.offset = offset + len;
	return string.byte(self.packet, offset, last);
end


function resolver:word()    -- - - - - - - - - - - - - - - - - - - - - -  word
	local b1, b2 = self:byte(2);
	return 0x100*b1 + b2;
end


function resolver:dword ()    -- - - - - - - - - - - - - - - - - - - - -  dword
	local b1, b2, b3, b4 = self:byte(4);
	--print('dword', b1, b2, b3, b4);
	return 0x1000000*b1 + 0x10000*b2 + 0x100*b3 + b4;
end


function resolver:sub(len)    -- - - - - - - - - - - - - - - - - - - - - - sub
	len = len or 1;
	local s = string.sub(self.packet, self.offset, self.offset + len - 1);
	self.offset = self.offset + len;
	return s;
end


function resolver:header(force)    -- - - - - - - - - - - - - - - - - - header
	local id = self:word();
	--print(string.format(':header  id  %x', id));
	if not self.active[id] and not force then return nil; end

	local h = { id = id };

	local b1, b2 = self:byte(2);

	h.rd      = b1 %2;
	h.tc      = b1 /2%2;
	h.aa      = b1 /4%2;
	h.opcode  = b1 /8%16;
	h.qr      = b1 /128;

	h.rcode   = b2 %16;
	h.z       = b2 /16%8;
	h.ra      = b2 /128;

	h.qdcount = self:word();
	h.ancount = self:word();
	h.nscount = self:word();
	h.arcount = self:word();

	for k,v in pairs(h) do h[k] = v-v%1; end

	return h;
end


function resolver:name()    -- - - - - - - - - - - - - - - - - - - - - -  name
	local remember, pointers = nil, 0;
	local len = self:byte();
	local n = {};
	while len > 0 do
		if len >= 0xc0 then    -- name is "compressed"
			pointers = pointers + 1;
			if pointers >= 20 then error('dns error: 20 pointers'); end;
			local offset = ((len-0xc0)*0x100) + self:byte();
			remember = remember or self.offset;
			self.offset = offset + 1;    -- +1 for lua
		else    -- name is not compressed
			append(n, self:sub(len)..'.');
		end
		len = self:byte();
	end
	self.offset = remember or self.offset;
	return table.concat(n);
end


function resolver:question()    -- - - - - - - - - - - - - - - - - -  question
	local q = {};
	q.name  = self:name();
	q.type  = dns.type[self:word()];
	q.class = dns.class[self:word()];
	return q;
end


function resolver:A(rr)    -- - - - - - - - - - - - - - - - - - - - - - - -  A
	local b1, b2, b3, b4 = self:byte(4);
	rr.a = string.format('%i.%i.%i.%i', b1, b2, b3, b4);
end

function resolver:AAAA(rr)
	local addr = {};
	for i = 1, rr.rdlength, 2 do
		local b1, b2 = self:byte(2);
		table.insert(addr, ("%02x%02x"):format(b1, b2));
	end
	rr.aaaa = table.concat(addr, ":");
end

function resolver:CNAME(rr)    -- - - - - - - - - - - - - - - - - - - -  CNAME
	rr.cname = self:name();
end


function resolver:MX(rr)    -- - - - - - - - - - - - - - - - - - - - - - -  MX
	rr.pref = self:word();
	rr.mx   = self:name();
end


function resolver:LOC_nibble_power()    -- - - - - - - - - -  LOC_nibble_power
	local b = self:byte();
	--print('nibbles', ((b-(b%0x10))/0x10), (b%0x10));
	return ((b-(b%0x10))/0x10) * (10^(b%0x10));
end


function resolver:LOC(rr)    -- - - - - - - - - - - - - - - - - - - - - -  LOC
	rr.version = self:byte();
	if rr.version == 0 then
		rr.loc           = rr.loc or {};
		rr.loc.size      = self:LOC_nibble_power();
		rr.loc.horiz_pre = self:LOC_nibble_power();
		rr.loc.vert_pre  = self:LOC_nibble_power();
		rr.loc.latitude  = self:dword();
		rr.loc.longitude = self:dword();
		rr.loc.altitude  = self:dword();
	end
end


local function LOC_tostring_degrees(f, pos, neg)    -- - - - - - - - - - - - -
	f = f - 0x80000000;
	if f < 0 then pos = neg; f = -f; end
	local deg, min, msec;
	msec = f%60000;
	f    = (f-msec)/60000;
	min  = f%60;
	deg = (f-min)/60;
	return string.format('%3d %2d %2.3f %s', deg, min, msec/1000, pos);
end


function resolver.LOC_tostring(rr)    -- - - - - - - - - - - - -  LOC_tostring
	local t = {};

	--[[
	for k,name in pairs { 'size', 'horiz_pre', 'vert_pre', 'latitude', 'longitude', 'altitude' } do
		append(t, string.format('%4s%-10s: %12.0f\n', '', name, rr.loc[name]));
	end
	--]]

	append(t, string.format(
		'%s    %s    %.2fm %.2fm %.2fm %.2fm',
		LOC_tostring_degrees (rr.loc.latitude, 'N', 'S'),
		LOC_tostring_degrees (rr.loc.longitude, 'E', 'W'),
		(rr.loc.altitude - 10000000) / 100,
		rr.loc.size / 100,
		rr.loc.horiz_pre / 100,
		rr.loc.vert_pre / 100
	));

	return table.concat(t);
end


function resolver:NS(rr)    -- - - - - - - - - - - - - - - - - - - - - - -  NS
	rr.ns = self:name();
end


function resolver:SOA(rr)    -- - - - - - - - - - - - - - - - - - - - - -  SOA
end


function resolver:SRV(rr)    -- - - - - - - - - - - - - - - - - - - - - -  SRV
	  rr.srv = {};
	  rr.srv.priority = self:word();
	  rr.srv.weight   = self:word();
	  rr.srv.port     = self:word();
	  rr.srv.target   = self:name();
end

function resolver:PTR(rr)
	rr.ptr = self:name();
end

function resolver:TXT(rr)    -- - - - - - - - - - - - - - - - - - - - - -  TXT
	rr.txt = self:sub (self:byte());
end


function resolver:rr()    -- - - - - - - - - - - - - - - - - - - - - - - -  rr
	local rr = {};
	setmetatable(rr, rr_metatable);
	rr.name     = self:name(self);
	rr.type     = dns.type[self:word()] or rr.type;
	rr.class    = dns.class[self:word()] or rr.class;
	rr.ttl      = 0x10000*self:word() + self:word();
	rr.rdlength = self:word();

	if rr.ttl <= 0 then
		rr.tod = self.time + 30;
	else
		rr.tod = self.time + rr.ttl;
	end

	local remember = self.offset;
	local rr_parser = self[dns.type[rr.type]];
	if rr_parser then rr_parser(self, rr); end
	self.offset = remember;
	rr.rdata = self:sub(rr.rdlength);
	return rr;
end


function resolver:rrs (count)    -- - - - - - - - - - - - - - - - - - - - - rrs
	local rrs = {};
	for i = 1,count do append(rrs, self:rr()); end
	return rrs;
end


function resolver:decode(packet, force)    -- - - - - - - - - - - - - - decode
	self.packet, self.offset = packet, 1;
	local header = self:header(force);
	if not header then return nil; end
	local response = { header = header };

	response.question = {};
	local offset = self.offset;
	for i = 1,response.header.qdcount do
		append(response.question, self:question());
	end
	response.question.raw = string.sub(self.packet, offset, self.offset - 1);

	if not force then
		if not self.active[response.header.id] or not self.active[response.header.id][response.question.raw] then
			return nil;
		end
	end

	response.answer     = self:rrs(response.header.ancount);
	response.authority  = self:rrs(response.header.nscount);
	response.additional = self:rrs(response.header.arcount);

	return response;
end


-- socket layer -------------------------------------------------- socket layer


resolver.delays = { 1, 3 };


function resolver:addnameserver(address)    -- - - - - - - - - - addnameserver
	self.server = self.server or {};
	append(self.server, address);
end


function resolver:setnameserver(address)    -- - - - - - - - - - setnameserver
	self.server = {};
	self:addnameserver(address);
end


function resolver:adddefaultnameservers()    -- - - - -  adddefaultnameservers
	if is_windows then
		if windows and windows.get_nameservers then
			for _, server in ipairs(windows.get_nameservers()) do
				self:addnameserver(server);
			end
		end
		if not self.server or #self.server == 0 then
			-- TODO log warning about no nameservers, adding opendns servers as fallback
			self:addnameserver("208.67.222.222");
			self:addnameserver("208.67.220.220");
		end
	else -- posix
		local resolv_conf = io.open("/etc/resolv.conf");
		if resolv_conf then
			for line in resolv_conf:lines() do
				line = line:gsub("#.*$", "")
					:match('^%s*nameserver%s+(.*)%s*$');
				if line then
					line:gsub("%f[%d.](%d+%.%d+%.%d+%.%d+)%f[^%d.]", function (address)
						self:addnameserver(address)
					end);
				end
			end
		end
		if not self.server or #self.server == 0 then
			-- TODO log warning about no nameservers, adding localhost as the default nameserver
			self:addnameserver("127.0.0.1");
		end
	end
end


function resolver:getsocket(servernum)    -- - - - - - - - - - - - - getsocket
	self.socket = self.socket or {};
	self.socketset = self.socketset or {};

	local sock = self.socket[servernum];
	if sock then return sock; end

	local err;
	sock, err = socket.udp();
	if not sock then
		return nil, err;
	end
	if self.socket_wrapper then sock = self.socket_wrapper(sock, self); end
	sock:settimeout(0);
	-- todo: attempt to use a random port, fallback to 0
	sock:setsockname('*', 0);
	sock:setpeername(self.server[servernum], 53);
	self.socket[servernum] = sock;
	self.socketset[sock] = servernum;
	return sock;
end

function resolver:voidsocket(sock)
	if self.socket[sock] then
		self.socketset[self.socket[sock]] = nil;
		self.socket[sock] = nil;
	elseif self.socketset[sock] then
		self.socket[self.socketset[sock]] = nil;
		self.socketset[sock] = nil;
	end
end

function resolver:socket_wrapper_set(func)  -- - - - - - - socket_wrapper_set
	self.socket_wrapper = func;
end


function resolver:closeall ()    -- - - - - - - - - - - - - - - - - -  closeall
	for i,sock in ipairs(self.socket) do
		self.socket[i] = nil;
		self.socketset[sock] = nil;
		sock:close();
	end
end


function resolver:remember(rr, type)    -- - - - - - - - - - - - - -  remember
	--print ('remember', type, rr.class, rr.type, rr.name)
	local qname, qtype, qclass = standardize(rr.name, rr.type, rr.class);

	if type ~= '*' then
		type = qtype;
		local all = get(self.cache, qclass, '*', qname);
		--print('remember all', all);
		if all then append(all, rr); end
	end

	self.cache = self.cache or setmetatable({}, cache_metatable);
	local rrs = get(self.cache, qclass, type, qname) or
		set(self.cache, qclass, type, qname, setmetatable({}, rrs_metatable));
	append(rrs, rr);

	if type == 'MX' then self.unsorted[rrs] = true; end
end


local function comp_mx(a, b)    -- - - - - - - - - - - - - - - - - - - comp_mx
	return (a.pref == b.pref) and (a.mx < b.mx) or (a.pref < b.pref);
end


function resolver:peek (qname, qtype, qclass)    -- - - - - - - - - - - -  peek
	qname, qtype, qclass = standardize(qname, qtype, qclass);
	local rrs = get(self.cache, qclass, qtype, qname);
	if not rrs then return nil; end
	if prune(rrs, socket.gettime()) and qtype == '*' or not next(rrs) then
		set(self.cache, qclass, qtype, qname, nil);
		return nil;
	end
	if self.unsorted[rrs] then table.sort (rrs, comp_mx); end
	return rrs;
end


function resolver:purge(soft)    -- - - - - - - - - - - - - - - - - - -  purge
	if soft == 'soft' then
		self.time = socket.gettime();
		for class,types in pairs(self.cache or {}) do
			for type,names in pairs(types) do
				for name,rrs in pairs(names) do
					prune(rrs, self.time, 'soft')
				end
			end
		end
	else self.cache = {}; end
end


function resolver:query(qname, qtype, qclass)    -- - - - - - - - - - -- query
	qname, qtype, qclass = standardize(qname, qtype, qclass)

	if not self.server then self:adddefaultnameservers(); end

	local question = encodeQuestion(qname, qtype, qclass);
	local peek = self:peek (qname, qtype, qclass);
	if peek then return peek; end

	local header, id = encodeHeader();
	--print ('query  id', id, qclass, qtype, qname)
	local o = {
		packet = header..question,
		server = self.best_server,
		delay  = 1,
		retry  = socket.gettime() + self.delays[1]
	};

	-- remember the query
	self.active[id] = self.active[id] or {};
	self.active[id][question] = o;

	-- remember which coroutine wants the answer
	local co = coroutine.running();
	if co then
		set(self.wanted, qclass, qtype, qname, co, true);
		--set(self.yielded, co, qclass, qtype, qname, true);
	end

	local conn, err = self:getsocket(o.server)
	if not conn then
		return nil, err;
	end
	conn:send (o.packet)
	
	if timer and self.timeout then
		local num_servers = #self.server;
		local i = 1;
		timer.add_task(self.timeout, function ()
			if get(self.wanted, qclass, qtype, qname, co) then
				if i < num_servers then
					i = i + 1;
					self:servfail(conn);
					o.server = self.best_server;
					conn, err = self:getsocket(o.server);
					if conn then
						conn:send(o.packet);
						return self.timeout;
					end
				end
				-- Tried everything, failed
				self:cancel(qclass, qtype, qname, co, true);
			end
		end)
	end
	return true;
end

function resolver:servfail(sock)
	-- Resend all queries for this server

	local num = self.socketset[sock]

	-- Socket is dead now
	self:voidsocket(sock);

	-- Find all requests to the down server, and retry on the next server
	self.time = socket.gettime();
	for id,queries in pairs(self.active) do
		for question,o in pairs(queries) do
			if o.server == num then -- This request was to the broken server
				o.server = o.server + 1 -- Use next server
				if o.server > #self.server then
					o.server = 1;
				end

				o.retries = (o.retries or 0) + 1;
				if o.retries >= #self.server then
					--print('timeout');
					queries[question] = nil;
				else
					local _a = self:getsocket(o.server);
					if _a then _a:send(o.packet); end
				end
			end
		end
	end

	if num == self.best_server then
		self.best_server = self.best_server + 1;
		if self.best_server > #self.server then
			-- Exhausted all servers, try first again
			self.best_server = 1;
		end
	end
end

function resolver:settimeout(seconds)
	self.timeout = seconds;
end

function resolver:receive(rset)    -- - - - - - - - - - - - - - - - -  receive
	--print('receive');  print(self.socket);
	self.time = socket.gettime();
	rset = rset or self.socket;

	local response;
	for i,sock in pairs(rset) do

		if self.socketset[sock] then
			local packet = sock:receive();
			if packet then
				response = self:decode(packet);
				if response and self.active[response.header.id]
					and self.active[response.header.id][response.question.raw] then
					--print('received response');
					--self.print(response);

					for j,rr in pairs(response.answer) do
						if rr.name:sub(-#response.question[1].name, -1) == response.question[1].name then
							self:remember(rr, response.question[1].type)
						end
					end

					-- retire the query
					local queries = self.active[response.header.id];
					queries[response.question.raw] = nil;
					
					if not next(queries) then self.active[response.header.id] = nil; end
					if not next(self.active) then self:closeall(); end

					-- was the query on the wanted list?
					local q = response.question[1];
					local cos = get(self.wanted, q.class, q.type, q.name);
					if cos then
						for co in pairs(cos) do
							set(self.yielded, co, q.class, q.type, q.name, nil);
							if coroutine.status(co) == "suspended" then coroutine.resume(co); end
						end
						set(self.wanted, q.class, q.type, q.name, nil);
					end
				end
			end
		end
	end

	return response;
end


function resolver:feed(sock, packet, force)
	--print('receive'); print(self.socket);
	self.time = socket.gettime();

	local response = self:decode(packet, force);
	if response and self.active[response.header.id]
		and self.active[response.header.id][response.question.raw] then
		--print('received response');
		--self.print(response);

		for j,rr in pairs(response.answer) do
			self:remember(rr, response.question[1].type);
		end

		-- retire the query
		local queries = self.active[response.header.id];
		queries[response.question.raw] = nil;
		if not next(queries) then self.active[response.header.id] = nil; end
		if not next(self.active) then self:closeall(); end

		-- was the query on the wanted list?
		local q = response.question[1];
		if q then
			local cos = get(self.wanted, q.class, q.type, q.name);
			if cos then
				for co in pairs(cos) do
					set(self.yielded, co, q.class, q.type, q.name, nil);
					if coroutine.status(co) == "suspended" then coroutine.resume(co); end
				end
				set(self.wanted, q.class, q.type, q.name, nil);
			end
		end
	end

	return response;
end

function resolver:cancel(qclass, qtype, qname, co, call_handler)
	local cos = get(self.wanted, qclass, qtype, qname);
	if cos then
		if call_handler then
			coroutine.resume(co);
		end
		cos[co] = nil;
	end
end

function resolver:pulse()    -- - - - - - - - - - - - - - - - - - - - -  pulse
	--print(':pulse');
	while self:receive() do end
	if not next(self.active) then return nil; end

	self.time = socket.gettime();
	for id,queries in pairs(self.active) do
		for question,o in pairs(queries) do
			if self.time >= o.retry then

				o.server = o.server + 1;
				if o.server > #self.server then
					o.server = 1;
					o.delay = o.delay + 1;
				end

				if o.delay > #self.delays then
					--print('timeout');
					queries[question] = nil;
					if not next(queries) then self.active[id] = nil; end
					if not next(self.active) then return nil; end
				else
					--print('retry', o.server, o.delay);
					local _a = self.socket[o.server];
					if _a then _a:send(o.packet); end
					o.retry = self.time + self.delays[o.delay];
				end
			end
		end
	end

	if next(self.active) then return true; end
	return nil;
end


function resolver:lookup(qname, qtype, qclass)    -- - - - - - - - - -  lookup
	self:query (qname, qtype, qclass)
	while self:pulse() do
		local recvt = {}
		for i, s in ipairs(self.socket) do
			recvt[i] = s
		end
		socket.select(recvt, nil, 4)
	end
	--print(self.cache);
	return self:peek(qname, qtype, qclass);
end

function resolver:lookupex(handler, qname, qtype, qclass)    -- - - - - - - - - -  lookup
	return self:peek(qname, qtype, qclass) or self:query(qname, qtype, qclass);
end

function resolver:tohostname(ip)
	return dns.lookup(ip:gsub("(%d+)%.(%d+)%.(%d+)%.(%d+)", "%4.%3.%2.%1.in-addr.arpa."), "PTR");
end

--print ---------------------------------------------------------------- print


local hints = {    -- - - - - - - - - - - - - - - - - - - - - - - - - - - hints
	qr = { [0]='query', 'response' },
	opcode = { [0]='query', 'inverse query', 'server status request' },
	aa = { [0]='non-authoritative', 'authoritative' },
	tc = { [0]='complete', 'truncated' },
	rd = { [0]='recursion not desired', 'recursion desired' },
	ra = { [0]='recursion not available', 'recursion available' },
	z  = { [0]='(reserved)' },
	rcode = { [0]='no error', 'format error', 'server failure', 'name error', 'not implemented' },

	type = dns.type,
	class = dns.class
};


local function hint(p, s)    -- - - - - - - - - - - - - - - - - - - - - - hint
	return (hints[s] and hints[s][p[s]]) or '';
end


function resolver.print(response)    -- - - - - - - - - - - - - resolver.print
	for s,s in pairs { 'id', 'qr', 'opcode', 'aa', 'tc', 'rd', 'ra', 'z',
						'rcode', 'qdcount', 'ancount', 'nscount', 'arcount' } do
		print( string.format('%-30s', 'header.'..s), response.header[s], hint(response.header, s) );
	end

	for i,question in ipairs(response.question) do
		print(string.format ('question[%i].name         ', i), question.name);
		print(string.format ('question[%i].type         ', i), question.type);
		print(string.format ('question[%i].class        ', i), question.class);
	end

	local common = { name=1, type=1, class=1, ttl=1, rdlength=1, rdata=1 };
	local tmp;
	for s,s in pairs({'answer', 'authority', 'additional'}) do
		for i,rr in pairs(response[s]) do
			for j,t in pairs({ 'name', 'type', 'class', 'ttl', 'rdlength' }) do
				tmp = string.format('%s[%i].%s', s, i, t);
				print(string.format('%-30s', tmp), rr[t], hint(rr, t));
			end
			for j,t in pairs(rr) do
				if not common[j] then
					tmp = string.format('%s[%i].%s', s, i, j);
					print(string.format('%-30s  %s', tostring(tmp), tostring(t)));
				end
			end
		end
	end
end


-- module api ------------------------------------------------------ module api


function dns.resolver ()    -- - - - - - - - - - - - - - - - - - - - - resolver
	-- this function seems to be redundant with resolver.new ()

	local r = { active = {}, cache = {}, unsorted = {}, wanted = {}, yielded = {}, best_server = 1 };
	setmetatable (r, resolver);
	setmetatable (r.cache, cache_metatable);
	setmetatable (r.unsorted, { __mode = 'kv' });
	return r;
end

local _resolver = dns.resolver();
dns._resolver = _resolver;

function dns.lookup(...)    -- - - - - - - - - - - - - - - - - - - - -  lookup
	return _resolver:lookup(...);
end

function dns.tohostname(...)
	return _resolver:tohostname(...);
end

function dns.purge(...)    -- - - - - - - - - - - - - - - - - - - - - -  purge
	return _resolver:purge(...);
end

function dns.peek(...)    -- - - - - - - - - - - - - - - - - - - - - - -  peek
	return _resolver:peek(...);
end

function dns.query(...)    -- - - - - - - - - - - - - - - - - - - - - -  query
	return _resolver:query(...);
end

function dns.feed(...)    -- - - - - - - - - - - - - - - - - - - - - - -  feed
	return _resolver:feed(...);
end

function dns.cancel(...)  -- - - - - - - - - - - - - - - - - - - - - -  cancel
	return _resolver:cancel(...);
end

function dns.settimeout(...)
	return _resolver:settimeout(...);
end

function dns.socket_wrapper_set(...)    -- - - - - - - - -  socket_wrapper_set
	return _resolver:socket_wrapper_set(...);
end

return dns;
 end)
package.preload['net.adns'] = (function (...)
-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local server = require "net.server";
local dns = require "net.dns";

local log = require "util.logger".init("adns");

local t_insert, t_remove = table.insert, table.remove;
local coroutine, tostring, pcall = coroutine, tostring, pcall;

local function dummy_send(sock, data, i, j) return (j-i)+1; end

module "adns"

function lookup(handler, qname, qtype, qclass)
	return coroutine.wrap(function (peek)
				if peek then
					log("debug", "Records for %s already cached, using those...", qname);
					handler(peek);
					return;
				end
				log("debug", "Records for %s not in cache, sending query (%s)...", qname, tostring(coroutine.running()));
				local ok, err = dns.query(qname, qtype, qclass);
				if ok then
					coroutine.yield({ qclass or "IN", qtype or "A", qname, coroutine.running()}); -- Wait for reply
					log("debug", "Reply for %s (%s)", qname, tostring(coroutine.running()));
				end
				if ok then
					ok, err = pcall(handler, dns.peek(qname, qtype, qclass));
				else
					log("error", "Error sending DNS query: %s", err);
					ok, err = pcall(handler, nil, err);
				end
				if not ok then
					log("error", "Error in DNS response handler: %s", tostring(err));
				end
			end)(dns.peek(qname, qtype, qclass));
end

function cancel(handle, call_handler, reason)
	log("warn", "Cancelling DNS lookup for %s", tostring(handle[3]));
	dns.cancel(handle[1], handle[2], handle[3], handle[4], call_handler);
end

function new_async_socket(sock, resolver)
	local peername = "<unknown>";
	local listener = {};
	local handler = {};
	function listener.onincoming(conn, data)
		if data then
			dns.feed(handler, data);
		end
	end
	function listener.ondisconnect(conn, err)
		if err then
			log("warn", "DNS socket for %s disconnected: %s", peername, err);
			local servers = resolver.server;
			if resolver.socketset[conn] == resolver.best_server and resolver.best_server == #servers then
				log("error", "Exhausted all %d configured DNS servers, next lookup will try %s again", #servers, servers[1]);
			end
		
			resolver:servfail(conn); -- Let the magic commence
		end
	end
	handler = server.wrapclient(sock, "dns", 53, listener);
	if not handler then
		log("warn", "handler is nil");
	end
	
	handler.settimeout = function () end
	handler.setsockname = function (_, ...) return sock:setsockname(...); end
	handler.setpeername = function (_, ...) peername = (...); local ret = sock:setpeername(...); _:set_send(dummy_send); return ret; end
	handler.connect = function (_, ...) return sock:connect(...) end
	--handler.send = function (_, data) _:write(data);  return _.sendbuffer and _.sendbuffer(); end
	handler.send = function (_, data)
		local getpeername = sock.getpeername;
		log("debug", "Sending DNS query to %s", (getpeername and getpeername(sock)) or "<unconnected>");
		return sock:send(data);
	end
	return handler;
end

dns.socket_wrapper_set(new_async_socket);

return _M;
 end)
package.preload['net.server'] = (function (...)
-- 
-- server.lua by blastbeat of the luadch project
-- Re-used here under the MIT/X Consortium License
-- 
-- Modifications (C) 2008-2010 Matthew Wild, Waqas Hussain
--

-- // wrapping luadch stuff // --

local use = function( what )
	return _G[ what ]
end
local clean = function( tbl )
	for i, k in pairs( tbl ) do
		tbl[ i ] = nil
	end
end

local log, table_concat = require ("util.logger").init("socket"), table.concat;
local out_put = function (...) return log("debug", table_concat{...}); end
local out_error = function (...) return log("warn", table_concat{...}); end
local mem_free = collectgarbage

----------------------------------// DECLARATION //--

--// constants //--

local STAT_UNIT = 1 -- byte

--// lua functions //--

local type = use "type"
local pairs = use "pairs"
local ipairs = use "ipairs"
local tonumber = use "tonumber"
local tostring = use "tostring"
local collectgarbage = use "collectgarbage"

--// lua libs //--

local os = use "os"
local table = use "table"
local string = use "string"
local coroutine = use "coroutine"

--// lua lib methods //--

local os_difftime = os.difftime
local math_min = math.min
local math_huge = math.huge
local table_concat = table.concat
local table_remove = table.remove
local string_len = string.len
local string_sub = string.sub
local coroutine_wrap = coroutine.wrap
local coroutine_yield = coroutine.yield

--// extern libs //--

local luasec = use "ssl"
local luasocket = use "socket" or require "socket"
local luasocket_gettime = luasocket.gettime

--// extern lib methods //--

local ssl_wrap = ( luasec and luasec.wrap )
local socket_bind = luasocket.bind
local socket_sleep = luasocket.sleep
local socket_select = luasocket.select
local ssl_newcontext = ( luasec and luasec.newcontext )

--// functions //--

local id
local loop
local stats
local idfalse
local addtimer
local closeall
local addsocket
local addserver
local getserver
local wrapserver
local getsettings
local closesocket
local removesocket
local removeserver
local changetimeout
local wrapconnection
local changesettings

--// tables //--

local _server
local _readlist
local _timerlist
local _sendlist
local _socketlist
local _closelist
local _readtimes
local _writetimes

--// simple data types //--

local _
local _readlistlen
local _sendlistlen
local _timerlistlen

local _sendtraffic
local _readtraffic

local _selecttimeout
local _sleeptime

local _starttime
local _currenttime

local _maxsendlen
local _maxreadlen

local _checkinterval
local _sendtimeout
local _readtimeout

local _cleanqueue

local _timer

local _maxclientsperserver

local _maxsslhandshake

----------------------------------// DEFINITION //--

_server = { } -- key = port, value = table; list of listening servers
_readlist = { } -- array with sockets to read from
_sendlist = { } -- arrary with sockets to write to
_timerlist = { } -- array of timer functions
_socketlist = { } -- key = socket, value = wrapped socket (handlers)
_readtimes = { } -- key = handler, value = timestamp of last data reading
_writetimes = { } -- key = handler, value = timestamp of last data writing/sending
_closelist = { } -- handlers to close

_readlistlen = 0 -- length of readlist
_sendlistlen = 0 -- length of sendlist
_timerlistlen = 0 -- lenght of timerlist

_sendtraffic = 0 -- some stats
_readtraffic = 0

_selecttimeout = 1 -- timeout of socket.select
_sleeptime = 0 -- time to wait at the end of every loop

_maxsendlen = 51000 * 1024 -- max len of send buffer
_maxreadlen = 25000 * 1024 -- max len of read buffer

_checkinterval = 1200000 -- interval in secs to check idle clients
_sendtimeout = 60000 -- allowed send idle time in secs
_readtimeout = 6 * 60 * 60 -- allowed read idle time in secs

_cleanqueue = false -- clean bufferqueue after using

_maxclientsperserver = 1000

_maxsslhandshake = 30 -- max handshake round-trips

----------------------------------// PRIVATE //--

wrapserver = function( listeners, socket, ip, serverport, pattern, sslctx, maxconnections ) -- this function wraps a server

	maxconnections = maxconnections or _maxclientsperserver

	local connections = 0

	local dispatch, disconnect = listeners.onconnect or listeners.onincoming, listeners.ondisconnect

	local accept = socket.accept

	--// public methods of the object //--

	local handler = { }

	handler.shutdown = function( ) end

	handler.ssl = function( )
		return sslctx ~= nil
	end
	handler.sslctx = function( )
		return sslctx
	end
	handler.remove = function( )
		connections = connections - 1
	end
	handler.close = function( )
		for _, handler in pairs( _socketlist ) do
			if handler.serverport == serverport then
				handler.disconnect( handler, "server closed" )
				handler:close( true )
			end
		end
		socket:close( )
		_sendlistlen = removesocket( _sendlist, socket, _sendlistlen )
		_readlistlen = removesocket( _readlist, socket, _readlistlen )
		_socketlist[ socket ] = nil
		handler = nil
		socket = nil
		--mem_free( )
		out_put "server.lua: closed server handler and removed sockets from list"
	end
	handler.ip = function( )
		return ip
	end
	handler.serverport = function( )
		return serverport
	end
	handler.socket = function( )
		return socket
	end
	handler.readbuffer = function( )
		if connections > maxconnections then
			out_put( "server.lua: refused new client connection: server full" )
			return false
		end
		local client, err = accept( socket )	-- try to accept
		if client then
			local ip, clientport = client:getpeername( )
			client:settimeout( 0 )
			local handler, client, err = wrapconnection( handler, listeners, client, ip, serverport, clientport, pattern, sslctx ) -- wrap new client socket
			if err then -- error while wrapping ssl socket
				return false
			end
			connections = connections + 1
			out_put( "server.lua: accepted new client connection from ", tostring(ip), ":", tostring(clientport), " to ", tostring(serverport))
			return dispatch( handler )
		elseif err then -- maybe timeout or something else
			out_put( "server.lua: error with new client connection: ", tostring(err) )
			return false
		end
	end
	return handler
end

wrapconnection = function( server, listeners, socket, ip, serverport, clientport, pattern, sslctx ) -- this function wraps a client to a handler object

	socket:settimeout( 0 )

	--// local import of socket methods //--

	local send
	local receive
	local shutdown

	--// private closures of the object //--

	local ssl

	local dispatch = listeners.onincoming
	local status = listeners.onstatus
	local disconnect = listeners.ondisconnect
	local drain = listeners.ondrain

	local bufferqueue = { } -- buffer array
	local bufferqueuelen = 0	-- end of buffer array

	local toclose
	local fatalerror
	local needtls

	local bufferlen = 0

	local noread = false
	local nosend = false

	local sendtraffic, readtraffic = 0, 0

	local maxsendlen = _maxsendlen
	local maxreadlen = _maxreadlen

	--// public methods of the object //--

	local handler = bufferqueue -- saves a table ^_^

	handler.dispatch = function( )
		return dispatch
	end
	handler.disconnect = function( )
		return disconnect
	end
	handler.setlistener = function( self, listeners )
		dispatch = listeners.onincoming
		disconnect = listeners.ondisconnect
		status = listeners.onstatus
		drain = listeners.ondrain
	end
	handler.getstats = function( )
		return readtraffic, sendtraffic
	end
	handler.ssl = function( )
		return ssl
	end
	handler.sslctx = function ( )
		return sslctx
	end
	handler.send = function( _, data, i, j )
		return send( socket, data, i, j )
	end
	handler.receive = function( pattern, prefix )
		return receive( socket, pattern, prefix )
	end
	handler.shutdown = function( pattern )
		return shutdown( socket, pattern )
	end
	handler.setoption = function (self, option, value)
		if socket.setoption then
			return socket:setoption(option, value);
		end
		return false, "setoption not implemented";
	end
	handler.close = function( self, forced )
		if not handler then return true; end
		_readlistlen = removesocket( _readlist, socket, _readlistlen )
		_readtimes[ handler ] = nil
		if bufferqueuelen ~= 0 then
			if not ( forced or fatalerror ) then
				handler.sendbuffer( )
				if bufferqueuelen ~= 0 then -- try again...
					if handler then
						handler.write = nil -- ... but no further writing allowed
					end
					toclose = true
					return false
				end
			else
				send( socket, table_concat( bufferqueue, "", 1, bufferqueuelen ), 1, bufferlen )	-- forced send
			end
		end
		if socket then
			_ = shutdown and shutdown( socket )
			socket:close( )
			_sendlistlen = removesocket( _sendlist, socket, _sendlistlen )
			_socketlist[ socket ] = nil
			socket = nil
		else
			out_put "server.lua: socket already closed"
		end
		if handler then
			_writetimes[ handler ] = nil
			_closelist[ handler ] = nil
			handler = nil
		end
		if server then
			server.remove( )
		end
		out_put "server.lua: closed client handler and removed socket from list"
		return true
	end
	handler.ip = function( )
		return ip
	end
	handler.serverport = function( )
		return serverport
	end
	handler.clientport = function( )
		return clientport
	end
	local write = function( self, data )
		bufferlen = bufferlen + string_len( data )
		if bufferlen > maxsendlen then
			_closelist[ handler ] = "send buffer exceeded"	 -- cannot close the client at the moment, have to wait to the end of the cycle
			handler.write = idfalse -- dont write anymore
			return false
		elseif socket and not _sendlist[ socket ] then
			_sendlistlen = addsocket(_sendlist, socket, _sendlistlen)
		end
		bufferqueuelen = bufferqueuelen + 1
		bufferqueue[ bufferqueuelen ] = data
		if handler then
			_writetimes[ handler ] = _writetimes[ handler ] or _currenttime
		end
		return true
	end
	handler.write = write
	handler.bufferqueue = function( self )
		return bufferqueue
	end
	handler.socket = function( self )
		return socket
	end
	handler.set_mode = function( self, new )
		pattern = new or pattern
		return pattern
	end
	handler.set_send = function ( self, newsend )
		send = newsend or send
		return send
	end
	handler.bufferlen = function( self, readlen, sendlen )
		maxsendlen = sendlen or maxsendlen
		maxreadlen = readlen or maxreadlen
		return bufferlen, maxreadlen, maxsendlen
	end
	--TODO: Deprecate
	handler.lock_read = function (self, switch)
		if switch == true then
			local tmp = _readlistlen
			_readlistlen = removesocket( _readlist, socket, _readlistlen )
			_readtimes[ handler ] = nil
			if _readlistlen ~= tmp then
				noread = true
			end
		elseif switch == false then
			if noread then
				noread = false
				_readlistlen = addsocket(_readlist, socket, _readlistlen)
				_readtimes[ handler ] = _currenttime
			end
		end
		return noread
	end
	handler.pause = function (self)
		return self:lock_read(true);
	end
	handler.resume = function (self)
		return self:lock_read(false);
	end
	handler.lock = function( self, switch )
		handler.lock_read (switch)
		if switch == true then
			handler.write = idfalse
			local tmp = _sendlistlen
			_sendlistlen = removesocket( _sendlist, socket, _sendlistlen )
			_writetimes[ handler ] = nil
			if _sendlistlen ~= tmp then
				nosend = true
			end
		elseif switch == false then
			handler.write = write
			if nosend then
				nosend = false
				write( "" )
			end
		end
		return noread, nosend
	end
	local _readbuffer = function( ) -- this function reads data
		local buffer, err, part = receive( socket, pattern )	-- receive buffer with "pattern"
		if not err or (err == "wantread" or err == "timeout") then -- received something
			local buffer = buffer or part or ""
			local len = string_len( buffer )
			if len > maxreadlen then
				disconnect( handler, "receive buffer exceeded" )
				handler:close( true )
				return false
			end
			local count = len * STAT_UNIT
			readtraffic = readtraffic + count
			_readtraffic = _readtraffic + count
			_readtimes[ handler ] = _currenttime
			--out_put( "server.lua: read data '", buffer:gsub("[^%w%p ]", "."), "', error: ", err )
			return dispatch( handler, buffer, err )
		else	-- connections was closed or fatal error
			out_put( "server.lua: client ", tostring(ip), ":", tostring(clientport), " read error: ", tostring(err) )
			fatalerror = true
			disconnect( handler, err )
		_ = handler and handler:close( )
			return false
		end
	end
	local _sendbuffer = function( ) -- this function sends data
		local succ, err, byte, buffer, count;
		local count;
		if socket then
			buffer = table_concat( bufferqueue, "", 1, bufferqueuelen )
			succ, err, byte = send( socket, buffer, 1, bufferlen )
			count = ( succ or byte or 0 ) * STAT_UNIT
			sendtraffic = sendtraffic + count
			_sendtraffic = _sendtraffic + count
			_ = _cleanqueue and clean( bufferqueue )
			--out_put( "server.lua: sended '", buffer, "', bytes: ", tostring(succ), ", error: ", tostring(err), ", part: ", tostring(byte), ", to: ", tostring(ip), ":", tostring(clientport) )
		else
			succ, err, count = false, "closed", 0;
		end
		if succ then	-- sending succesful
			bufferqueuelen = 0
			bufferlen = 0
			_sendlistlen = removesocket( _sendlist, socket, _sendlistlen ) -- delete socket from writelist
			_writetimes[ handler ] = nil
			if drain then
				drain(handler)
			end
			_ = needtls and handler:starttls(nil)
			_ = toclose and handler:close( )
			return true
		elseif byte and ( err == "timeout" or err == "wantwrite" ) then -- want write
			buffer = string_sub( buffer, byte + 1, bufferlen ) -- new buffer
			bufferqueue[ 1 ] = buffer	 -- insert new buffer in queue
			bufferqueuelen = 1
			bufferlen = bufferlen - byte
			_writetimes[ handler ] = _currenttime
			return true
		else	-- connection was closed during sending or fatal error
			out_put( "server.lua: client ", tostring(ip), ":", tostring(clientport), " write error: ", tostring(err) )
			fatalerror = true
			disconnect( handler, err )
			_ = handler and handler:close( )
			return false
		end
	end

	-- Set the sslctx
	local handshake;
	function handler.set_sslctx(self, new_sslctx)
		ssl = true
		sslctx = new_sslctx;
		local wrote
		local read
		handshake = coroutine_wrap( function( client ) -- create handshake coroutine
				local err
				for i = 1, _maxsslhandshake do
					_sendlistlen = ( wrote and removesocket( _sendlist, client, _sendlistlen ) ) or _sendlistlen
					_readlistlen = ( read and removesocket( _readlist, client, _readlistlen ) ) or _readlistlen
					read, wrote = nil, nil
					_, err = client:dohandshake( )
					if not err then
						out_put( "server.lua: ssl handshake done" )
						handler.readbuffer = _readbuffer	-- when handshake is done, replace the handshake function with regular functions
						handler.sendbuffer = _sendbuffer
						_ = status and status( handler, "ssl-handshake-complete" )
						_readlistlen = addsocket(_readlist, client, _readlistlen)
						return true
					else
						if err == "wantwrite" and not wrote then
							_sendlistlen = addsocket(_sendlist, client, _sendlistlen)
							wrote = true
						elseif err == "wantread" and not read then
							_readlistlen = addsocket(_readlist, client, _readlistlen)
							read = true
						else
							out_put( "server.lua: ssl handshake error: ", tostring(err) )
							break;
						end
						--coroutine_yield( handler, nil, err )	 -- handshake not finished
						coroutine_yield( )
					end
				end
				disconnect( handler, "ssl handshake failed" )
				_ = handler and handler:close( true )	 -- forced disconnect
				return false	-- handshake failed
			end
		)
	end
	if luasec then
		if sslctx then -- ssl?
			handler:set_sslctx(sslctx);
			out_put("server.lua: ", "starting ssl handshake")
			local err
			socket, err = ssl_wrap( socket, sslctx )	-- wrap socket
			if err then
				out_put( "server.lua: ssl error: ", tostring(err) )
				--mem_free( )
				return nil, nil, err	-- fatal error
			end
			socket:settimeout( 0 )
			handler.readbuffer = handshake
			handler.sendbuffer = handshake
			handshake( socket ) -- do handshake
			if not socket then
				return nil, nil, "ssl handshake failed";
			end
		else
			local sslctx;
			handler.starttls = function( self, _sslctx)
				if _sslctx then
					sslctx = _sslctx;
					handler:set_sslctx(sslctx);
				end
				if bufferqueuelen > 0 then
					out_put "server.lua: we need to do tls, but delaying until send buffer empty"
					needtls = true
					return
				end
				out_put( "server.lua: attempting to start tls on " .. tostring( socket ) )
				local oldsocket, err = socket
				socket, err = ssl_wrap( socket, sslctx )	-- wrap socket
				--out_put( "server.lua: sslwrapped socket is " .. tostring( socket ) )
				if err then
					out_put( "server.lua: error while starting tls on client: ", tostring(err) )
					return nil, err -- fatal error
				end

				socket:settimeout( 0 )
	
				-- add the new socket to our system
	
				send = socket.send
				receive = socket.receive
				shutdown = id

				_socketlist[ socket ] = handler
				_readlistlen = addsocket(_readlist, socket, _readlistlen)

				-- remove traces of the old socket

				_readlistlen = removesocket( _readlist, oldsocket, _readlistlen )
				_sendlistlen = removesocket( _sendlist, oldsocket, _sendlistlen )
				_socketlist[ oldsocket ] = nil

				handler.starttls = nil
				needtls = nil

				-- Secure now
				ssl = true

				handler.readbuffer = handshake
				handler.sendbuffer = handshake
				handshake( socket ) -- do handshake
			end
			handler.readbuffer = _readbuffer
			handler.sendbuffer = _sendbuffer
		end
	else
		handler.readbuffer = _readbuffer
		handler.sendbuffer = _sendbuffer
	end
	send = socket.send
	receive = socket.receive
	shutdown = ( ssl and id ) or socket.shutdown

	_socketlist[ socket ] = handler
	_readlistlen = addsocket(_readlist, socket, _readlistlen)
	return handler, socket
end

id = function( )
end

idfalse = function( )
	return false
end

addsocket = function( list, socket, len )
	if not list[ socket ] then
		len = len + 1
		list[ len ] = socket
		list[ socket ] = len
	end
	return len;
end

removesocket = function( list, socket, len )	-- this function removes sockets from a list ( copied from copas )
	local pos = list[ socket ]
	if pos then
		list[ socket ] = nil
		local last = list[ len ]
		list[ len ] = nil
		if last ~= socket then
			list[ last ] = pos
			list[ pos ] = last
		end
		return len - 1
	end
	return len
end

closesocket = function( socket )
	_sendlistlen = removesocket( _sendlist, socket, _sendlistlen )
	_readlistlen = removesocket( _readlist, socket, _readlistlen )
	_socketlist[ socket ] = nil
	socket:close( )
	--mem_free( )
end

local function link(sender, receiver, buffersize)
	local sender_locked;
	local _sendbuffer = receiver.sendbuffer;
	function receiver.sendbuffer()
		_sendbuffer();
		if sender_locked and receiver.bufferlen() < buffersize then
			sender:lock_read(false); -- Unlock now
			sender_locked = nil;
		end
	end
	
	local _readbuffer = sender.readbuffer;
	function sender.readbuffer()
		_readbuffer();
		if not sender_locked and receiver.bufferlen() >= buffersize then
			sender_locked = true;
			sender:lock_read(true);
		end
	end
end

----------------------------------// PUBLIC //--

addserver = function( addr, port, listeners, pattern, sslctx ) -- this function provides a way for other scripts to reg a server
	local err
	if type( listeners ) ~= "table" then
		err = "invalid listener table"
	end
	if type( port ) ~= "number" or not ( port >= 0 and port <= 65535 ) then
		err = "invalid port"
	elseif _server[ addr..":"..port ] then
		err = "listeners on '[" .. addr .. "]:" .. port .. "' already exist"
	elseif sslctx and not luasec then
		err = "luasec not found"
	end
	if err then
		out_error( "server.lua, [", addr, "]:", port, ": ", err )
		return nil, err
	end
	addr = addr or "*"
	local server, err = socket_bind( addr, port )
	if err then
		out_error( "server.lua, [", addr, "]:", port, ": ", err )
		return nil, err
	end
	local handler, err = wrapserver( listeners, server, addr, port, pattern, sslctx, _maxclientsperserver ) -- wrap new server socket
	if not handler then
		server:close( )
		return nil, err
	end
	server:settimeout( 0 )
	_readlistlen = addsocket(_readlist, server, _readlistlen)
	_server[ addr..":"..port ] = handler
	_socketlist[ server ] = handler
	out_put( "server.lua: new "..(sslctx and "ssl " or "").."server listener on '[", addr, "]:", port, "'" )
	return handler
end

getserver = function ( addr, port )
	return _server[ addr..":"..port ];
end

removeserver = function( addr, port )
	local handler = _server[ addr..":"..port ]
	if not handler then
		return nil, "no server found on '[" .. addr .. "]:" .. tostring( port ) .. "'"
	end
	handler:close( )
	_server[ addr..":"..port ] = nil
	return true
end

closeall = function( )
	for _, handler in pairs( _socketlist ) do
		handler:close( )
		_socketlist[ _ ] = nil
	end
	_readlistlen = 0
	_sendlistlen = 0
	_timerlistlen = 0
	_server = { }
	_readlist = { }
	_sendlist = { }
	_timerlist = { }
	_socketlist = { }
	--mem_free( )
end

getsettings = function( )
	return	_selecttimeout, _sleeptime, _maxsendlen, _maxreadlen, _checkinterval, _sendtimeout, _readtimeout, _cleanqueue, _maxclientsperserver, _maxsslhandshake
end

changesettings = function( new )
	if type( new ) ~= "table" then
		return nil, "invalid settings table"
	end
	_selecttimeout = tonumber( new.timeout ) or _selecttimeout
	_sleeptime = tonumber( new.sleeptime ) or _sleeptime
	_maxsendlen = tonumber( new.maxsendlen ) or _maxsendlen
	_maxreadlen = tonumber( new.maxreadlen ) or _maxreadlen
	_checkinterval = tonumber( new.checkinterval ) or _checkinterval
	_sendtimeout = tonumber( new.sendtimeout ) or _sendtimeout
	_readtimeout = tonumber( new.readtimeout ) or _readtimeout
	_cleanqueue = new.cleanqueue
	_maxclientsperserver = new._maxclientsperserver or _maxclientsperserver
	_maxsslhandshake = new._maxsslhandshake or _maxsslhandshake
	return true
end

addtimer = function( listener )
	if type( listener ) ~= "function" then
		return nil, "invalid listener function"
	end
	_timerlistlen = _timerlistlen + 1
	_timerlist[ _timerlistlen ] = listener
	return true
end

stats = function( )
	return _readtraffic, _sendtraffic, _readlistlen, _sendlistlen, _timerlistlen
end

local quitting;

setquitting = function (quit)
	quitting = not not quit;
end

loop = function(once) -- this is the main loop of the program
	if quitting then return "quitting"; end
	if once then quitting = "once"; end
	local next_timer_time = math_huge;
	repeat
		local read, write, err = socket_select( _readlist, _sendlist, math_min(_selecttimeout, next_timer_time) )
		for i, socket in ipairs( write ) do -- send data waiting in writequeues
			local handler = _socketlist[ socket ]
			if handler then
				handler.sendbuffer( )
			else
				closesocket( socket )
				out_put "server.lua: found no handler and closed socket (writelist)"	-- this should not happen
			end
		end
		for i, socket in ipairs( read ) do -- receive data
			local handler = _socketlist[ socket ]
			if handler then
				handler.readbuffer( )
			else
				closesocket( socket )
				out_put "server.lua: found no handler and closed socket (readlist)" -- this can happen
			end
		end
		for handler, err in pairs( _closelist ) do
			handler.disconnect( )( handler, err )
			handler:close( true )	 -- forced disconnect
		end
		clean( _closelist )
		_currenttime = luasocket_gettime( )
		if _currenttime - _timer >= math_min(next_timer_time, 1) then
			next_timer_time = math_huge;
			for i = 1, _timerlistlen do
				local t = _timerlist[ i ]( _currenttime ) -- fire timers
				if t then next_timer_time = math_min(next_timer_time, t); end
			end
			_timer = _currenttime
		else
			next_timer_time = next_timer_time - (_currenttime - _timer);
		end
		socket_sleep( _sleeptime ) -- wait some time
		--collectgarbage( )
	until quitting;
	if once and quitting == "once" then quitting = nil; return; end
	return "quitting"
end

step = function ()
	return loop(true);
end

local function get_backend()
	return "select";
end

--// EXPERIMENTAL //--

local wrapclient = function( socket, ip, serverport, listeners, pattern, sslctx )
	local handler = wrapconnection( nil, listeners, socket, ip, serverport, "clientport", pattern, sslctx )
	_socketlist[ socket ] = handler
	_sendlistlen = addsocket(_sendlist, socket, _sendlistlen)
	if listeners.onconnect then
		-- When socket is writeable, call onconnect
		local _sendbuffer = handler.sendbuffer;
		handler.sendbuffer = function ()
			handler.sendbuffer = _sendbuffer;
			listeners.onconnect(handler);
			-- If there was data with the incoming packet, handle it now.
			if #handler:bufferqueue() > 0 then
				return _sendbuffer();
			end
		end
	end
	return handler, socket
end

local addclient = function( address, port, listeners, pattern, sslctx )
	local client, err = luasocket.tcp( )
	if err then
		return nil, err
	end
	client:settimeout( 0 )
	_, err = client:connect( address, port )
	if err then -- try again
		local handler = wrapclient( client, address, port, listeners )
	else
		wrapconnection( nil, listeners, client, address, port, "clientport", pattern, sslctx )
	end
end

--// EXPERIMENTAL //--

----------------------------------// BEGIN //--

use "setmetatable" ( _socketlist, { __mode = "k" } )
use "setmetatable" ( _readtimes, { __mode = "k" } )
use "setmetatable" ( _writetimes, { __mode = "k" } )

_timer = luasocket_gettime( )
_starttime = luasocket_gettime( )

addtimer( function( )
		local difftime = os_difftime( _currenttime - _starttime )
		if difftime > _checkinterval then
			_starttime = _currenttime
			for handler, timestamp in pairs( _writetimes ) do
				if os_difftime( _currenttime - timestamp ) > _sendtimeout then
					--_writetimes[ handler ] = nil
					handler.disconnect( )( handler, "send timeout" )
					handler:close( true )	 -- forced disconnect
				end
			end
			for handler, timestamp in pairs( _readtimes ) do
				if os_difftime( _currenttime - timestamp ) > _readtimeout then
					--_readtimes[ handler ] = nil
					handler.disconnect( )( handler, "read timeout" )
					handler:close( )	-- forced disconnect?
				end
			end
		end
	end
)

local function setlogger(new_logger)
	local old_logger = log;
	if new_logger then
		log = new_logger;
	end
	return old_logger;
end

----------------------------------// PUBLIC INTERFACE //--

return {

	addclient = addclient,
	wrapclient = wrapclient,
	
	loop = loop,
	link = link,
	step = step,
	stats = stats,
	closeall = closeall,
	addtimer = addtimer,
	addserver = addserver,
	getserver = getserver,
	setlogger = setlogger,
	getsettings = getsettings,
	setquitting = setquitting,
	removeserver = removeserver,
	get_backend = get_backend,
	changesettings = changesettings,
}
 end)
package.preload['util.xmppstream'] = (function (...)
-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--


local lxp = require "lxp";
local st = require "util.stanza";
local stanza_mt = st.stanza_mt;

local tostring = tostring;
local t_insert = table.insert;
local t_concat = table.concat;
local t_remove = table.remove;
local setmetatable = setmetatable;

local default_log = require "util.logger".init("xmppstream");

-- COMPAT: w/LuaExpat 1.1.0
local lxp_supports_doctype = pcall(lxp.new, { StartDoctypeDecl = false });

if not lxp_supports_doctype then
	default_log("warn", "The version of LuaExpat on your system leaves Prosody "
		.."vulnerable to denial-of-service attacks. You should upgrade to "
		.."LuaExpat 1.1.1 or higher as soon as possible. See "
		.."http://prosody.im/doc/depends#luaexpat for more information.");
end

local error = error;

module "xmppstream"

local new_parser = lxp.new;

local ns_prefixes = {
	["http://www.w3.org/XML/1998/namespace"] = "xml";
};

local xmlns_streams = "http://etherx.jabber.org/streams";

local ns_separator = "\1";
local ns_pattern = "^([^"..ns_separator.."]*)"..ns_separator.."?(.*)$";

_M.ns_separator = ns_separator;
_M.ns_pattern = ns_pattern;

function new_sax_handlers(session, stream_callbacks)
	local xml_handlers = {};
	
	local log = session.log or default_log;
	
	local cb_streamopened = stream_callbacks.streamopened;
	local cb_streamclosed = stream_callbacks.streamclosed;
	local cb_error = stream_callbacks.error or function(session, e) error("XML stream error: "..tostring(e)); end;
	local cb_handlestanza = stream_callbacks.handlestanza;
	
	local stream_ns = stream_callbacks.stream_ns or xmlns_streams;
	local stream_tag = stream_callbacks.stream_tag or "stream";
	if stream_ns ~= "" then
		stream_tag = stream_ns..ns_separator..stream_tag;
	end
	local stream_error_tag = stream_ns..ns_separator..(stream_callbacks.error_tag or "error");
	
	local stream_default_ns = stream_callbacks.default_ns;
	
	local stack = {};
	local chardata, stanza = {};
	local non_streamns_depth = 0;
	function xml_handlers:StartElement(tagname, attr)
		if stanza and #chardata > 0 then
			-- We have some character data in the buffer
			t_insert(stanza, t_concat(chardata));
			chardata = {};
		end
		local curr_ns,name = tagname:match(ns_pattern);
		if name == "" then
			curr_ns, name = "", curr_ns;
		end

		if curr_ns ~= stream_default_ns or non_streamns_depth > 0 then
			attr.xmlns = curr_ns;
			non_streamns_depth = non_streamns_depth + 1;
		end
		
		-- FIXME !!!!!
		for i=1,#attr do
			local k = attr[i];
			attr[i] = nil;
			local ns, nm = k:match(ns_pattern);
			if nm ~= "" then
				ns = ns_prefixes[ns];
				if ns then
					attr[ns..":"..nm] = attr[k];
					attr[k] = nil;
				end
			end
		end
		
		if not stanza then --if we are not currently inside a stanza
			if session.notopen then
				if tagname == stream_tag then
					non_streamns_depth = 0;
					if cb_streamopened then
						cb_streamopened(session, attr);
					end
				else
					-- Garbage before stream?
					cb_error(session, "no-stream");
				end
				return;
			end
			if curr_ns == "jabber:client" and name ~= "iq" and name ~= "presence" and name ~= "message" then
				cb_error(session, "invalid-top-level-element");
			end
			
			stanza = setmetatable({ name = name, attr = attr, tags = {} }, stanza_mt);
		else -- we are inside a stanza, so add a tag
			t_insert(stack, stanza);
			local oldstanza = stanza;
			stanza = setmetatable({ name = name, attr = attr, tags = {} }, stanza_mt);
			t_insert(oldstanza, stanza);
			t_insert(oldstanza.tags, stanza);
		end
	end
	function xml_handlers:CharacterData(data)
		if stanza then
			t_insert(chardata, data);
		end
	end
	function xml_handlers:EndElement(tagname)
		if non_streamns_depth > 0 then
			non_streamns_depth = non_streamns_depth - 1;
		end
		if stanza then
			if #chardata > 0 then
				-- We have some character data in the buffer
				t_insert(stanza, t_concat(chardata));
				chardata = {};
			end
			-- Complete stanza
			if #stack == 0 then
				if tagname ~= stream_error_tag then
					cb_handlestanza(session, stanza);
				else
					cb_error(session, "stream-error", stanza);
				end
				stanza = nil;
			else
				stanza = t_remove(stack);
			end
		else
			if tagname == stream_tag then
				if cb_streamclosed then
					cb_streamclosed(session);
				end
			else
				local curr_ns,name = tagname:match(ns_pattern);
				if name == "" then
					curr_ns, name = "", curr_ns;
				end
				cb_error(session, "parse-error", "unexpected-element-close", name);
			end
			stanza, chardata = nil, {};
			stack = {};
		end
	end

	local function restricted_handler(parser)
		cb_error(session, "parse-error", "restricted-xml", "Restricted XML, see RFC 6120 section 11.1.");
		if not parser.stop or not parser:stop() then
			error("Failed to abort parsing");
		end
	end
	
	if lxp_supports_doctype then
		xml_handlers.StartDoctypeDecl = restricted_handler;
	end
	xml_handlers.Comment = restricted_handler;
	xml_handlers.ProcessingInstruction = restricted_handler;
	
	local function reset()
		stanza, chardata = nil, {};
		stack = {};
	end
	
	local function set_session(stream, new_session)
		session = new_session;
		log = new_session.log or default_log;
	end
	
	return xml_handlers, { reset = reset, set_session = set_session };
end

function new(session, stream_callbacks)
	local handlers, meta = new_sax_handlers(session, stream_callbacks);
	local parser = new_parser(handlers, ns_separator);
	local parse = parser.parse;

	return {
		reset = function ()
			parser = new_parser(handlers, ns_separator);
			parse = parser.parse;
			meta.reset();
		end,
		feed = function (self, data)
			return parse(parser, data);
		end,
		set_session = meta.set_session;
	};
end

return _M;
 end)
package.preload['util.jid'] = (function (...)
-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--



local match = string.match;
local nodeprep = require "util.encodings".stringprep.nodeprep;
local nameprep = require "util.encodings".stringprep.nameprep;
local resourceprep = require "util.encodings".stringprep.resourceprep;

module "jid"

local function _split(jid)
	if not jid then return; end
	local node, nodepos = match(jid, "^([^@/]+)@()");
	local host, hostpos = match(jid, "^([^@/]+)()", nodepos)
	if node and not host then return nil, nil, nil; end
	local resource = match(jid, "^/(.+)$", hostpos);
	if (not host) or ((not resource) and #jid >= hostpos) then return nil, nil, nil; end
	return node, host, resource;
end
split = _split;

function bare(jid)
	local node, host = _split(jid);
	if node and host then
		return node.."@"..host;
	end
	return host;
end

local function _prepped_split(jid)
	local node, host, resource = _split(jid);
	if host then
		host = nameprep(host);
		if not host then return; end
		if node then
			node = nodeprep(node);
			if not node then return; end
		end
		if resource then
			resource = resourceprep(resource);
			if not resource then return; end
		end
		return node, host, resource;
	end
end
prepped_split = _prepped_split;

function prep(jid)
	local node, host, resource = _prepped_split(jid);
	if host then
		if node then
			host = node .. "@" .. host;
		end
		if resource then
			host = host .. "/" .. resource;
		end
	end
	return host;
end

function join(node, host, resource)
	if node and host and resource then
		return node.."@"..host.."/"..resource;
	elseif node and host then
		return node.."@"..host;
	elseif host and resource then
		return host.."/"..resource;
	elseif host then
		return host;
	end
	return nil; -- Invalid JID
end

function compare(jid, acl)
	-- compare jid to single acl rule
	-- TODO compare to table of rules?
	local jid_node, jid_host, jid_resource = _split(jid);
	local acl_node, acl_host, acl_resource = _split(acl);
	if ((acl_node ~= nil and acl_node == jid_node) or acl_node == nil) and
		((acl_host ~= nil and acl_host == jid_host) or acl_host == nil) and
		((acl_resource ~= nil and acl_resource == jid_resource) or acl_resource == nil) then
		return true
	end
	return false
end

return _M;
 end)
package.preload['util.events'] = (function (...)
-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--


local pairs = pairs;
local t_insert = table.insert;
local t_sort = table.sort;
local setmetatable = setmetatable;
local next = next;

module "events"

function new()
	local handlers = {};
	local event_map = {};
	local function _rebuild_index(handlers, event)
		local _handlers = event_map[event];
		if not _handlers or next(_handlers) == nil then return; end
		local index = {};
		for handler in pairs(_handlers) do
			t_insert(index, handler);
		end
		t_sort(index, function(a, b) return _handlers[a] > _handlers[b]; end);
		handlers[event] = index;
		return index;
	end;
	setmetatable(handlers, { __index = _rebuild_index });
	local function add_handler(event, handler, priority)
		local map = event_map[event];
		if map then
			map[handler] = priority or 0;
		else
			map = {[handler] = priority or 0};
			event_map[event] = map;
		end
		handlers[event] = nil;
	end;
	local function remove_handler(event, handler)
		local map = event_map[event];
		if map then
			map[handler] = nil;
			handlers[event] = nil;
			if next(map) == nil then
				event_map[event] = nil;
			end
		end
	end;
	local function add_handlers(handlers)
		for event, handler in pairs(handlers) do
			add_handler(event, handler);
		end
	end;
	local function remove_handlers(handlers)
		for event, handler in pairs(handlers) do
			remove_handler(event, handler);
		end
	end;
	local function fire_event(event, ...)
		local h = handlers[event];
		if h then
			for i=1,#h do
				local ret = h[i](...);
				if ret ~= nil then return ret; end
			end
		end
	end;
	return {
		add_handler = add_handler;
		remove_handler = remove_handler;
		add_handlers = add_handlers;
		remove_handlers = remove_handlers;
		fire_event = fire_event;
		_handlers = handlers;
		_event_map = event_map;
	};
end

return _M;
 end)
package.preload['util.dataforms'] = (function (...)
-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local setmetatable = setmetatable;
local pairs, ipairs = pairs, ipairs;
local tostring, type = tostring, type;
local t_concat = table.concat;
local st = require "util.stanza";

module "dataforms"

local xmlns_forms = 'jabber:x:data';

local form_t = {};
local form_mt = { __index = form_t };

function new(layout)
	return setmetatable(layout, form_mt);
end

function form_t.form(layout, data, formtype)
	local form = st.stanza("x", { xmlns = xmlns_forms, type = formtype or "form" });
	if layout.title then
		form:tag("title"):text(layout.title):up();
	end
	if layout.instructions then
		form:tag("instructions"):text(layout.instructions):up();
	end
	for n, field in ipairs(layout) do
		local field_type = field.type or "text-single";
		-- Add field tag
		form:tag("field", { type = field_type, var = field.name, label = field.label });

		local value = (data and data[field.name]) or field.value;
		
		if value then
			-- Add value, depending on type
			if field_type == "hidden" then
				if type(value) == "table" then
					-- Assume an XML snippet
					form:tag("value")
						:add_child(value)
						:up();
				else
					form:tag("value"):text(tostring(value)):up();
				end
			elseif field_type == "boolean" then
				form:tag("value"):text((value and "1") or "0"):up();
			elseif field_type == "fixed" then
				
			elseif field_type == "jid-multi" then
				for _, jid in ipairs(value) do
					form:tag("value"):text(jid):up();
				end
			elseif field_type == "jid-single" then
				form:tag("value"):text(value):up();
			elseif field_type == "text-single" or field_type == "text-private" then
				form:tag("value"):text(value):up();
			elseif field_type == "text-multi" then
				-- Split into multiple <value> tags, one for each line
				for line in value:gmatch("([^\r\n]+)\r?\n*") do
					form:tag("value"):text(line):up();
				end
			elseif field_type == "list-single" then
				local has_default = false;
				if type(value) == "string" then
					form:tag("value"):text(value):up();
				else
					for _, val in ipairs(value) do
						if type(val) == "table" then
							form:tag("option", { label = val.label }):tag("value"):text(val.value):up():up();
							if val.default and (not has_default) then
								form:tag("value"):text(val.value):up();
								has_default = true;
							end
						else
							form:tag("option", { label= val }):tag("value"):text(tostring(val)):up():up();
						end
					end
				end
			elseif field_type == "list-multi" then
				for _, val in ipairs(value) do
					if type(val) == "table" then
						form:tag("option", { label = val.label }):tag("value"):text(val.value):up():up();
						if val.default then
							form:tag("value"):text(val.value):up();
						end
					else
						form:tag("option", { label= val }):tag("value"):text(tostring(val)):up():up();
					end
				end
			end
		end
		
		if field.required then
			form:tag("required"):up();
		end
		
		-- Jump back up to list of fields
		form:up();
	end
	return form;
end

local field_readers = {};

function form_t.data(layout, stanza)
	local data = {};
	
	for field_tag in stanza:childtags() do
		local field_type;
		for n, field in ipairs(layout) do
			if field.name == field_tag.attr.var then
				field_type = field.type;
				break;
			end
		end
		
		local reader = field_readers[field_type];
		if reader then
			data[field_tag.attr.var] = reader(field_tag);
		end
		
	end
	return data;
end

field_readers["text-single"] = 
	function (field_tag)
		local value = field_tag:child_with_name("value");
		if value then
			return value[1];
		end
	end

field_readers["text-private"] = 
	field_readers["text-single"];

field_readers["jid-single"] =
	field_readers["text-single"];

field_readers["jid-multi"] = 
	function (field_tag)
		local result = {};
		for value_tag in field_tag:childtags() do
			if value_tag.name == "value" then
				result[#result+1] = value_tag[1];
			end
		end
		return result;
	end

field_readers["text-multi"] = 
	function (field_tag)
		local result = {};
		for value_tag in field_tag:childtags() do
			if value_tag.name == "value" then
				result[#result+1] = value_tag[1];
			end
		end
		return t_concat(result, "\n");
	end

field_readers["list-single"] =
	field_readers["text-single"];

field_readers["list-multi"] =
	function (field_tag)
		local result = {};
		for value_tag in field_tag:childtags() do
			if value_tag.name == "value" then
				result[#result+1] = value_tag[1];
			end
		end
		return result;
	end

field_readers["boolean"] = 
	function (field_tag)
		local value = field_tag:child_with_name("value");
		if value then
			if value[1] == "1" or value[1] == "true" then
				return true;
			else
				return false;
			end
		end		
	end

field_readers["hidden"] = 
	function (field_tag)
		local value = field_tag:child_with_name("value");
		if value then
			return value[1];
		end
	end
	
return _M;


--[=[

Layout:
{

	title = "MUC Configuration",
	instructions = [[Use this form to configure options for this MUC room.]],

	{ name = "FORM_TYPE", type = "hidden", required = true };
	{ name = "field-name", type = "field-type", required = false };
}


--]=]
 end)
package.preload['util.serialization'] = (function (...)
-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local string_rep = string.rep;
local type = type;
local tostring = tostring;
local t_insert = table.insert;
local t_concat = table.concat;
local error = error;
local pairs = pairs;
local next = next;

local loadstring = loadstring;
local setfenv = setfenv;
local pcall = pcall;

local debug_traceback = debug.traceback;
local log = require "util.logger".init("serialization");
module "serialization"

local indent = function(i)
	return string_rep("\t", i);
end
local function basicSerialize (o)
	if type(o) == "number" or type(o) == "boolean" then
		-- no need to check for NaN, as that's not a valid table index
		if o == 1/0 then return "(1/0)";
		elseif o == -1/0 then return "(-1/0)";
		else return tostring(o); end
	else -- assume it is a string -- FIXME make sure it's a string. throw an error otherwise.
		return (("%q"):format(tostring(o)):gsub("\\\n", "\\n"));
	end
end
local function _simplesave(o, ind, t, func)
	if type(o) == "number" then
		if o ~= o then func(t, "(0/0)");
		elseif o == 1/0 then func(t, "(1/0)");
		elseif o == -1/0 then func(t, "(-1/0)");
		else func(t, tostring(o)); end
	elseif type(o) == "string" then
		func(t, (("%q"):format(o):gsub("\\\n", "\\n")));
	elseif type(o) == "table" then
		if next(o) ~= nil then
			func(t, "{\n");
			for k,v in pairs(o) do
				func(t, indent(ind));
				func(t, "[");
				func(t, basicSerialize(k));
				func(t, "] = ");
				if ind == 0 then
					_simplesave(v, 0, t, func);
				else
					_simplesave(v, ind+1, t, func);
				end
				func(t, ";\n");
			end
			func(t, indent(ind-1));
			func(t, "}");
		else
			func(t, "{}");
		end
	elseif type(o) == "boolean" then
		func(t, (o and "true" or "false"));
	else
		log("error", "cannot serialize a %s: %s", type(o), debug_traceback())
		func(t, "nil");
	end
end

function append(t, o)
	_simplesave(o, 1, t, t.write or t_insert);
	return t;
end

function serialize(o)
	return t_concat(append({}, o));
end

function deserialize(str)
	if type(str) ~= "string" then return nil; end
	str = "return "..str;
	local f, err = loadstring(str, "@data");
	if not f then return nil, err; end
	setfenv(f, {});
	local success, ret = pcall(f);
	if not success then return nil, ret; end
	return ret;
end

return _M;
 end)
package.preload['verse.plugins.presence'] = (function (...)
function verse.plugins.presence(stream)
	stream.last_presence = nil;

	stream:hook("presence-out", function (presence)
		if not presence.attr.to then
			stream.last_presence = presence; -- Cache non-directed presence
		end
	end, 1);

	function stream:resend_presence()
		if last_presence then
			stream:send(last_presence);
		end
	end

	function stream:set_status(opts)
		local p = verse.presence();
		if type(opts) == "table" then
			if opts.show then
				p:tag("show"):text(opts.show):up();
			end
			if opts.prio then
				p:tag("priority"):text(tostring(opts.prio)):up();
			end
			if opts.msg then
				p:tag("status"):text(opts.msg):up();
			end
		end
		-- TODO maybe use opts as prio if it's a int,
		-- or as show or status if it's a string?

		stream:send(p);
	end
end
 end)
package.preload['verse.plugins.groupchat'] = (function (...)
local events = require "events";

local room_mt = {};
room_mt.__index = room_mt;

local xmlns_delay = "urn:xmpp:delay";
local xmlns_muc = "http://jabber.org/protocol/muc";

function verse.plugins.groupchat(stream)
	stream:add_plugin("presence")
	stream.rooms = {};
	
	stream:hook("stanza", function (stanza)
		local room_jid = jid.bare(stanza.attr.from);
		if not room_jid then return end
		local room = stream.rooms[room_jid]
		if not room and stanza.attr.to and room_jid then
			room = stream.rooms[stanza.attr.to.." "..room_jid]
		end
		if room and room.opts.source and stanza.attr.to ~= room.opts.source then return end
		if room then
			local nick = select(3, jid.split(stanza.attr.from));
			local body = stanza:get_child("body");
			local delay = stanza:get_child("delay", xmlns_delay);
			local event = {
				room_jid = room_jid;
				room = room;
				sender = room.occupants[nick];
				nick = nick;
				body = (body and body:get_text()) or nil;
				stanza = stanza;
				delay = (delay and delay.attr.stamp);
			};
			local ret = room:event(stanza.name, event);
			return ret or (stanza.name == "message") or nil;
		end
	end, 500);
	
	function stream:join_room(jid, nick, opts)
		if not nick then
			return false, "no nickname supplied"
		end
		opts = opts or {};
		local room = setmetatable({
			stream = stream, jid = jid, nick = nick,
			subject = nil,
			occupants = {},
			opts = opts,
			events = events.new()
		}, room_mt);
		if opts.source then
			self.rooms[opts.source.." "..jid] = room;
		else
			self.rooms[jid] = room;
		end
		local occupants = room.occupants;
		room:hook("presence", function (presence)
			local nick = presence.nick or nick;
			if not occupants[nick] and presence.stanza.attr.type ~= "unavailable" then
				occupants[nick] = {
					nick = nick;
					jid = presence.stanza.attr.from;
					presence = presence.stanza;
				};
				local x = presence.stanza:get_child("x", xmlns_muc .. "#user");
				if x then
					local x_item = x:get_child("item");
					if x_item and x_item.attr then
						occupants[nick].real_jid    = x_item.attr.jid;
						occupants[nick].affiliation = x_item.attr.affiliation;
						occupants[nick].role        = x_item.attr.role;
					end
					--TODO Check for status 100?
				end
				if nick == room.nick then
					room.stream:event("groupchat/joined", room);
				else
					room:event("occupant-joined", occupants[nick]);
				end
			elseif occupants[nick] and presence.stanza.attr.type == "unavailable" then
				if nick == room.nick then
					room.stream:event("groupchat/left", room);
					if room.opts.source then
						self.rooms[room.opts.source.." "..jid] = nil;
					else
						self.rooms[jid] = nil;
					end
				else
					occupants[nick].presence = presence.stanza;
					room:event("occupant-left", occupants[nick]);
					occupants[nick] = nil;
				end
			end
		end);
		room:hook("message", function(msg)
			local subject = msg.stanza:get_child_text("subject");
			if not subject then return end
			subject = #subject > 0 and subject or nil;
			if subject ~= room.subject then
				local old_subject = room.subject;
				room.subject = subject;
				return self:event("subject-changed", { from = old_subject, to = subject, by = msg.sender });
			end
		end, 2000);
		local join_st = verse.presence():tag("x",{xmlns = xmlns_muc}):reset();
		self:event("pre-groupchat/joining", join_st);
		room:send(join_st)
		self:event("groupchat/joining", room);
		return room;
	end

	stream:hook("presence-out", function(presence)
		if not presence.attr.to then
			for _, room in pairs(stream.rooms) do
				room:send(presence);
			end
			presence.attr.to = nil;
		end
	end);
end

function room_mt:send(stanza)
	if stanza.name == "message" and not stanza.attr.type then
		stanza.attr.type = "groupchat";
	end
	if stanza.name == "presence" then
		stanza.attr.to = self.jid .."/"..self.nick;
	end
	if stanza.attr.type == "groupchat" or not stanza.attr.to then
		stanza.attr.to = self.jid;
	end
	if self.opts.source then
		stanza.attr.from = self.opts.source
	end
	self.stream:send(stanza);
end

function room_mt:send_message(text)
	self:send(verse.message():tag("body"):text(text));
end

function room_mt:set_subject(text)
	self:send(verse.message():tag("subject"):text(text));
end

function room_mt:leave(message)
	self.stream:event("groupchat/leaving", self);
	self:send(verse.presence({type="unavailable"}));
end

function room_mt:admin_set(nick, what, value, reason)
	self:send(verse.iq({type="set"})
		:query(xmlns_muc .. "#admin")
			:tag("item", {nick = nick, [what] = value})
				:tag("reason"):text(reason or ""));
end

function room_mt:set_role(nick, role, reason)
	self:admin_set(nick, "role", role, reason);
end

function room_mt:set_affiliation(nick, affiliation, reason)
	self:admin_set(nick, "affiliation", affiliation, reason);
end

function room_mt:kick(nick, reason)
	self:set_role(nick, "none", reason);
end

function room_mt:ban(nick, reason)
	self:set_affiliation(nick, "outcast", reason);
end

function room_mt:event(name, arg)
	self.stream:debug("Firing room event: %s", name);
	return self.events.fire_event(name, arg);
end

function room_mt:hook(name, callback, priority)
	return self.events.add_handler(name, callback, priority);
end
 end)
package.preload['net.httpclient_listener'] = (function (...)
-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local log = require "util.logger".init("httpclient_listener");

local connlisteners_register = require "net.connlisteners".register;

local requests = {}; -- Open requests
local buffers = {}; -- Buffers of partial lines

local httpclient = { default_port = 80, default_mode = "*a" };

function httpclient.onincoming(conn, data)
	local request = requests[conn];

	if not request then
		log("warn", "Received response from connection %s with no request attached!", tostring(conn));
		return;
	end

	if data and request.reader then
		request:reader(data);
	end
end

function httpclient.ondisconnect(conn, err)
	local request = requests[conn];
	if request and err ~= "closed" then
		request:reader(nil);
	end
	requests[conn] = nil;
end

function httpclient.register_request(conn, req)
	log("debug", "Attaching request %s to connection %s", tostring(req.id or req), tostring(conn));
	requests[conn] = req;
end

connlisteners_register("httpclient", httpclient);
 end)
package.preload['net.connlisteners'] = (function (...)
-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--



local listeners_dir = (CFG_SOURCEDIR or ".").."/net/";
local server = require "net.server";
local log = require "util.logger".init("connlisteners");
local tostring = tostring;
local type = type
local ipairs = ipairs

local dofile, xpcall, error =
      dofile, xpcall, error

local debug_traceback = debug.traceback;

module "connlisteners"

local listeners = {};

function register(name, listener)
	if listeners[name] and listeners[name] ~= listener then
		log("debug", "Listener %s is already registered, not registering any more", name);
		return false;
	end
	listeners[name] = listener;
	log("debug", "Registered connection listener %s", name);
	return true;
end

function deregister(name)
	listeners[name] = nil;
end

function get(name)
	local h = listeners[name];
	if not h then
		local ok, ret = xpcall(function() dofile(listeners_dir..name:gsub("[^%w%-]", "_").."_listener.lua") end, debug_traceback);
		if not ok then
			log("error", "Error while loading listener '%s': %s", tostring(name), tostring(ret));
			return nil, ret;
		end
		h = listeners[name];
	end
	return h;
end

function start(name, udata)
	local h, err = get(name);
	if not h then
		error("No such connection module: "..name.. (err and (" ("..err..")") or ""), 0);
	end
	
	local interfaces = (udata and udata.interface) or h.default_interface or "*";
	if type(interfaces) == "string" then interfaces = {interfaces}; end
	local port = (udata and udata.port) or h.default_port or error("Can't start listener "..name.." because no port was specified, and it has no default port", 0);
	local mode = (udata and udata.mode) or h.default_mode or 1;
	local ssl = (udata and udata.ssl) or nil;
	local autossl = udata and udata.type == "ssl";
	
	if autossl and not ssl then
		return nil, "no ssl context";
	end

	ok, err = true, {};
	for _, interface in ipairs(interfaces) do
		local handler
		handler, err[interface] = server.addserver(interface, port, h, mode, autossl and ssl or nil);
		ok = ok and handler;
	end

	return ok, err;
end

return _M;
 end)
package.preload['util.httpstream'] = (function (...)

local coroutine = coroutine;
local tonumber = tonumber;

local deadroutine = coroutine.create(function() end);
coroutine.resume(deadroutine);

module("httpstream")

local function parser(success_cb, parser_type, options_cb)
	local data = coroutine.yield();
	local function readline()
		local pos = data:find("\r\n", nil, true);
		while not pos do
			data = data..coroutine.yield();
			pos = data:find("\r\n", nil, true);
		end
		local r = data:sub(1, pos-1);
		data = data:sub(pos+2);
		return r;
	end
	local function readlength(n)
		while #data < n do
			data = data..coroutine.yield();
		end
		local r = data:sub(1, n);
		data = data:sub(n + 1);
		return r;
	end
	local function readheaders()
		local headers = {}; -- read headers
		while true do
			local line = readline();
			if line == "" then break; end -- headers done
			local key, val = line:match("^([^%s:]+): *(.*)$");
			if not key then coroutine.yield("invalid-header-line"); end -- TODO handle multi-line and invalid headers
			key = key:lower();
			headers[key] = headers[key] and headers[key]..","..val or val;
		end
		return headers;
	end
	
	if not parser_type or parser_type == "server" then
		while true do
			-- read status line
			local status_line = readline();
			local method, path, httpversion = status_line:match("^(%S+)%s+(%S+)%s+HTTP/(%S+)$");
			if not method then coroutine.yield("invalid-status-line"); end
			path = path:gsub("^//+", "/"); -- TODO parse url more
			local headers = readheaders();
			
			-- read body
			local len = tonumber(headers["content-length"]);
			len = len or 0; -- TODO check for invalid len
			local body = readlength(len);
			
			success_cb({
				method = method;
				path = path;
				httpversion = httpversion;
				headers = headers;
				body = body;
			});
		end
	elseif parser_type == "client" then
		while true do
			-- read status line
			local status_line = readline();
			local httpversion, status_code, reason_phrase = status_line:match("^HTTP/(%S+)%s+(%d%d%d)%s+(.*)$");
			status_code = tonumber(status_code);
			if not status_code then coroutine.yield("invalid-status-line"); end
			local headers = readheaders();
			
			-- read body
			local have_body = not
				 ( (options_cb and options_cb().method == "HEAD")
				or (status_code == 204 or status_code == 304 or status_code == 301)
				or (status_code >= 100 and status_code < 200) );
			
			local body;
			if have_body then
				local len = tonumber(headers["content-length"]);
				if headers["transfer-encoding"] == "chunked" then
					body = "";
					while true do
						local chunk_size = readline():match("^%x+");
						if not chunk_size then coroutine.yield("invalid-chunk-size"); end
						chunk_size = tonumber(chunk_size, 16)
						if chunk_size == 0 then break; end
						body = body..readlength(chunk_size);
						if readline() ~= "" then coroutine.yield("invalid-chunk-ending"); end
					end
					local trailers = readheaders();
				elseif len then -- TODO check for invalid len
					body = readlength(len);
				else -- read to end
					repeat
						local newdata = coroutine.yield();
						data = data..newdata;
					until newdata == "";
					body, data = data, "";
				end
			end
			
			success_cb({
				code = status_code;
				httpversion = httpversion;
				headers = headers;
				body = body;
				-- COMPAT the properties below are deprecated
				responseversion = httpversion;
				responseheaders = headers;
			});
		end
	else coroutine.yield("unknown-parser-type"); end
end

function new(success_cb, error_cb, parser_type, options_cb)
	local co = coroutine.create(parser);
	coroutine.resume(co, success_cb, parser_type, options_cb)
	return {
		feed = function(self, data)
			if not data then
				if parser_type == "client" then coroutine.resume(co, ""); end
				co = deadroutine;
				return error_cb();
			end
			local success, result = coroutine.resume(co, data);
			if result then
				co = deadroutine;
				return error_cb(result);
			end
		end;
	};
end

return _M;
 end)
package.preload['net.http'] = (function (...)
-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--


local socket = require "socket"
local mime = require "mime"
local url = require "socket.url"
local httpstream_new = require "util.httpstream".new;

local server = require "net.server"

local connlisteners_get = require "net.connlisteners".get;
local listener = connlisteners_get("httpclient") or error("No httpclient listener!");

local t_insert, t_concat = table.insert, table.concat;
local pairs, ipairs = pairs, ipairs;
local tonumber, tostring, xpcall, select, debug_traceback, char, format =
      tonumber, tostring, xpcall, select, debug.traceback, string.char, string.format;

local log = require "util.logger".init("http");

module "http"

function urlencode(s) return s and (s:gsub("%W", function (c) return format("%%%02x", c:byte()); end)); end
function urldecode(s) return s and (s:gsub("%%(%x%x)", function (c) return char(tonumber(c,16)); end)); end

local function _formencodepart(s)
	return s and (s:gsub("%W", function (c)
		if c ~= " " then
			return format("%%%02x", c:byte());
		else
			return "+";
		end
	end));
end
function formencode(form)
	local result = {};
	for _, field in ipairs(form) do
		t_insert(result, _formencodepart(field.name).."=".._formencodepart(field.value));
	end
	return t_concat(result, "&");
end

local function request_reader(request, data, startpos)
	if not request.parser then
		local function success_cb(r)
			if request.callback then
				for k,v in pairs(r) do request[k] = v; end
				request.callback(r.body, r.code, request);
				request.callback = nil;
			end
			destroy_request(request);
		end
		local function error_cb(r)
			if request.callback then
				request.callback(r or "connection-closed", 0, request);
				request.callback = nil;
			end
			destroy_request(request);
		end
		local function options_cb()
			return request;
		end
		request.parser = httpstream_new(success_cb, error_cb, "client", options_cb);
	end
	request.parser:feed(data);
end

local function handleerr(err) log("error", "Traceback[http]: %s: %s", tostring(err), debug_traceback()); end
function request(u, ex, callback)
	local req = url.parse(u);
	
	if not (req and req.host) then
		callback(nil, 0, req);
		return nil, "invalid-url";
	end
	
	if not req.path then
		req.path = "/";
	end
	
	local custom_headers, body;
	local default_headers = { ["Host"] = req.host, ["User-Agent"] = "Prosody XMPP Server" }
	
	
	if req.userinfo then
		default_headers["Authorization"] = "Basic "..mime.b64(req.userinfo);
	end
	
	if ex then
		custom_headers = ex.headers;
		req.onlystatus = ex.onlystatus;
		body = ex.body;
		if body then
			req.method = "POST ";
			default_headers["Content-Length"] = tostring(#body);
			default_headers["Content-Type"] = "application/x-www-form-urlencoded";
		end
		if ex.method then req.method = ex.method; end
	end
	
	req.handler, req.conn = server.wrapclient(socket.tcp(), req.host, req.port or 80, listener, "*a");
	req.write = function (...) return req.handler:write(...); end
	req.conn:settimeout(0);
	local ok, err = req.conn:connect(req.host, req.port or 80);
	if not ok and err ~= "timeout" then
		callback(nil, 0, req);
		return nil, err;
	end
	
	local request_line = { req.method or "GET", " ", req.path, " HTTP/1.1\r\n" };
	
	if req.query then
		t_insert(request_line, 4, "?");
		t_insert(request_line, 5, req.query);
	end
	
	req.write(t_concat(request_line));
	local t = { [2] = ": ", [4] = "\r\n" };
	if custom_headers then
		for k, v in pairs(custom_headers) do
			t[1], t[3] = k, v;
			req.write(t_concat(t));
			default_headers[k] = nil;
		end
	end
	
	for k, v in pairs(default_headers) do
		t[1], t[3] = k, v;
		req.write(t_concat(t));
		default_headers[k] = nil;
	end
	req.write("\r\n");
	
	if body then
		req.write(body);
	end
	
	req.callback = function (content, code, request) log("debug", "Calling callback, status %s", code or "---"); return select(2, xpcall(function () return callback(content, code, request) end, handleerr)); end
	req.reader = request_reader;
	req.state = "status";
	
	listener.register_request(req.handler, req);

	return req;
end

function destroy_request(request)
	if request.conn then
		request.conn = nil;
		request.handler:close()
		listener.ondisconnect(request.handler, "closed");
	end
end

_M.urlencode = urlencode;

return _M;
 end)
package.preload['verse.bosh'] = (function (...)

local new_xmpp_stream = require "util.xmppstream".new;
local st = require "util.stanza";
require "net.httpclient_listener"; -- Required for net.http to work
local http = require "net.http";

local stream_mt = setmetatable({}, { __index = verse.stream_mt });
stream_mt.__index = stream_mt;

local xmlns_stream = "http://etherx.jabber.org/streams";
local xmlns_bosh = "http://jabber.org/protocol/httpbind";

local reconnect_timeout = 5;

function verse.new_bosh(logger, url)
	local stream = {
		bosh_conn_pool = {};
		bosh_waiting_requests = {};
		bosh_rid = math.random(1,999999);
		bosh_outgoing_buffer = {};
		bosh_url = url;
		conn = {};
	};
	function stream:reopen()
		self.bosh_need_restart = true;
		self:flush();
	end
	local conn = verse.new(logger, stream);
	return setmetatable(conn, stream_mt);
end

function stream_mt:connect()
	self:_send_session_request();
end

function stream_mt:send(data)
	self:debug("Putting into BOSH send buffer: %s", tostring(data));
	self.bosh_outgoing_buffer[#self.bosh_outgoing_buffer+1] = st.clone(data);
	self:flush(); --TODO: Optimize by doing this on next tick (give a chance for data to buffer)
end

function stream_mt:flush()
	if self.connected
	and #self.bosh_waiting_requests < self.bosh_max_requests
	and (#self.bosh_waiting_requests == 0
		or #self.bosh_outgoing_buffer > 0
		or self.bosh_need_restart) then
		self:debug("Flushing...");
		local payload = self:_make_body();
		local buffer = self.bosh_outgoing_buffer;
		for i, stanza in ipairs(buffer) do
			payload:add_child(stanza);
			buffer[i] = nil;
		end
		self:_make_request(payload);
	else
		self:debug("Decided not to flush.");
	end
end

function stream_mt:_make_request(payload)
	local request, err = http.request(self.bosh_url, { body = tostring(payload) }, function (response, code, request)
		if code ~= 0 then
			self.inactive_since = nil;
			return self:_handle_response(response, code, request);
		end
		
		-- Connection issues, we need to retry this request
		local time = os.time();
		if not self.inactive_since then
			self.inactive_since = time; -- So we know when it is time to give up
		elseif time - self.inactive_since > self.bosh_max_inactivity then
			return self:_disconnected();
		else
			self:debug("%d seconds left to reconnect, retrying in %d seconds...", 
				self.bosh_max_inactivity - (time - self.inactive_since), reconnect_timeout);
		end
		
		-- Set up reconnect timer
		timer.add_task(reconnect_timeout, function ()
			self:debug("Retrying request...");
			-- Remove old request
			for i, waiting_request in ipairs(self.bosh_waiting_requests) do
				if waiting_request == request then
					table.remove(self.bosh_waiting_requests, i);
					break;
				end
			end
			self:_make_request(payload);
		end);
	end);
	if request then
		table.insert(self.bosh_waiting_requests, request);
	else
		self:warn("Request failed instantly: %s", err);
	end
end

function stream_mt:_disconnected()
	self.connected = nil;
	self:event("disconnected");
end

function stream_mt:_send_session_request()
	local body = self:_make_body();
	
	-- XEP-0124
	body.attr.hold = "1";
	body.attr.wait = "60";
	body.attr["xml:lang"] = "en";
	body.attr.ver = "1.6";

	-- XEP-0206
	body.attr.from = self.jid;
	body.attr.to = self.host;
	body.attr.secure = 'true';
	
	http.request(self.bosh_url, { body = tostring(body) }, function (response, code)
		if code == 0 then
			-- Failed to connect
			return self:_disconnected();
		end
		-- Handle session creation response
		local payload = self:_parse_response(response)
		if not payload then
			self:warn("Invalid session creation response");
			self:_disconnected();
			return;
		end
		self.bosh_sid = payload.attr.sid; -- Session id
		self.bosh_wait = tonumber(payload.attr.wait); -- How long the server may hold connections for
		self.bosh_hold = tonumber(payload.attr.hold); -- How many connections the server may hold
		self.bosh_max_inactivity = tonumber(payload.attr.inactivity); -- Max amount of time with no connections
		self.bosh_max_requests = tonumber(payload.attr.requests) or self.bosh_hold; -- Max simultaneous requests we can make
		self.connected = true;
		self:event("connected");
		self:_handle_response_payload(payload);
	end);
end

function stream_mt:_handle_response(response, code, request)
	if self.bosh_waiting_requests[1] ~= request then
		self:warn("Server replied to request that wasn't the oldest");
		for i, waiting_request in ipairs(self.bosh_waiting_requests) do
			if waiting_request == request then
				self.bosh_waiting_requests[i] = nil;
				break;
			end
		end
	else
		table.remove(self.bosh_waiting_requests, 1);
	end
	local payload = self:_parse_response(response);
	if payload then
		self:_handle_response_payload(payload);
	end
	self:flush();
end

function stream_mt:_handle_response_payload(payload)
	for stanza in payload:childtags() do
		if stanza.attr.xmlns == xmlns_stream then
			self:event("stream-"..stanza.name, stanza);
		elseif stanza.attr.xmlns then
			self:event("stream/"..stanza.attr.xmlns, stanza);
		else
			self:event("stanza", stanza);
		end
	end
	if payload.attr.type == "terminate" then
		self:_disconnected({reason = payload.attr.condition});
	end
end

local stream_callbacks = {
	stream_ns = "http://jabber.org/protocol/httpbind", stream_tag = "body",
	default_ns = "jabber:client",
	streamopened = function (session, attr) session.notopen = nil; session.payload = verse.stanza("body", attr); return true; end;
	handlestanza = function (session, stanza) session.payload:add_child(stanza); end;
};
function stream_mt:_parse_response(response)
	self:debug("Parsing response: %s", response);
	if response == nil then
		self:debug("%s", debug.traceback());
		self:_disconnected();
		return;
	end
	local session = { notopen = true, log = self.log };
	local stream = new_xmpp_stream(session, stream_callbacks);
	stream:feed(response);
	return session.payload;
end

function stream_mt:_make_body()
	self.bosh_rid = self.bosh_rid + 1;
	local body = verse.stanza("body", {
		xmlns = xmlns_bosh;
		content = "text/xml; charset=utf-8";
		sid = self.bosh_sid;
		rid = self.bosh_rid;
	});
	if self.bosh_need_restart then
		self.bosh_need_restart = nil;
		body.attr.restart = 'true';
	end
	return body;
end
 end)
package.preload['bit'] = (function (...)
-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--


local type = type;
local tonumber = tonumber;
local setmetatable = setmetatable;
local error = error;
local tostring = tostring;
local print = print;

local xor_map = {[0]=0;[1]=1;[2]=2;[3]=3;[4]=4;[5]=5;[6]=6;[7]=7;[8]=8;[9]=9;[10]=10;[11]=11;[12]=12;[13]=13;[14]=14;[15]=15;[16]=1;[17]=0;[18]=3;[19]=2;[20]=5;[21]=4;[22]=7;[23]=6;[24]=9;[25]=8;[26]=11;[27]=10;[28]=13;[29]=12;[30]=15;[31]=14;[32]=2;[33]=3;[34]=0;[35]=1;[36]=6;[37]=7;[38]=4;[39]=5;[40]=10;[41]=11;[42]=8;[43]=9;[44]=14;[45]=15;[46]=12;[47]=13;[48]=3;[49]=2;[50]=1;[51]=0;[52]=7;[53]=6;[54]=5;[55]=4;[56]=11;[57]=10;[58]=9;[59]=8;[60]=15;[61]=14;[62]=13;[63]=12;[64]=4;[65]=5;[66]=6;[67]=7;[68]=0;[69]=1;[70]=2;[71]=3;[72]=12;[73]=13;[74]=14;[75]=15;[76]=8;[77]=9;[78]=10;[79]=11;[80]=5;[81]=4;[82]=7;[83]=6;[84]=1;[85]=0;[86]=3;[87]=2;[88]=13;[89]=12;[90]=15;[91]=14;[92]=9;[93]=8;[94]=11;[95]=10;[96]=6;[97]=7;[98]=4;[99]=5;[100]=2;[101]=3;[102]=0;[103]=1;[104]=14;[105]=15;[106]=12;[107]=13;[108]=10;[109]=11;[110]=8;[111]=9;[112]=7;[113]=6;[114]=5;[115]=4;[116]=3;[117]=2;[118]=1;[119]=0;[120]=15;[121]=14;[122]=13;[123]=12;[124]=11;[125]=10;[126]=9;[127]=8;[128]=8;[129]=9;[130]=10;[131]=11;[132]=12;[133]=13;[134]=14;[135]=15;[136]=0;[137]=1;[138]=2;[139]=3;[140]=4;[141]=5;[142]=6;[143]=7;[144]=9;[145]=8;[146]=11;[147]=10;[148]=13;[149]=12;[150]=15;[151]=14;[152]=1;[153]=0;[154]=3;[155]=2;[156]=5;[157]=4;[158]=7;[159]=6;[160]=10;[161]=11;[162]=8;[163]=9;[164]=14;[165]=15;[166]=12;[167]=13;[168]=2;[169]=3;[170]=0;[171]=1;[172]=6;[173]=7;[174]=4;[175]=5;[176]=11;[177]=10;[178]=9;[179]=8;[180]=15;[181]=14;[182]=13;[183]=12;[184]=3;[185]=2;[186]=1;[187]=0;[188]=7;[189]=6;[190]=5;[191]=4;[192]=12;[193]=13;[194]=14;[195]=15;[196]=8;[197]=9;[198]=10;[199]=11;[200]=4;[201]=5;[202]=6;[203]=7;[204]=0;[205]=1;[206]=2;[207]=3;[208]=13;[209]=12;[210]=15;[211]=14;[212]=9;[213]=8;[214]=11;[215]=10;[216]=5;[217]=4;[218]=7;[219]=6;[220]=1;[221]=0;[222]=3;[223]=2;[224]=14;[225]=15;[226]=12;[227]=13;[228]=10;[229]=11;[230]=8;[231]=9;[232]=6;[233]=7;[234]=4;[235]=5;[236]=2;[237]=3;[238]=0;[239]=1;[240]=15;[241]=14;[242]=13;[243]=12;[244]=11;[245]=10;[246]=9;[247]=8;[248]=7;[249]=6;[250]=5;[251]=4;[252]=3;[253]=2;[254]=1;[255]=0;};
local or_map = {[0]=0;[1]=1;[2]=2;[3]=3;[4]=4;[5]=5;[6]=6;[7]=7;[8]=8;[9]=9;[10]=10;[11]=11;[12]=12;[13]=13;[14]=14;[15]=15;[16]=1;[17]=1;[18]=3;[19]=3;[20]=5;[21]=5;[22]=7;[23]=7;[24]=9;[25]=9;[26]=11;[27]=11;[28]=13;[29]=13;[30]=15;[31]=15;[32]=2;[33]=3;[34]=2;[35]=3;[36]=6;[37]=7;[38]=6;[39]=7;[40]=10;[41]=11;[42]=10;[43]=11;[44]=14;[45]=15;[46]=14;[47]=15;[48]=3;[49]=3;[50]=3;[51]=3;[52]=7;[53]=7;[54]=7;[55]=7;[56]=11;[57]=11;[58]=11;[59]=11;[60]=15;[61]=15;[62]=15;[63]=15;[64]=4;[65]=5;[66]=6;[67]=7;[68]=4;[69]=5;[70]=6;[71]=7;[72]=12;[73]=13;[74]=14;[75]=15;[76]=12;[77]=13;[78]=14;[79]=15;[80]=5;[81]=5;[82]=7;[83]=7;[84]=5;[85]=5;[86]=7;[87]=7;[88]=13;[89]=13;[90]=15;[91]=15;[92]=13;[93]=13;[94]=15;[95]=15;[96]=6;[97]=7;[98]=6;[99]=7;[100]=6;[101]=7;[102]=6;[103]=7;[104]=14;[105]=15;[106]=14;[107]=15;[108]=14;[109]=15;[110]=14;[111]=15;[112]=7;[113]=7;[114]=7;[115]=7;[116]=7;[117]=7;[118]=7;[119]=7;[120]=15;[121]=15;[122]=15;[123]=15;[124]=15;[125]=15;[126]=15;[127]=15;[128]=8;[129]=9;[130]=10;[131]=11;[132]=12;[133]=13;[134]=14;[135]=15;[136]=8;[137]=9;[138]=10;[139]=11;[140]=12;[141]=13;[142]=14;[143]=15;[144]=9;[145]=9;[146]=11;[147]=11;[148]=13;[149]=13;[150]=15;[151]=15;[152]=9;[153]=9;[154]=11;[155]=11;[156]=13;[157]=13;[158]=15;[159]=15;[160]=10;[161]=11;[162]=10;[163]=11;[164]=14;[165]=15;[166]=14;[167]=15;[168]=10;[169]=11;[170]=10;[171]=11;[172]=14;[173]=15;[174]=14;[175]=15;[176]=11;[177]=11;[178]=11;[179]=11;[180]=15;[181]=15;[182]=15;[183]=15;[184]=11;[185]=11;[186]=11;[187]=11;[188]=15;[189]=15;[190]=15;[191]=15;[192]=12;[193]=13;[194]=14;[195]=15;[196]=12;[197]=13;[198]=14;[199]=15;[200]=12;[201]=13;[202]=14;[203]=15;[204]=12;[205]=13;[206]=14;[207]=15;[208]=13;[209]=13;[210]=15;[211]=15;[212]=13;[213]=13;[214]=15;[215]=15;[216]=13;[217]=13;[218]=15;[219]=15;[220]=13;[221]=13;[222]=15;[223]=15;[224]=14;[225]=15;[226]=14;[227]=15;[228]=14;[229]=15;[230]=14;[231]=15;[232]=14;[233]=15;[234]=14;[235]=15;[236]=14;[237]=15;[238]=14;[239]=15;[240]=15;[241]=15;[242]=15;[243]=15;[244]=15;[245]=15;[246]=15;[247]=15;[248]=15;[249]=15;[250]=15;[251]=15;[252]=15;[253]=15;[254]=15;[255]=15;};
local and_map = {[0]=0;[1]=0;[2]=0;[3]=0;[4]=0;[5]=0;[6]=0;[7]=0;[8]=0;[9]=0;[10]=0;[11]=0;[12]=0;[13]=0;[14]=0;[15]=0;[16]=0;[17]=1;[18]=0;[19]=1;[20]=0;[21]=1;[22]=0;[23]=1;[24]=0;[25]=1;[26]=0;[27]=1;[28]=0;[29]=1;[30]=0;[31]=1;[32]=0;[33]=0;[34]=2;[35]=2;[36]=0;[37]=0;[38]=2;[39]=2;[40]=0;[41]=0;[42]=2;[43]=2;[44]=0;[45]=0;[46]=2;[47]=2;[48]=0;[49]=1;[50]=2;[51]=3;[52]=0;[53]=1;[54]=2;[55]=3;[56]=0;[57]=1;[58]=2;[59]=3;[60]=0;[61]=1;[62]=2;[63]=3;[64]=0;[65]=0;[66]=0;[67]=0;[68]=4;[69]=4;[70]=4;[71]=4;[72]=0;[73]=0;[74]=0;[75]=0;[76]=4;[77]=4;[78]=4;[79]=4;[80]=0;[81]=1;[82]=0;[83]=1;[84]=4;[85]=5;[86]=4;[87]=5;[88]=0;[89]=1;[90]=0;[91]=1;[92]=4;[93]=5;[94]=4;[95]=5;[96]=0;[97]=0;[98]=2;[99]=2;[100]=4;[101]=4;[102]=6;[103]=6;[104]=0;[105]=0;[106]=2;[107]=2;[108]=4;[109]=4;[110]=6;[111]=6;[112]=0;[113]=1;[114]=2;[115]=3;[116]=4;[117]=5;[118]=6;[119]=7;[120]=0;[121]=1;[122]=2;[123]=3;[124]=4;[125]=5;[126]=6;[127]=7;[128]=0;[129]=0;[130]=0;[131]=0;[132]=0;[133]=0;[134]=0;[135]=0;[136]=8;[137]=8;[138]=8;[139]=8;[140]=8;[141]=8;[142]=8;[143]=8;[144]=0;[145]=1;[146]=0;[147]=1;[148]=0;[149]=1;[150]=0;[151]=1;[152]=8;[153]=9;[154]=8;[155]=9;[156]=8;[157]=9;[158]=8;[159]=9;[160]=0;[161]=0;[162]=2;[163]=2;[164]=0;[165]=0;[166]=2;[167]=2;[168]=8;[169]=8;[170]=10;[171]=10;[172]=8;[173]=8;[174]=10;[175]=10;[176]=0;[177]=1;[178]=2;[179]=3;[180]=0;[181]=1;[182]=2;[183]=3;[184]=8;[185]=9;[186]=10;[187]=11;[188]=8;[189]=9;[190]=10;[191]=11;[192]=0;[193]=0;[194]=0;[195]=0;[196]=4;[197]=4;[198]=4;[199]=4;[200]=8;[201]=8;[202]=8;[203]=8;[204]=12;[205]=12;[206]=12;[207]=12;[208]=0;[209]=1;[210]=0;[211]=1;[212]=4;[213]=5;[214]=4;[215]=5;[216]=8;[217]=9;[218]=8;[219]=9;[220]=12;[221]=13;[222]=12;[223]=13;[224]=0;[225]=0;[226]=2;[227]=2;[228]=4;[229]=4;[230]=6;[231]=6;[232]=8;[233]=8;[234]=10;[235]=10;[236]=12;[237]=12;[238]=14;[239]=14;[240]=0;[241]=1;[242]=2;[243]=3;[244]=4;[245]=5;[246]=6;[247]=7;[248]=8;[249]=9;[250]=10;[251]=11;[252]=12;[253]=13;[254]=14;[255]=15;}

local not_map = {[0]=15;[1]=14;[2]=13;[3]=12;[4]=11;[5]=10;[6]=9;[7]=8;[8]=7;[9]=6;[10]=5;[11]=4;[12]=3;[13]=2;[14]=1;[15]=0;};
local rshift1_map = {[0]=0;[1]=0;[2]=1;[3]=1;[4]=2;[5]=2;[6]=3;[7]=3;[8]=4;[9]=4;[10]=5;[11]=5;[12]=6;[13]=6;[14]=7;[15]=7;};
local rshift1carry_map = {[0]=0;[1]=8;[2]=0;[3]=8;[4]=0;[5]=8;[6]=0;[7]=8;[8]=0;[9]=8;[10]=0;[11]=8;[12]=0;[13]=8;[14]=0;[15]=8;};
local lshift1_map = {[0]=0;[1]=2;[2]=4;[3]=6;[4]=8;[5]=10;[6]=12;[7]=14;[8]=0;[9]=2;[10]=4;[11]=6;[12]=8;[13]=10;[14]=12;[15]=14;};
local lshift1carry_map = {[0]=0;[1]=0;[2]=0;[3]=0;[4]=0;[5]=0;[6]=0;[7]=0;[8]=1;[9]=1;[10]=1;[11]=1;[12]=1;[13]=1;[14]=1;[15]=1;};
local arshift1carry_map = {[0]=0;[1]=0;[2]=0;[3]=0;[4]=0;[5]=0;[6]=0;[7]=0;[8]=8;[9]=8;[10]=8;[11]=8;[12]=8;[13]=8;[14]=8;[15]=8;};

module "bit"

local bit_mt = {__tostring = function(t) return ("%x%x%x%x%x%x%x%x"):format(t[1],t[2],t[3],t[4],t[5],t[6],t[7],t[8]); end};
local function do_bop(a, b, op)
	return setmetatable({
		op[a[1]*16+b[1]];
		op[a[2]*16+b[2]];
		op[a[3]*16+b[3]];
		op[a[4]*16+b[4]];
		op[a[5]*16+b[5]];
		op[a[6]*16+b[6]];
		op[a[7]*16+b[7]];
		op[a[8]*16+b[8]];
	}, bit_mt);
end
local function do_uop(a, op)
	return setmetatable({
		op[a[1]];
		op[a[2]];
		op[a[3]];
		op[a[4]];
		op[a[5]];
		op[a[6]];
		op[a[7]];
		op[a[8]];
	}, bit_mt);
end

function bxor(a, b) return do_bop(a, b, xor_map); end
function bor(a, b) return do_bop(a, b, or_map); end
function band(a, b) return do_bop(a, b, and_map); end

function bnot(a) return do_uop(a, not_map); end
local function _rshift1(t)
	local carry = 0;
	for i=1,8 do
		local t_i = rshift1_map[t[i]] + carry;
		carry = rshift1carry_map[t[i]];
		t[i] = t_i;
	end
end
function rshift(a, i)
	local t = {a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8]};
	for n = 1,i do _rshift1(t); end
	return setmetatable(t, bit_mt);
end
local function _arshift1(t)
	local carry = arshift1carry_map[t[1]];
	for i=1,8 do
		local t_i = rshift1_map[t[i]] + carry;
		carry = rshift1carry_map[t[i]];
		t[i] = t_i;
	end
end
function arshift(a, i)
	local t = {a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8]};
	for n = 1,i do _arshift1(t); end
	return setmetatable(t, bit_mt);
end
local function _lshift1(t)
	local carry = 0;
	for i=8,1,-1 do
		local t_i = lshift1_map[t[i]] + carry;
		carry = lshift1carry_map[t[i]];
		t[i] = t_i;
	end
end
function lshift(a, i)
	local t = {a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8]};
	for n = 1,i do _lshift1(t); end
	return setmetatable(t, bit_mt);
end

local function _cast(a)
	if type(a) == "number" then a = ("%x"):format(a);
	elseif type(a) == "table" then return a;
	elseif type(a) ~= "string" then error("string expected, got "..type(a), 2); end
	local t = {0,0,0,0,0,0,0,0};
	a = "00000000"..a;
	a = a:sub(-8);
	for i = 1,8 do
		t[i] = tonumber(a:sub(i,i), 16) or error("Number format error", 2);
	end
	return setmetatable(t, bit_mt);
end

local function wrap1(f)
	return function(a, ...)
		if type(a) ~= "table" then a = _cast(a); end
		a = f(a, ...);
		a = tonumber(tostring(a), 16);
		if a > 0x7fffffff then a = a - 1 - 0xffffffff; end
		return a;
	end;
end
local function wrap2(f)
	return function(a, b, ...)
		if type(a) ~= "table" then a = _cast(a); end
		if type(b) ~= "table" then b = _cast(b); end
		a = f(a, b, ...);
		a = tonumber(tostring(a), 16);
		if a > 0x7fffffff then a = a - 1 - 0xffffffff; end
		return a;
	end;
end

bxor = wrap2(bxor);
bor = wrap2(bor);
band = wrap2(band);
bnot = wrap1(bnot);
lshift = wrap1(lshift);
rshift = wrap1(rshift);
arshift = wrap1(arshift);
cast = wrap1(_cast);

bits = 32;

return _M;
 end)
package.preload['verse.client'] = (function (...)
local verse = require "verse";
local stream = verse.stream_mt;

local jid_split = require "util.jid".split;
local adns = require "net.adns";
local lxp = require "lxp";
local st = require "util.stanza";

-- Shortcuts to save having to load util.stanza
verse.message, verse.presence, verse.iq, verse.stanza, verse.reply, verse.error_reply =
	st.message, st.presence, st.iq, st.stanza, st.reply, st.error_reply;

local new_xmpp_stream = require "util.xmppstream".new;

local xmlns_stream = "http://etherx.jabber.org/streams";

local function compare_srv_priorities(a,b)
	return a.priority < b.priority or (a.priority == b.priority and a.weight > b.weight);
end

local stream_callbacks = {
	stream_ns = xmlns_stream,
	stream_tag = "stream",
	 default_ns = "jabber:client" };
	
function stream_callbacks.streamopened(stream, attr)
	stream.stream_id = attr.id;
	if not stream:event("opened", attr) then
		stream.notopen = nil;
	end
	return true;
end

function stream_callbacks.streamclosed(stream)
	return stream:event("closed");
end

function stream_callbacks.handlestanza(stream, stanza)
	if stanza.attr.xmlns == xmlns_stream then
		return stream:event("stream-"..stanza.name, stanza);
	elseif stanza.attr.xmlns then
		return stream:event("stream/"..stanza.attr.xmlns, stanza);
	end

	return stream:event("stanza", stanza);
end

function stream:reset()
	if self.stream then
		self.stream:reset();
	else
		self.stream = new_xmpp_stream(self, stream_callbacks);
	end
	self.notopen = true;
	return true;
end

function stream:connect_client(jid, pass)
	self.jid, self.password = jid, pass;
	self.username, self.host, self.resource = jid_split(jid);
	
	-- Required XMPP features
	self:add_plugin("tls");
	self:add_plugin("sasl");
	self:add_plugin("bind");
	self:add_plugin("session");
	
	function self.data(conn, data)
		local ok, err = self.stream:feed(data);
		if ok then return; end
		self:debug("debug", "Received invalid XML (%s) %d bytes: %s", tostring(err), #data, data:sub(1, 300):gsub("[\r\n]+", " "));
		self:close("xml-not-well-formed");
	end
	
	self:hook("connected", function () self:reopen(); end);
	self:hook("incoming-raw", function (data) return self.data(self.conn, data); end);
	
	self.curr_id = 0;
	
	self.tracked_iqs = {};
	self:hook("stanza", function (stanza)
		local id, type = stanza.attr.id, stanza.attr.type;
		if id and stanza.name == "iq" and (type == "result" or type == "error") and self.tracked_iqs[id] then
			self.tracked_iqs[id](stanza);
			self.tracked_iqs[id] = nil;
			return true;
		end
	end);
	
	self:hook("stanza", function (stanza)
		if stanza.attr.xmlns == nil or stanza.attr.xmlns == "jabber:client" then
			if stanza.name == "iq" and (stanza.attr.type == "get" or stanza.attr.type == "set") then
				local xmlns = stanza.tags[1] and stanza.tags[1].attr.xmlns;
				if xmlns then
					ret = self:event("iq/"..xmlns, stanza);
					if not ret then
						ret = self:event("iq", stanza);
					end
				end
				if ret == nil then
					self:send(verse.error_reply(stanza, "cancel", "service-unavailable"));
					return true;
				end
			else
				ret = self:event(stanza.name, stanza);
			end
		end
		return ret;
	end, -1);

	self:hook("outgoing", function (data)
		if data.name then
			self:event("stanza-out", data);
		end
	end);
	
	self:hook("stanza-out", function (stanza)
		if not stanza.attr.xmlns then
			self:event(stanza.name.."-out", stanza);
		end
	end);
	
	local function stream_ready()
		self:event("ready");
	end
	self:hook("session-success", stream_ready, -1)
	self:hook("bind-success", stream_ready, -1);

	local _base_close = self.close;
	function self:close(reason)
		if not self.notopen then
			self:send("</stream:stream>");
		end
		return _base_close(self);
	end
	
	local function start_connect()
		-- Initialise connection
		self:connect(self.connect_host or self.host, self.connect_port or 5222);
	end
	
	if not (self.connect_host or self.connect_port) then
		-- Look up SRV records
		adns.lookup(function (answer)
			if answer then
				local srv_hosts = {};
				self.srv_hosts = srv_hosts;
				for _, record in ipairs(answer) do
					table.insert(srv_hosts, record.srv);
				end
				table.sort(srv_hosts, compare_srv_priorities);
				
				local srv_choice = srv_hosts[1];
				self.srv_choice = 1;
				if srv_choice then
					self.connect_host, self.connect_port = srv_choice.target, srv_choice.port;
					self:debug("Best record found, will connect to %s:%d", self.connect_host or self.host, self.connect_port or 5222);
				end
				
				self:hook("disconnected", function ()
					if self.srv_hosts and self.srv_choice < #self.srv_hosts then
						self.srv_choice = self.srv_choice + 1;
						local srv_choice = srv_hosts[self.srv_choice];
						self.connect_host, self.connect_port = srv_choice.target, srv_choice.port;
						start_connect();
						return true;
					end
				end, 1000);
				
				self:hook("connected", function ()
					self.srv_hosts = nil;
				end, 1000);
			end
			start_connect();
		end, "_xmpp-client._tcp."..(self.host)..".", "SRV");
	else
		start_connect();
	end
end

function stream:reopen()
	self:reset();
	self:send(st.stanza("stream:stream", { to = self.host, ["xmlns:stream"]='http://etherx.jabber.org/streams',
		xmlns = "jabber:client", version = "1.0" }):top_tag());
end

function stream:send_iq(iq, callback)
	local id = self:new_id();
	self.tracked_iqs[id] = callback;
	iq.attr.id = id;
	self:send(iq);
end

function stream:new_id()
	self.curr_id = self.curr_id + 1;
	return tostring(self.curr_id);
end
 end)
package.preload['verse.component'] = (function (...)
local verse = require "verse";
local stream = verse.stream_mt;

local jid_split = require "util.jid".split;
local lxp = require "lxp";
local st = require "util.stanza";
local sha1 = require "util.sha1".sha1;

-- Shortcuts to save having to load util.stanza
verse.message, verse.presence, verse.iq, verse.stanza, verse.reply, verse.error_reply =
	st.message, st.presence, st.iq, st.stanza, st.reply, st.error_reply;

local new_xmpp_stream = require "util.xmppstream".new;

local xmlns_stream = "http://etherx.jabber.org/streams";
local xmlns_component = "jabber:component:accept";

local stream_callbacks = {
	stream_ns = xmlns_stream,
	stream_tag = "stream",
	 default_ns = xmlns_component };
	
function stream_callbacks.streamopened(stream, attr)
	stream.stream_id = attr.id;
	if not stream:event("opened", attr) then
		stream.notopen = nil;
	end
	return true;
end

function stream_callbacks.streamclosed(stream)
	return stream:event("closed");
end

function stream_callbacks.handlestanza(stream, stanza)
	if stanza.attr.xmlns == xmlns_stream then
		return stream:event("stream-"..stanza.name, stanza);
	elseif stanza.attr.xmlns or stanza.name == "handshake" then
		return stream:event("stream/"..(stanza.attr.xmlns or xmlns_component), stanza);
	end

	return stream:event("stanza", stanza);
end

function stream:reset()
	if self.stream then
		self.stream:reset();
	else
		self.stream = new_xmpp_stream(self, stream_callbacks);
	end
	self.notopen = true;
	return true;
end

function stream:connect_component(jid, pass)
	self.jid, self.password = jid, pass;
	self.username, self.host, self.resource = jid_split(jid);
	
	function self.data(conn, data)
		local ok, err = self.stream:feed(data);
		if ok then return; end
		stream:debug("debug", "Received invalid XML (%s) %d bytes: %s", tostring(err), #data, data:sub(1, 300):gsub("[\r\n]+", " "));
		stream:close("xml-not-well-formed");
	end
	
	self:hook("incoming-raw", function (data) return self.data(self.conn, data); end);
	
	self.curr_id = 0;
	
	self.tracked_iqs = {};
	self:hook("stanza", function (stanza)
		local id, type = stanza.attr.id, stanza.attr.type;
		if id and stanza.name == "iq" and (type == "result" or type == "error") and self.tracked_iqs[id] then
			self.tracked_iqs[id](stanza);
			self.tracked_iqs[id] = nil;
			return true;
		end
	end);
	
	self:hook("stanza", function (stanza)
		if stanza.attr.xmlns == nil or stanza.attr.xmlns == "jabber:client" then
			if stanza.name == "iq" and (stanza.attr.type == "get" or stanza.attr.type == "set") then
				local xmlns = stanza.tags[1] and stanza.tags[1].attr.xmlns;
				if xmlns then
					ret = self:event("iq/"..xmlns, stanza);
					if not ret then
						ret = self:event("iq", stanza);
					end
				end
				if ret == nil then
					self:send(verse.error_reply(stanza, "cancel", "service-unavailable"));
					return true;
				end
			else
				ret = self:event(stanza.name, stanza);
			end
		end
		return ret;
	end, -1);

	self:hook("opened", function (attr)
		print(self.jid, self.stream_id, attr.id);
		local token = sha1(self.stream_id..pass, true);

		self:send(st.stanza("handshake", { xmlns = xmlns_component }):text(token));
		self:hook("stream/"..xmlns_component, function (stanza)
			if stanza.name == "handshake" then
				self:event("authentication-success");
			end
		end);
	end);

	local function stream_ready()
		self:event("ready");
	end
	self:hook("authentication-success", stream_ready, -1);

	-- Initialise connection
	self:connect(self.connect_host or self.host, self.connect_port or 5347);
	self:reopen();
end

function stream:reopen()
	self:reset();
	self:send(st.stanza("stream:stream", { to = self.host, ["xmlns:stream"]='http://etherx.jabber.org/streams',
		xmlns = xmlns_component, version = "1.0" }):top_tag());
end

function stream:close(reason)
	if not self.notopen then
		self:send("</stream:stream>");
	end
	local on_disconnect = self.conn.disconnect();
	self.conn:close();
	on_disconnect(conn, reason);
end

function stream:send_iq(iq, callback)
	local id = self:new_id();
	self.tracked_iqs[id] = callback;
	iq.attr.id = id;
	self:send(iq);
end

function stream:new_id()
	self.curr_id = self.curr_id + 1;
	return tostring(self.curr_id);
end
 end)

-- Use LuaRocks if available
pcall(require, "luarocks.require");

-- Load LuaSec if available
pcall(require, "ssl");

local server = require "net.server";
local events = require "util.events";

module("verse", package.seeall);
local verse = _M;
_M.server = server;

local stream = {};
stream.__index = stream;
stream_mt = stream;

verse.plugins = {};

function verse.new(logger, base)
	local t = setmetatable(base or {}, stream);
	t.id = tostring(t):match("%x*$");
	t:set_logger(logger, true);
	t.events = events.new();
	t.plugins = {};
	return t;
end

verse.add_task = require "util.timer".add_task;

verse.logger = logger.init;
verse.log = verse.logger("verse");

function verse.set_logger(logger)
	verse.log = logger;
	server.setlogger(logger);
end

function verse.filter_log(levels, logger)
	local level_set = {};
	for _, level in ipairs(levels) do
		level_set[level] = true;
	end
	return function (level, name, ...)
		if level_set[level] then
			return logger(level, name, ...);
		end
	end;
end

local function error_handler(err)
	verse.log("error", "Error: %s", err);
	verse.log("error", "Traceback: %s", debug.traceback());
end

function verse.set_error_handler(new_error_handler)
	error_handler = new_error_handler;
end

function verse.loop()
	return xpcall(server.loop, error_handler);
end

function verse.step()
	return xpcall(server.step, error_handler);
end

function verse.quit()
	return server.setquitting(true);
end

function stream:connect(connect_host, connect_port)
	connect_host = connect_host or "localhost";
	connect_port = tonumber(connect_port) or 5222;
	
	-- Create and initiate connection
	local conn = socket.tcp()
	conn:settimeout(0);
	local success, err = conn:connect(connect_host, connect_port);
	
	if not success and err ~= "timeout" then
		self:warn("connect() to %s:%d failed: %s", connect_host, connect_port, err);
		return self:event("disconnected", { reason = err }) or false, err;
	end

	local conn = server.wrapclient(conn, connect_host, connect_port, new_listener(self), "*a");
	if not conn then
		self:warn("connection initialisation failed: %s", err);
		return self:event("disconnected", { reason = err }) or false, err;
	end
	
	self.conn = conn;
	self.send = function (stream, data)
		self:event("outgoing", data);
		data = tostring(data);
		self:event("outgoing-raw", data);
		return conn:write(data);
	end;
	return true;
end

function stream:close()
	if not self.conn then 
		verse.log("error", "Attempt to close disconnected connection - possibly a bug");
		return;
	end
	local on_disconnect = self.conn.disconnect();
	self.conn:close();
	on_disconnect(conn, reason);
end

-- Logging functions
function stream:debug(...)
	if self.logger and self.log.debug then
		return self.logger("debug", ...);
	end
end

function stream:warn(...)
	if self.logger and self.log.warn then
		return self.logger("warn", ...);
	end
end

function stream:error(...)
	if self.logger and self.log.error then
		return self.logger("error", ...);
	end
end

function stream:set_logger(logger, levels)
	local old_logger = self.logger;
	if logger then
		self.logger = logger;
	end
	if levels then
		if levels == true then
			levels = { "debug", "info", "warn", "error" };
		end
		self.log = {};
		for _, level in ipairs(levels) do
			self.log[level] = true;
		end
	end
	return old_logger;
end

function stream_mt:set_log_levels(levels)
	self:set_logger(nil, levels);
end

-- Event handling
function stream:event(name, ...)
	self:debug("Firing event: "..tostring(name));
	return self.events.fire_event(name, ...);
end

function stream:hook(name, ...)
	return self.events.add_handler(name, ...);
end

function stream:unhook(name, handler)
	return self.events.remove_handler(name, handler);
end

function verse.eventable(object)
        object.events = events.new();
        object.hook, object.unhook = stream.hook, stream.unhook;
        local fire_event = object.events.fire_event;
        function object:event(name, ...)
                return fire_event(name, ...);
        end
        return object;
end

function stream:add_plugin(name)
	if self.plugins[name] then return true; end
	if require("verse.plugins."..name) then
		local ok, err = verse.plugins[name](self);
		if ok ~= false then
			self:debug("Loaded %s plugin", name);
			self.plugins[name] = true;
		else
			self:warn("Failed to load %s plugin: %s", name, err);
		end
	end
	return self;
end

-- Listener factory
function new_listener(stream)
	local conn_listener = {};
	
	function conn_listener.onconnect(conn)
		stream.connected = true;
		stream:event("connected");
	end
	
	function conn_listener.onincoming(conn, data)
		stream:event("incoming-raw", data);
	end
	
	function conn_listener.ondisconnect(conn, err)
		stream.connected = false;
		stream:event("disconnected", { reason = err });
	end

	function conn_listener.ondrain(conn)
		stream:event("drained");
	end
	
	function conn_listener.onstatus(conn, new_status)
		stream:event("status", new_status);
	end
	
	return conn_listener;
end


local log = require "util.logger".init("verse");

return verse;
 end)
-- README
-- Squish verse into this dir, then squish them into one, which you move
-- and rename to mod_ircd.lua in your prosody modules/plugins dir.
--
-- IRC spec:
-- http://tools.ietf.org/html/rfc2812
local _module = module
module = _G.module
local module = _module
--
local component_jid, component_secret, muc_server =
      module.host, nil, module:get_option("conference_server");

package.loaded["util.sha1"] = require "util.encodings";
local verse = require "verse"
require "verse.component"
require "socket"
c = verse.new();--verse.logger())
c:add_plugin("groupchat");

local function verse2prosody(e)
	return c:event("stanza", e.stanza) or true;
end
module:hook("message/bare", verse2prosody);
module:hook("message/full", verse2prosody);
module:hook("presence/bare", verse2prosody);
module:hook("presence/full", verse2prosody);
c.type = "component";
c.send = core_post_stanza;

-- This plugin is actually a verse based component, but that mode is currently commented out

-- Add some hooks for debugging
--c:hook("opened", function () print("Stream opened!") end);
--c:hook("closed", function () print("Stream closed!") end);
--c:hook("stanza", function (stanza) print("Stanza:", stanza) end);

-- This one prints all received data
--c:hook("incoming-raw", print, 1000);
--c:hook("stanza", print, 1000);
--c:hook("outgoing-raw", print, 1000);

-- Print a message after authentication
--c:hook("authentication-success", function () print("Logged in!"); end);
--c:hook("authentication-failure", function (err) print("Failed to log in! Error: "..tostring(err.condition)); end);

-- Print a message and exit when disconnected
--c:hook("disconnected", function () print("Disconnected!"); os.exit(); end);

-- Now, actually start the connection:
--c.connect_host = "127.0.0.1"
--c:connect_component(component_jid, component_secret);

local jid = require "util.jid";

local function irc2muc(channel, nick)
	return jid.join(channel:gsub("^#", ""), muc_server, nick)
end
local function muc2irc(room)
	local channel, _, nick = jid.split(room);
	return "#"..channel, nick;
end
local rolemap = {
	moderator = "@",
	participant = "+",
}
local modemap = {
	moderator = "o",
	participant = "v",
}

local irc_listener = { default_port = 6667, default_mode = "*l" };

local sessions = {};
local jids = {};
local commands = {};

local nicks = {};

local st = require "util.stanza";

local conference_server = muc_server;

local function irc_close_session(session)
	session.conn:close();
end

function irc_listener.onincoming(conn, data)
	local session = sessions[conn];
	if not session then
		session = { conn = conn, host = component_jid, reset_stream = function () end,
			close = irc_close_session, log = logger.init("irc"..(conn.id or "1")),
			rooms = {},
			roster = {} };
		sessions[conn] = session;
		function session.data(data)
			local command, args = data:match("^%s*([^ ]+) *(.*)%s*$");
			if not command then
				return;
			end
			command = command:upper();
			if not session.nick then
				if not (command == "USER" or command == "NICK") then
					session.send(":" .. session.host .. " 451 " .. command .. " :You have not registered")
				end
			end
			if commands[command] then
				local ret = commands[command](session, args);
				if ret then
					session.send(ret.."\r\n");
				end
			else
				session.send(":" .. session.host .. " 421 " .. session.nick .. " " .. command .. " :Unknown command")
				module:log("debug", "Unknown command: %s", command);
			end
		end
		function session.send(data)
			return conn:write(data.."\r\n");
		end
	end
	if data then
		session.data(data);
	end
end

function irc_listener.ondisconnect(conn, error)
	local session = sessions[conn];
	for _, room in pairs(session.rooms) do
		room:leave("Disconnected");
	end
	jids[session.full_jid] = nil;
	nicks[session.nick] = nil;
	sessions[conn] = nil;
end

function commands.NICK(session, nick)
	if session.nick then
		session.send(":"..session.host.." 484 * "..nick.." :I'm afraid I can't let you do that, "..nick);
		--TODO Loop throug all rooms and change nick, with help from Verse.
		return;
	end
	nick = nick:match("^[%w_]+");
	if nicks[nick] then
		session.send(":"..session.host.." 433 * "..nick.." :The nickname "..nick.." is already in use");
		return;
	end
	local full_jid = jid.join(nick, component_jid, "ircd");
	jids[full_jid] = session;
	nicks[nick] = session;
	session.nick = nick;
	session.full_jid = full_jid;
	session.type = "c2s";
	session.send(":"..session.host.." 001 "..session.nick.." :Welcome to XMPP via the "..session.host.." gateway "..session.nick);
end

function commands.USER(session, params)
	-- FIXME
	-- Empty command for now
end

function commands.JOIN(session, channel)
	local room_jid = irc2muc(channel);
	print(session.full_jid);
	local room, err = c:join_room(room_jid, session.nick, { source = session.full_jid } );
	if not room then
		return ":"..session.host.." ERR :Could not join room: "..err
	end
	session.rooms[channel] = room;
	room.channel = channel;
	room.session = session;
	session.send(":"..session.nick.." JOIN :"..channel);
	session.send(":"..session.host.." 332 "..session.nick.." "..channel.." :Connection in progress...");
	room:hook("message", function(event)
		if not event.body then return end
		local nick, body = event.nick, event.body;
		if nick ~= session.nick then
			if body:sub(1,4) == "/me " then
				body = "\1ACTION ".. body:sub(5) .. "\1"
			end
			session.send(":"..nick.." PRIVMSG "..channel.." :"..body);
			--FIXME PM's probably won't work
		end
	end);
	room:hook("subject-changed", function(changed) 
		session.send((":%s TOPIC %s :%s"):format(changed.by, channel, changed.to or ""));
	end);
end

c:hook("groupchat/joined", function(room)
	local session = room.session or jids[room.opts.source];
	local channel = room.channel;
	session.send((":%s!%s JOIN %s :"):format(session.nick, session.nick, channel));
	if room.topic then
		session.send((":%s 332 %s :%s"):format(session.host, channel, room.topic));
	end
	commands.NAMES(session, channel)
	--FIXME Ones own mode get's lost
	--session.send((":%s MODE %s +%s %s"):format(session.host, room.channel, modemap[nick.role], nick.nick));
	room:hook("occupant-joined", function(nick)
		session.send((":%s!%s JOIN :%s"):format(nick.nick, nick.nick, channel));
		if nick.role and modemap[nick.role] then
			session.send((":%s MODE %s +%s %s"):format(session.host, room.channel, modemap[nick.role], nick.nick));
		end
	end);
	room:hook("occupant-left", function(nick)
		session.send((":%s!%s PART %s :"):format(nick.nick, nick.nick, channel));
	end);
end);

function commands.NAMES(session, channel)
	local nicks = { };
	local room = session.rooms[channel];
	if not room then return end
	-- TODO Break this out into commands.NAMES
	for nick, n in pairs(room.occupants) do
		if n.role and rolemap[n.role] then
			nick = rolemap[n.role] .. nick;
		end
		table.insert(nicks, nick);
	end
	nicks = table.concat(nicks, " ");
	--:molyb.irc.bnfh.org 353 derp = #grill-bit :derp hyamobi walt snuggles_ E-Rock kng grillbit gunnarbot Frink shedma zagabar zash Mrw00t Appiah J10 lectus peck EricJ soso mackt offer hyarion @pettter MMN-o 
	session.send((":%s 353 %s = %s :%s"):format(session.host, session.nick, channel, nicks));
	session.send((":%s 366 %s %s :End of /NAMES list."):format(session.host, session.nick, channel));
	session.send(":"..session.host.." 353 "..session.nick.." = "..channel.." :"..nicks);
end

function commands.PART(session, channel)
	local channel, part_message = channel:match("^([^:]+):?(.*)$");
	channel = channel:match("^([%S]*)");
	session.rooms[channel]:leave(part_message);
	session.send(":"..session.nick.." PART :"..channel);
end

function commands.PRIVMSG(session, message)
	local channel, message = message:match("^(%S+) :(.+)$");
	if message and #message > 0 and session.rooms[channel] then
		if message:sub(1,8) == "\1ACTION " then
			message = "/me ".. message:sub(9,-2)
		end
		module:log("debug", "%s sending PRIVMSG \"%s\" to %s", session.nick, message, channel);
		session.rooms[channel]:send_message(message);
	end
end

function commands.TOPIC(session, message)
	if not message then return end
	local channel, topic = message:match("^(%S+) :(.*)$");
	if not channel then
		channel = message:match("^(%S+)");
	end
	if not channel then return end
	local room = session.rooms[channel];
	if topic then
		room:set_subject(topic)
	else
		session.send((":%s TOPIC %s :%s"):format(session.host, channel, room.subject or ""));
		-- first should be who set it, but verse doesn't provide that yet, so we'll
		-- just say it was the server
	end
end

function commands.PING(session, server)
	session.send(":"..session.host..": PONG "..server);
end

function commands.WHO(session, channel)
	if session.rooms[channel] then
		local room = session.rooms[channel]
		for nick in pairs(room.occupants) do
			--n=MattJ 91.85.191.50 irc.freenode.net MattJ H :0 Matthew Wild
			session.send(":"..session.host.." 352 "..session.nick.." "..channel.." "..nick.." "..nick.." "..session.host.." "..nick.." H :0 "..nick);
		end
		session.send(":"..session.host.." 315 "..session.nick.." "..channel.. " :End of /WHO list");
	end
end

function commands.MODE(session, channel)
	session.send(":"..session.host.." 324 "..session.nick.." "..channel.." +J"); 
end

function commands.QUIT(session, message)
	session.send("ERROR :Closing Link: "..session.nick);
	for _, room in pairs(session.rooms) do
		room:leave(message);
	end
	jids[session.full_jid] = nil;
	nicks[session.nick] = nil;
	sessions[session.conn] = nil;
	session:close();
end

function commands.RAW(session, data)
	--c:send(data)
end

local function desetup()
	require "net.connlisteners".deregister("irc");
end

--c:hook("ready", function ()
	require "net.connlisteners".register("irc", irc_listener);
	require "net.connlisteners".start("irc");
--end);

module:hook("module-unloaded", desetup)
--print("Starting loop...")
--verse.loop()

--[[ TODO

This is so close to working as a Prosody plugin you know ^^
Zash: :D
MattJ: That component function can go
Prosody fires events now
but verse fires "message" where Prosody fires "message/bare"
[20:59:50] 
Easy... don't connect_component
hook "message/*" and presence, and whatever
and call c:event("message", ...)
module:hook("message/bare", function (e) c:event("message", e.stanza) end)
as an example
That's so bad ^^
and override c:send() to core_post_stanza...

--]]

