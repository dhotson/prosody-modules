local captcha_options = module:get_option("captcha_options", {});
local nodeprep = require "util.encodings".stringprep.nodeprep;

function generate_captcha(display_options)
	return (([[
		<script type="text/javascript"
     		src="https://www.google.com/recaptcha/api/challenge?k=$$recaptcha_public_key$$">
  		</script>
  		<noscript>
     		<iframe src="https://www.google.com/recaptcha/api/noscript?k=$$recaptcha_public_key$$$$recaptcha_display_error$$"
         		height="300" width="500" frameborder="0"></iframe><br>
     		<textarea name="recaptcha_challenge_field" rows="3" cols="40">
     		</textarea>
     		<input type="hidden" name="recaptcha_response_field"
         		value="manual_challenge">
  		</noscript>
  	]]):gsub("$$([^$]+)$%$", setmetatable({
  		recaptcha_display_error = display_options and display_options.recaptcha_error
  			and ("&error="..display_options.recaptcha_error) or "";
  	}, {
  		__index = function (t, k)
  			if captcha_options[k] then return captcha_options[k]; end
  			module:log("error", "Missing parameter from captcha_options: %s", k);
  		end })
  	));
end

function generate_page(event, display_options)
	local request = event.request;
	return [[<!DOCTYPE html>
	<html><body>
	<h1>XMPP Account Registration</h1>
	<form action="]]..request.path..[[" method="POST">]]
	..("<p>%s</p>\n"):format((display_options or {}).register_error or "")..
	[[	<table>
		<tr>
			<td>Username:</td>
			<td><input type="text" name="username">@]]..module.host..[[</td>
		</tr>
		<tr>
			<td>Password:</td>
			<td><input type="password" name="password"></td>
		</tr>
		<tr>
			<td colspan='2'>]]..generate_captcha(display_options)..[[</td>
		</tr>
		</table>
		<input type="submit" value="Register!">
	</form>
	</body></html>]];
end

function register_user(form)
        local prepped_username = nodeprep(form.username);
        if usermanager.user_exists(prepped_username, module.host) then
                return nil, "user-exists";
        end
        return usermanager.create_user(prepped_username, form.password, module.host);
end

function generate_success(event, form)
	return [[<!DOCTYPE html>
	<html><body><p>Registration succeeded! Your account is <pre>]]
		..form.username.."@"..module.host..
	[[</pre> - happy chatting!</p></body></html>]];
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
			local register_ok, register_err = register_user(form);
			response:send(generate_register_response(event, form, register_ok, register_err));
		else
			response:send(generate_page(event, { register_error = verify_err }));
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
