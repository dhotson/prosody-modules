local captcha_options = module:get_option("captcha_options", {});
local nodeprep = require "util.encodings".stringprep.nodeprep;
local usermanager = require "core.usermanager";
local http = require "util.http";

function template(data)
	-- Like util.template, but deals with plain text
	return { apply = function(values) return (data:gsub("{([^}]+)}", values)); end }
end

local function get_template(name)
	local fh = assert(module:load_resource("templates/"..name..".html"));
	local data = assert(fh:read("*a"));
	fh:close();
	return template(data);
end

local function render(template, data)
	return tostring(template.apply(data));
end

local register_tpl = get_template "register";
local success_tpl = get_template "success";
local recaptcha_tpl = get_template "recaptcha";

function generate_captcha(display_options)
	return recaptcha_tpl.apply(setmetatable({
  		recaptcha_display_error = display_options and display_options.recaptcha_error
  			and ("&error="..display_options.recaptcha_error) or "";
  	}, {
  		__index = function (t, k)
  			if captcha_options[k] then return captcha_options[k]; end
  			module:log("error", "Missing parameter from captcha_options: %s", k);
		end
	}));
end
function verify_captcha(form, callback)
	http.request("https://www.google.com/recaptcha/api/verify", {
		body = http.formencode {
			privatekey = captcha_options.recaptcha_private_key;
			remoteip = request.conn:ip();
			challenge = form.recaptcha_challenge_field;
			response = form.recaptcha_response_field;
		};
	}, function (verify_result, code)
		local verify_ok, verify_err = verify_result:match("^([^\n]+)\n([^\n]+)");
		if verify_ok == "true" then
			callback(true);
		else
			callback(false, verify_err)
		end
	end);
end

function generate_page(event, display_options)
	local request = event.request;

	return render(register_tpl, {
		path = request.path; hostname = module.host;
		notice = display_options and display_options.register_error or "";
		captcha = generate_captcha(display_options);
	})
end

function register_user(form)
        local prepped_username = nodeprep(form.username);
        if usermanager.user_exists(prepped_username, module.host) then
                return nil, "user-exists";
        end
        return usermanager.create_user(prepped_username, form.password, module.host);
end

function generate_success(event, form)
	return render(success_tpl, { jid = nodeprep(form.username).."@"..module.host });
end

function generate_register_response(event, form, ok, err)
	local message;
	if ok then
		return generate_success(event, form);
	else
		return generate_page(event, { register_error = err });
	end
end

function handle_form(event)
	local request, response = event.request, event.response;
	local form = http.formdecode(request.body);
	verify_captcha(form, function (ok, err)
		if ok then
			local register_ok, register_err = register_user(form);
			response:send(generate_register_response(event, form, register_ok, register_err));
		else
			response:send(generate_page(event, { register_error = err }));
		end
	end);
	return true; -- Leave connection open until we respond above
end

module:provides("http", {
	route = {
		GET = generate_page;
		POST = handle_form;
	};
});
