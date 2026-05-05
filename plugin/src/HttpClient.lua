local HttpService = game:GetService("HttpService")

local Constants = require(script.Parent.Constants)

local HttpClient = {}

function HttpClient.getServerUrl(plugin)
	local configuredValue = plugin:GetSetting(Constants.SERVER_URL_SETTING)

	if type(configuredValue) == "string" and configuredValue ~= "" then
		return configuredValue
	end

	return Constants.DEFAULT_SERVER_URL
end

function HttpClient.export(plugin, payload)
	local requestBody = HttpService:JSONEncode(payload)
	local requestUrl = HttpClient.getServerUrl(plugin)

	local ok, responseOrError = pcall(function()
		return HttpService:RequestAsync({
			Url = requestUrl,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
			},
			Body = requestBody,
		})
	end)

	if not ok then
		return false, ("HTTP request to %s failed: %s"):format(requestUrl, tostring(responseOrError))
	end

	local response = responseOrError

	if not response.Success then
		local message = response.StatusMessage or response.Body or "unknown error"
		return false, ("Exporter returned %d: %s"):format(response.StatusCode, message)
	end

	local decodeOk, decodedBody = pcall(function()
		if response.Body == nil or response.Body == "" then
			return {}
		end

		return HttpService:JSONDecode(response.Body)
	end)

	if not decodeOk then
		return false, "Exporter returned invalid JSON."
	end

	if decodedBody.ok == false then
		return false, decodedBody.error or "Exporter returned an error."
	end

	return true, decodedBody
end

return HttpClient
