
local full_sessions = full_sessions;
local bare_sessions = bare_sessions;

local st = require "util.stanza";
local jid_bare = require "util.jid".bare;
local jid_split = require "util.jid".split;
local user_exists = require "core.usermanager".user_exists;
local urlencode = require "net.http".urlencode;
local add_task = require "util.timer".add_task;
local os_time = os.time;
local t_concat = table.concat;
local smtp = require "socket.smtp";

local smtp_server = module:get_option("smtp_server");
local smtp_user = module:get_option("smtp_username");
local smtp_pass = module:get_option("smtp_password");

local smtp_address = module:get_option("smtp_from") or ((smtp_user or "xmpp").."@"..(smtp_server or module.host));

local queue_offline_emails = module:get_option("queue_offline_emails");
if queue_offline_emails == true then queue_offline_emails = 300; end

local send_message_as_email;
local message_body_from_stanza;

function process_to_bare(bare, origin, stanza)
	local user = bare_sessions[bare];
	
	local t = stanza.attr.type;
	if t == nil or t == "chat" or t == "normal" then -- chat or normal message
		if not (user and user.top_resources) then -- No resources online?
			if user_exists(jid_split(bare)) then
				local text = message_body_from_stanza(stanza);
				if text then
					send_message_as_email(bare, jid_bare(stanza.attr.from), text);
				else
					module:log("error", "Unable to extract message body from offline message to put into an email");
				end
			end
		end
	end
	return; -- Leave for further processing
end


module:hook("message/full", function(data)
	-- message to full JID recieved
	local origin, stanza = data.origin, data.stanza;
	
	local session = full_sessions[stanza.attr.to];
	if not session then -- resource not online
		return process_to_bare(jid_bare(stanza.attr.to), origin, stanza);
	end
end, 20);

module:hook("message/bare", function(data)
	-- message to bare JID recieved
	local origin, stanza = data.origin, data.stanza;

	return process_to_bare(stanza.attr.to or (origin.username..'@'..origin.host), origin, stanza);
end, 20);

function send_message_as_email(address, from_address, message_text, subject)
		module:log("info", "Forwarding offline message to %s via email", address);
		local rcpt = "<"..address..">";
		local from_user, from_domain = jid_split(from_address);
		local from = "<"..urlencode(from_user).."@"..from_domain..">";
		
		local mesgt = {
			headers = {
				to = address;
				subject = subject or ("Offline message from "..jid_bare(from_address));
			};
			body = message_text;
		};
		
	local ok, err = smtp.send{ from = from, rcpt = rcpt, source = smtp.message(mesgt), 
		server = smtp_server, user = smtp_user, password = smtp_pass };
	if not ok then
		module:log("error", "Failed to deliver to %s: %s", tostring(address), tostring(err));
		return false;
	end
	return true;
end

if queue_offline_emails then
	local queues = {};
	local real_send_message_as_email = send_message_as_email;
	function send_message_as_email(address, from_address, message_text)
		local pair_key = address.."\0"..from_address;
		local queue = queues[pair_key];
		if not queue then
			queue = { from = from_address, to = address, messages = {} };
			queues[pair_key] = queue;
	
			add_task(queue_offline_emails+5, function () 
				module:log("info", "Checking on %s", from_address);
				local current_time = os_time();
				local diff = current_time - queue.last_message_time;
				if diff > queue_offline_emails then
					module:log("info", "Enough silence, sending...");
					real_send_message_as_email(address, from_address, t_concat(queue.messages, "\n"), "You have "..#queue.messages.." offline message"..(#queue.messages == 1 and "" or "s").." from "..from_address)
				else
					module:log("info", "Next check in %d", queue_offline_emails - diff + 5);
					return queue_offline_emails - diff + 5;
				end
			end);
		end
		
		queue.last_message_time = os_time();

		local messages = queue.messages;
		messages[#messages+1] = message_text;
	end
end

function message_body_from_stanza(stanza)
	local message_text = stanza:child_with_name("body");
	if message_text then
		return message_text:get_text();
	end
end
