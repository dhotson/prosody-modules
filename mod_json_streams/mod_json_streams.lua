--
-- XEP-0295: JSON Encodings for XMPP
--

module.host = "*"

local filters = require "util.filters"
local json = require "util.json"

local json_escapes = {
	["\""] = "\\\"", ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
	["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t"};

local s_char = string.char;
for i=0,31 do
	local ch = s_char(i);
	if not json_escapes[ch] then json_escapes[ch] = ("\\u%.4X"):format(i); end
end

local state_out = 0;
local state_key_before = 1;
local state_key_in = 2;
local state_key_escape = 3;
local state_key_after = 4;
local state_val_before = 5;
local state_val_in = 6;
local state_val_escape = 7;
local state_val_after = 8;

local whitespace = { [" "] = true, ["\n"] = true, ["\r"] = true, ["\t"] = true };
function json_decoder()
	local state = state_out;
	local quote;
	local output = "";
	local buffer = "";
	return function(input)
		for ch in input:gmatch(".") do
			module:log("debug", "%s | %d", ch, state)
			local final = false;
			if state == state_out then
				if whitespace[ch] then
				elseif ch ~= "{" then return nil, "{ expected";
				else state = state_key_before end
			elseif state == state_key_before then
				if whitespace[ch] then
				elseif ch ~= "'" and ch ~= "\"" then return nil, "\" expected";
				else quote = ch; state = state_key_in; end
			elseif state == state_key_in then
				if ch == quote then state = state_key_after;
				elseif ch ~= "s" then return nil, "invalid key, 's' expected"; -- only s as key allowed
				else end -- ignore key
			elseif state == state_key_after then
				if whitespace[ch] then
				elseif ch ~= ":" then return nil, ": expected";
				else state = state_val_before; end
			elseif state == state_val_before then
				if whitespace[ch] then
				elseif ch ~= "'" and ch ~= "\"" then return nil, "\" expected";
				else quote = ch; state = state_val_in; end
			elseif state == state_val_in then
				if ch == quote then state = state_val_after;
				elseif ch == "\\" then state = state_val_escape;
				else end
			elseif state == state_val_after then
				if whitespace[ch] then
				elseif ch ~= "}" then return nil, "} expected";
				else state = state_out;
					final = true;
				end
			elseif state == state_val_escape then
				state = state_val_in;
			else
				module:log("error", "Unhandled state: "..state);
				return nil, "Unhandled state in parser"
			end
			buffer = buffer..ch;
			if final then
				module:log("debug", "%s", buffer)
				local tmp;
				pcall(function() tmp = json.decode(buffer); end);
				if not tmp then return nil, "Invalid JSON"; end
				output, buffer = output..tmp.s, "";
			end
		end
		local _ = output; output = "";
		return _;
	end;
end

function filter_hook(session)
	local determined = false;
	local is_json = false;
	local function in_filter(t)
		if not determined then
			is_json = (t:sub(1,1) == "{") and json_decoder();
			determined = true;
		end
		if is_json then
			local s, err = is_json(t);
			if not err then return s; end
			session:close("not-well-formed");
			return;
		end
		return t;
	end
	local function out_filter(t)
		if is_json then
			return '{"s":"' .. t:gsub(".", json_escapes) .. '"}'; -- encode
		end
		return t;
	end
	filters.add_filter(session, "bytes/in", in_filter,   100);
	filters.add_filter(session, "bytes/out", out_filter, 100);
end

function module.load()
	filters.add_filter_hook(filter_hook);
end
function module.unload()
	filters.remove_filter_hook(filter_hook);
end


