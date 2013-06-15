local it = require "util.iterators";
local log = require "util.logger".init("stats");

local last_cpu_wall, last_cpu_clock;
local get_time = require "socket".gettime;

local active_sessions, active_jids = {}, {};

local stats = {
	total_users = {
		get = function () return it.count(it.keys(bare_sessions)); end
	};
	total_c2s = {
		get = function () return it.count(it.keys(full_sessions)); end
	};
	total_s2sin = {
		get = function () return it.count(it.keys(prosody.incoming_s2s)); end
	};
	total_s2sout = {
		get = function ()
			local count = 0;
			for host, host_session in pairs(hosts) do
				count = count + it.count(it.keys(host_session.s2sout));
			end
			return count;
		end
	};
	total_component = {
		get = function ()
			local count = 0;
			for host, host_session in pairs(hosts) do
				if host_session.type == "component" then
					local c = host_session.modules.component;
					if c and c.connected then -- 0.9 only
						count = count + 1;
					end
				end
			end
			return count;
		end
	};
	up_since = {
		get = function () return prosody.start_time; end;
		tostring = function (up_since)
			return tostring(os.time()-up_since).."s";
		end;
	};
	memory_used = {
		get = function () return collectgarbage("count")/1024; end;
		tostring = "%0.2fMB";
	};
	memory_process = {
		get = function () return pposix.meminfo().allocated/1048576; end;
		tostring = "%0.2fMB";
	};
	time = {
		tostring = function () return os.date("%T"); end;
	};
	cpu = {
		get = function ()
			local new_wall, new_clock = get_time(), os.clock();
			local pc = 0;
			if last_cpu_wall then
				pc = 100/((new_wall-last_cpu_wall)/(new_clock-last_cpu_clock));
			end
			last_cpu_wall, last_cpu_clock = new_wall, new_clock;
			return math.ceil(pc);
		end;
		tostring = "%s%%";
	};
};

local add_statistics_filter; -- forward decl
if prosody and prosody.arg then -- ensures we aren't in prosodyctl
	setmetatable(active_sessions, {
		__index = function ( t, k )
			local v = {
				bytes_in = 0, bytes_out = 0;
				stanzas_in = {
					message = 0, presence = 0, iq = 0;
				};
				stanzas_out = {
					message = 0, presence = 0, iq = 0;
				};
			}
			rawset(t, k, v);
			return v;
		end
	});
	local filters = require "util.filters";
	local function handle_stanza_in(stanza, session)
		local s = active_sessions[session].stanzas_in;
		local n = s[stanza.name];
		if n then
			s[stanza.name] = n + 1;
		end
		return stanza;
	end
	local function handle_stanza_out(stanza, session)
		local s = active_sessions[session].stanzas_out;
		local n = s[stanza.name];
		if n then
			s[stanza.name] = n + 1;
		end
		return stanza;
	end
	local function handle_bytes_in(bytes, session)
		local s = active_sessions[session];
		s.bytes_in = s.bytes_in + #bytes;
		return bytes;
	end
	local function handle_bytes_out(bytes, session)
		local s = active_sessions[session];
		s.bytes_out = s.bytes_out + #bytes;
		return bytes;
	end
	function add_statistics_filter(session)
		filters.add_filter(session, "stanzas/in", handle_stanza_in);
		filters.add_filter(session, "stanzas/out", handle_stanza_out);
		filters.add_filter(session, "bytes/in", handle_bytes_in);
		filters.add_filter(session, "bytes/out", handle_bytes_out);
	end
end

return {
	stats = stats;
	active_sessions = active_sessions;
	filter_hook = add_statistics_filter;
};
