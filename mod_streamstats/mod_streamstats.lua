local stats = prosody.stats;

if not stats then
	stats = {
		stats = {}; conns = {};
		
		broadcast = function (self, stat)
			local value = self.stats[stat];
			for conn in pairs(self.conns) do
				conn:write(stat..":"..value.."\n");
			end
		end;

		adjust = function (self, stat, delta)
			if delta == 0 then return; end
			self.stats[stat] = (self.stats[stat] or 0) + delta;
			self:broadcast(stat);
		end;

		set = function (self, stat, value)
			if value == self.stats[stat] then return; end
			self.stats[stat] = value;
			self:broadcast(stat);
		end;
		
		add_conn = function (self, conn)
			self.conns[conn] = true;
			for stat, value in pairs(self.stats) do
				conn:write(stat..":"..value.."\n");
			end
		end;
		
		remove_conn = function (self, conn)
			self.conns[conn] = nil;
		end;
	};
	prosody.stats = stats;
	
	local network = {};
	
	function network.onconnect(conn)
		stats:add_conn(conn);
	end
	
	function network.onincoming(conn, data)
	end
	
	function network.ondisconnect(conn, reason)
		stats:remove_conn(conn);
	end
	
	require "util.iterators";
	require "util.timer".add_task(1, function ()
		stats:set("s2s-in", count(keys(prosody.incoming_s2s)));
		return math.random(10, 20);
	end);
	require "util.timer".add_task(3, function ()
		local s2sout_count = 0;
		for _, host in pairs(prosody.hosts) do
			s2sout_count = s2sout_count + count(keys(host.s2sout));
		end
		stats:set("s2s-out", s2sout_count);
		return math.random(10, 20);
	end);
	
	require "net.connlisteners".register("stats", network);
	require "net.connlisteners".start("stats", { port = module:get_option("stats_ports") or 5444, interface = "127.0.0.1" });
end

module:hook("resource-bind", function ()
	stats:adjust("c2s", 1);
end);
module:hook("resource-unbind", function ()
	stats:adjust("c2s", -1);
end);

local c2s_count = 0;
for username, user in pairs(hosts[module.host].sessions or {}) do
	for resource, session in pairs(user.sessions or {}) do
		c2s_count = c2s_count + 1;
	end
end
stats:adjust("c2s", c2s_count);

module:hook("s2sin-established", function (event)
	stats:adjust("s2s-in", 1);
end);
module:hook("s2sin-destroyed", function (event)
	stats:adjust("s2s-in", -1);
end);
module:hook("s2sout-established", function (event)
	stats:adjust("s2s-out", 1);
end);
module:hook("s2sout-destroyed", function (event)
	stats:adjust("s2s-out", -1);
end);
