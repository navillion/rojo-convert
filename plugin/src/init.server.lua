local Selection = game:GetService("Selection")

local Constants = require(script.Constants)
local ExportSerializer = require(script.ExportSerializer)
local HttpClient = require(script.HttpClient)

local toolbar = plugin:CreateToolbar(Constants.TOOLBAR_NAME)
local button = toolbar:CreateButton(Constants.BUTTON_ID, Constants.BUTTON_TOOLTIP, "")
button.ClickableWhenViewportHidden = true

local function emitWarnings(warnings)
	if type(warnings) ~= "table" then
		return
	end

	for _, warningMessage in ipairs(warnings) do
		warn(("[%s] %s"):format(Constants.PLUGIN_NAME, warningMessage))
	end
end

local function exportSelection()
	local payload, serializerWarningsOrError = ExportSerializer.serializeSelection(Selection:Get())

	if payload == nil then
		warn(("[%s] %s"):format(Constants.PLUGIN_NAME, serializerWarningsOrError))
		return
	end

	payload.version = Constants.FORMAT_VERSION

	local ok, responseOrError = HttpClient.export(plugin, payload)

	emitWarnings(serializerWarningsOrError)

	if not ok then
		warn(("[%s] %s"):format(Constants.PLUGIN_NAME, responseOrError))
		return
	end

	emitWarnings(responseOrError.warnings)

	local outputPath = responseOrError.bundlePath or responseOrError.outputPath or "the configured exporter output directory"
	print(("[%s] Exported %d root instance(s) to %s"):format(Constants.PLUGIN_NAME, #payload.selection, outputPath))

	if type(responseOrError.projectFile) == "string" and responseOrError.projectFile ~= "" then
		print(("[%s] Project file: %s"):format(Constants.PLUGIN_NAME, responseOrError.projectFile))
	end
end

button.Click:Connect(exportSelection)

