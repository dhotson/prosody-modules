-- Copyright (C) 2011-2012 Kim Alvefur
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

-- TODO
-- function lua_to_xep54()
-- function lua_to_text()
-- replace text_to_xep54() and xep54_to_text() with intermediate lua?

local st = require "util.stanza";
local t_insert, t_concat = table.insert, table.concat;
local type = type;
local next, pairs, ipairs = next, pairs, ipairs;

local lua_to_text, lua_to_xep54, text_to_lua, text_to_xep54, xep54_to_lua, xep54_to_text;
local from_text, to_text, from_xep54, to_xep54; --TODO implement these, replace the above


local vCard_dtd;

local function vCard_esc(s)
	return s:gsub("[,:;\\]", "\\%1"):gsub("\n","\\n");
end

local function vCard_unesc(s)
	return s:gsub("\\?[\\nt:;,]", {
		["\\\\"] = "\\",
		["\\n"] = "\n",
		["\\t"] = "\t",
		["\\:"] = ":", -- FIXME Shouldn't need to espace : in values, just params
		["\\;"] = ";",
		["\\,"] = ",",
		[":"] = "\29",
		[";"] = "\30",
		[","] = "\31",
	});
end

function text_to_xep54(data)
	--[[ TODO
	return lua_to_xep54(text_to_lua(data));
	--]]
	data = data
		:gsub("\r\n","\n")
		:gsub("\n ", "")
		:gsub("\n\n+","\n");
	local c = st.stanza("xCard", { xmlns = "vcard-temp" });
	for line in data:gmatch("[^\n]+") do
		local line = vCard_unesc(line);
		local name, params, value = line:match("^([-%a]+)(\30?[^\29]*)\29(.*)$");
		value = value:gsub("\29",":");
		if #params > 0 then
			local _params = {};
			for k,isval,v in params:gmatch("\30([^=]+)(=?)([^\30]*)") do
				k = k:upper();
				local _vt = {};
				for _p in v:gmatch("[^\31]+") do
					_vt[#_vt+1]=_p
					_vt[_p]=true;
				end
				if isval == "=" then
					_params[k]=_vt;
				else
					_params[k]=true;
				end
			end
			params = _params;
		end
		if name == "BEGIN" and value == "VCARD" then
			c:tag("vCard", { xmlns = "vcard-temp" });
		elseif name == "END" and value == "VCARD" then
			c:up();
		elseif vCard_dtd[name] then
			local dtd = vCard_dtd[name];
			c:tag(name);
			if dtd.types then
				for _, t in ipairs(dtd.types) do
					if ( params.TYPE and params.TYPE[t] == true)
							or params[t] == true then
						c:tag(t):up();
					end
				end
			end
			if dtd.props then
				for _, p in ipairs(dtd.props) do
					if params[p] then
						if params[p] == true then
							c:tag(p):up();
						else
							for _, prop in ipairs(params[p]) do
								c:tag(p):text(prop):up();
							end
						end
					end
				end
			end
			if dtd == "text" then
				c:text(value);
			elseif dtd.value then
				c:tag(dtd.value):text(value):up();
			elseif dtd.values then
				local values = dtd.values;
				local i = 1;
				local value = "\30"..value;
				for p in value:gmatch("\30([^\30]*)") do
					c:tag(values[i]):text(p):up();
					if i < #values then
						i = i + 1;
					end
				end
			end
			c:up();
		end
	end
	return c;
end

function text_to_lua(data) --table
	data = data
		:gsub("\r\n","\n")
		:gsub("\n ", "")
		:gsub("\n\n+","\n");
	local vCards = {};
	local c; -- current item
	for line in data:gmatch("[^\n]+") do
		local line = vCard_unesc(line);
		local name, params, value = line:match("^([-%a]+)(\30?[^\29]*)\29(.*)$");
		value = value:gsub("\29",":");
		if #params > 0 then
			local _params = {};
			for k,isval,v in params:gmatch("\30([^=]+)(=?)([^\30]*)") do
				k = k:upper();
				local _vt = {};
				for _p in v:gmatch("[^\31]+") do
					_vt[#_vt+1]=_p
					_vt[_p]=true;
				end
				if isval == "=" then
					_params[k]=_vt;
				else
					_params[k]=true;
				end
			end
			params = _params;
		end
		if name == "BEGIN" and value == "VCARD" then
			c = {};
			vCards[#vCards+1] = c;
		elseif name == "END" and value == "VCARD" then
			c = nil;
		elseif vCard_dtd[name] then
			local dtd = vCard_dtd[name];
			local p = { name = name };
			c[#c+1]=p;
			--c[name]=p;
			local up = c;
			c = p;
			if dtd.types then
				for _, t in ipairs(dtd.types) do
					local t = t:lower();
					if ( params.TYPE and params.TYPE[t] == true)
							or params[t] == true then
						c.TYPE=t;
					end
				end
			end
			if dtd.props then
				for _, p in ipairs(dtd.props) do
					if params[p] then
						if params[p] == true then
							c[p]=true;
						else
							for _, prop in ipairs(params[p]) do
								c[p]=prop;
							end
						end
					end
				end
			end
			if dtd == "text" or dtd.value then
				t_insert(c, value);
			elseif dtd.values then
				local value = "\30"..value;
				for p in value:gmatch("\30([^\30]*)") do
					t_insert(c, p);
				end
			end
			c = up;
		end
	end
	return vCards;
end

function to_text(vcard)
	local t={};
	t_insert(t, "BEGIN:VCARD")
	for i=1,#vcard do
		t_insert(t, ("%s:%s"):format(vcard[i].name, t_concat(vcard[i], ";")));
	end
	t_insert(t, "END:VCARD")
	return t_concat(t,"\n");
end

local function vCard_prop(item) -- single item staza object to text line
	local prop_name = item.name;
	local prop_def = vCard_dtd[prop_name];
	if not prop_def then return nil end

	local value, params = "", {};

	if prop_def == "text" then
		value = item:get_text();
	elseif type(prop_def) == "table" then
		if prop_def.value then --single item
			value = item:get_child_text(prop_def.value) or "";
		elseif prop_def.values then --array
			local value_names = prop_def.values;
			value = {};
			if value_names.behaviour == "repeat-last" then
				for i=1,#item do
					t_insert(value, item[i]:get_text() or "");
				end
			else
				for i=1,#value_names do
					t_insert(value, item:get_child_text(value_names[i]) or "");
				end
			end
		elseif prop_def.names then
			local names = prop_def.names;
			for i=1,#names do
				if item:get_child(names[i]) then
					value = names[i];
					break;
				end
			end
		end
		
		if prop_def.props_verbatim then
			for k,v in pairs(prop_def.props_verbatim) do
				params[k] = v;
			end
		end

		if prop_def.types then
			local types = prop_def.types;
			params.TYPE = {};
			for i=1,#types do
				if item:get_child(types[i]) then
					t_insert(params.TYPE, types[i]:lower());
				end
			end
			if #params.TYPE == 0 then
				params.TYPE = nil;
			end
		end

		if prop_def.props then
			local props = prop_def.props;
			for i=1,#props do
				local prop = props[i]
				local p = item:get_child_text(prop);
				if p then
					params[prop] = params[prop] or {};
					t_insert(params[prop], p);
				end
			end
		end
	else
		return nil
	end

	if type(value) == "table" then
		for i=1,#value do
			value[i]=vCard_esc(value[i]);
		end
		value = t_concat(value, ";");
	else
		value = vCard_esc(value);
	end

	if next(params) then
		local sparams = "";
		for k,v in pairs(params) do
			sparams = sparams .. (";%s=%s"):format(k, t_concat(v,","));
		end
		params = sparams;
	else
		params = "";
	end

	return ("%s%s:%s"):format(item.name, params, value)
		:gsub(("."):rep(75), "%0\r\n "):gsub("\r\n $","");
end

function xep54_to_text(vCard)
	--[[ TODO
	return lua_to_text(xep54_to_lua(vCard))
	--]]
	local r = {};
	t_insert(r, "BEGIN:VCARD");
	for i = 1,#vCard do
		local item = vCard[i];
		if item.name then
			local s = vCard_prop(item);
			if s then
				t_insert(r, s);
			end
		end
	end
	t_insert(r, "END:VCARD");
	return t_concat(r, "\r\n");
end

local function xep54_item_to_lua(item)
	local prop_name = item.name;
	local prop_def = vCard_dtd[prop_name];
	if not prop_def then return nil end

	local prop = { name = prop_name };

	if prop_def == "text" then
		prop[1] = item:get_text();
	elseif type(prop_def) == "table" then
		if prop_def.value then --single item
			prop[1] = item:get_child_text(prop_def.value) or "";
		elseif prop_def.values then --array
			local value_names = prop_def.values;
			if value_names.behaviour == "repeat-last" then
				for i=1,#item do
					t_insert(prop, item[i]:get_text() or "");
				end
			else
				for i=1,#value_names do
					t_insert(prop, item:get_child_text(value_names[i]) or "");
				end
			end
		elseif prop_def.names then
			local names = prop_def.names;
			for i=1,#names do
				if item:get_child(names[i]) then
					prop[1] = names[i];
					break;
				end
			end
		end
		
		if prop_def.props_verbatim then
			for k,v in pairs(prop_def.props_verbatim) do
				prop[k] = v;
			end
		end

		if prop_def.types then
			local types = prop_def.types;
			prop.TYPE = {};
			for i=1,#types do
				if item:get_child(types[i]) then
					t_insert(prop.TYPE, types[i]:lower());
				end
			end
			if #prop.TYPE == 0 then
				prop.TYPE = nil;
			end
		end

		-- A key-value pair, within a key-value pair?
		if prop_def.props then
			local params = prop_def.props;
			for i=1,#params do
				local name = params[i]
				local data = item:get_child_text(name);
				if data then
					prop[name] = prop[name] or {};
					t_insert(prop[name], data);
				end
			end
		end
	else
		return nil
	end

	return prop;
end

local function xep54_vCard_to_lua(vCard)
	local tags = vCard.tags;
	local t = {};
	for i=1,#tags do
		t[i] = xep54_item_to_lua(tags[i]);
	end
	return t
end

function xep54_to_lua(vCard)
	if vCard.attr.xmlns ~= "vcard-temp" then
		return false
	end
	if vCard.name == "xCard" then
		local t = {};
		local vCards = vCard.tags;
		for i=1,#vCards do
			local ti = xep54_vCard_to_lua(vCards[i]);
			t[i] = ti;
			--t[ti.name] = ti;
		end
		return t
	elseif vCard.name == "vCard" then
		return xep54_vCard_to_lua(vCard)
	end
end

-- This was adapted from http://xmpp.org/extensions/xep-0054.html#dtd
vCard_dtd = {
	VERSION = "text", --MUST be 3.0, so parsing is redundant
	FN = "text",
	N = {
		values = {
			"FAMILY",
			"GIVEN",
			"MIDDLE",
			"PREFIX",
			"SUFFIX",
		},
	},
	NICKNAME = "text",
	PHOTO = {
		props_verbatim = { ENCODING = { "b" } },
		props = { "TYPE" },
		value = "BINVAL", --{ "EXTVAL", },
	},
	BDAY = "text",
	ADR = {
		types = {
			"HOME",
			"WORK", 
			"POSTAL", 
			"PARCEL", 
			"DOM",
			"INTL",
			"PREF", 
		},
		values = {
			"POBOX",
			"EXTADD",
			"STREET",
			"LOCALITY",
			"REGION",
			"PCODE",
			"CTRY",
		}
	},
	LABEL = {
		types = {
			"HOME", 
			"WORK", 
			"POSTAL", 
			"PARCEL", 
			"DOM",
			"INTL", 
			"PREF", 
		},
		value = "LINE",
	},
	TEL = {
		types = {
			"HOME", 
			"WORK", 
			"VOICE", 
			"FAX", 
			"PAGER", 
			"MSG", 
			"CELL", 
			"VIDEO", 
			"BBS", 
			"MODEM", 
			"ISDN", 
			"PCS", 
			"PREF", 
		},
		value = "NUMBER",
	},
	EMAIL = {
		types = {
			"HOME", 
			"WORK", 
			"INTERNET", 
			"PREF", 
			"X400", 
		},
		value = "USERID",
	},
	JABBERID = "text",
	MAILER = "text",
	TZ = "text",
	GEO = {
		values = {
			"LAT",
			"LON",
		},
	},
	TITLE = "text",
	ROLE = "text",
	LOGO = "copy of PHOTO",
	AGENT = "text",
	ORG = {
		values = {
			behaviour = "repeat-last",
			"ORGNAME",
			"ORGUNIT",
		}
	},
	CATEGORIES = {
		values = "KEYWORD",
	},
	NOTE = "text",
	PRODID = "text",
	REV = "text",
	SORTSTRING = "text",
	SOUND = "copy of PHOTO",
	UID = "text",
	URL = "text",
	CLASS = {
		names = { -- The item.name is the value if it's one of these.
			"PUBLIC",
			"PRIVATE",
			"CONFIDENTIAL",
		},
	},
	KEY = {
		props = { "TYPE" },
		value = "CRED",
	},
	DESC = "text",
};
vCard_dtd.LOGO = vCard_dtd.PHOTO;
vCard_dtd.SOUND = vCard_dtd.PHOTO;

return {
	text_to_xep54 = text_to_xep54;
	text_to_lua = text_to_lua;
	xep54_to_text = xep54_to_text;
	xep54_to_lua = xep54_to_lua;
	--[[ TODO
	from_text = from_text;
	to_text = to_text;
	from_xep54 = from_xep54;
	to_xep54 = to_xep54;
	--]]
};
