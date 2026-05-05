local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local InsertService = game:GetService("InsertService")
local Selection = game:GetService("Selection")

local Constants = require(script.Constants)
local ExportSerializer = require(script.ExportSerializer)
local HttpClient = require(script.HttpClient)

local MESH_PART_ATTRIBUTE = "RojoMeshId"
local MESH_PART_COLLISION_ATTRIBUTE = "RojoCollisionFidelity"
local MESH_PART_RENDER_ATTRIBUTE = "RojoRenderFidelity"
local MESH_PART_SIZE_ATTRIBUTE = "RojoMeshSize"
local MESH_PART_TAG = "RojoMeshPart"
local STYLE_RULE_PROPERTIES_ATTRIBUTE = "RojoStyleProperties"
local STYLE_RULE_TRANSITIONS_ATTRIBUTE = "RojoStyleTransitions"
local STYLE_RULE_ORDER_ATTRIBUTE = "RojoStyleRuleOrder"
local STYLE_SHEET_DERIVES_ATTRIBUTE = "RojoStyleDerives"
local STYLE_LINK_ATTRIBUTE = "RojoStyleSheetRef"
local STYLE_RULE_TAG = "RojoStyleRule"
local STYLE_SHEET_TAG = "RojoStyleSheet"
local STYLE_LINK_TAG = "RojoStyleLink"

local meshPartConnections = {}
local meshPartUpdates = {}
local styleRuleConnections = {}
local styleRuleUpdates = {}
local styleSheetConnections = {}
local styleSheetUpdates = {}
local styleLinkConnections = {}
local styleLinkUpdates = {}
local styleReferenceRefreshQueued = false
local suppressedStyleInstances = {}

local toolbar = plugin:CreateToolbar(Constants.TOOLBAR_NAME)
local exportButton = toolbar:CreateButton(Constants.BUTTON_ID, Constants.BUTTON_TOOLTIP, "")
exportButton.ClickableWhenViewportHidden = true
local dedupedNameButton = toolbar:CreateButton(
	Constants.DEDUPED_NAME_BUTTON_ID,
	Constants.DEDUPED_NAME_BUTTON_TOOLTIP,
	""
)
dedupedNameButton.ClickableWhenViewportHidden = true

local function updateMeshPart(mesh)
	if mesh.Parent == nil then
		return
	end

	local meshId = mesh:GetAttribute(MESH_PART_ATTRIBUTE)
	if type(meshId) ~= "string" or meshId == "" then
		return
	end

	local collisionFidelityName = mesh:GetAttribute(MESH_PART_COLLISION_ATTRIBUTE)
	local renderFidelityName = mesh:GetAttribute(MESH_PART_RENDER_ATTRIBUTE)
	local desiredSize = mesh:GetAttribute(MESH_PART_SIZE_ATTRIBUTE)

	local collisionFidelity = mesh.CollisionFidelity
	if type(collisionFidelityName) == "string" and Enum.CollisionFidelity[collisionFidelityName] ~= nil then
		collisionFidelity = Enum.CollisionFidelity[collisionFidelityName]
	end

	local renderFidelity = mesh.RenderFidelity
	if type(renderFidelityName) == "string" and Enum.RenderFidelity[renderFidelityName] ~= nil then
		renderFidelity = Enum.RenderFidelity[renderFidelityName]
	end

	if typeof(desiredSize) ~= "Vector3" then
		desiredSize = mesh.Size
	end

	local meshIsLoaded = mesh.MeshId == meshId and mesh.MeshSize.Magnitude > 0
	local fidelityMatches = mesh.CollisionFidelity == collisionFidelity and mesh.RenderFidelity == renderFidelity

	if meshIsLoaded and fidelityMatches then
		if mesh.Size ~= desiredSize then
			local sizeOk, sizeError = pcall(function()
				mesh.Size = desiredSize
			end)

			if not sizeOk then
				warn(("[%s] Failed to restore size for %s: %s"):format(Constants.PLUGIN_NAME, mesh:GetFullName(), tostring(sizeError)))
			end
		end

		return
	end

	local success, applyMeshOrError = pcall(function()
		return InsertService:CreateMeshPartAsync(meshId, collisionFidelity, renderFidelity)
	end)

	if not success then
		warn(("[%s] Failed to create MeshPart %s from %s: %s"):format(Constants.PLUGIN_NAME, mesh:GetFullName(), meshId, tostring(applyMeshOrError)))
		return
	end

	if mesh.Parent == nil then
		return
	end

	if mesh:GetAttribute(MESH_PART_ATTRIBUTE) ~= meshId then
		return
	end

	if type(mesh:GetAttribute(MESH_PART_COLLISION_ATTRIBUTE)) == "string" and mesh:GetAttribute(MESH_PART_COLLISION_ATTRIBUTE) ~= collisionFidelity.Name then
		return
	end

	if type(mesh:GetAttribute(MESH_PART_RENDER_ATTRIBUTE)) == "string" and mesh:GetAttribute(MESH_PART_RENDER_ATTRIBUTE) ~= renderFidelity.Name then
		return
	end

	local latestDesiredSize = mesh:GetAttribute(MESH_PART_SIZE_ATTRIBUTE)
	if latestDesiredSize ~= nil and typeof(latestDesiredSize) ~= "Vector3" then
		return
	end

	if typeof(latestDesiredSize) == "Vector3" then
		desiredSize = latestDesiredSize
	end

	local applyOk, applyError = pcall(function()
		mesh:ApplyMesh(applyMeshOrError)
	end)

	if not applyOk then
		warn(("[%s] Failed to apply mesh for %s: %s"):format(Constants.PLUGIN_NAME, mesh:GetFullName(), tostring(applyError)))
		return
	end

	local propertyOk, propertyError = pcall(function()
		mesh.CollisionFidelity = collisionFidelity
		mesh.RenderFidelity = renderFidelity
		mesh.Size = desiredSize
	end)

	if not propertyOk then
		warn(("[%s] Failed to finalize MeshPart %s after apply: %s"):format(Constants.PLUGIN_NAME, mesh:GetFullName(), tostring(propertyError)))
	end
end

local function scheduleMeshUpdate(mesh)
	if meshPartUpdates[mesh] then
		return
	end

	meshPartUpdates[mesh] = true

	task.defer(function()
		meshPartUpdates[mesh] = nil
		updateMeshPart(mesh)
	end)
end

local function syncMeshAttribute(mesh)
	local meshId = mesh.MeshId

	if type(meshId) == "string" and meshId ~= "" and mesh:GetAttribute(MESH_PART_ATTRIBUTE) ~= meshId then
		mesh:SetAttribute(MESH_PART_ATTRIBUTE, meshId)
	end
end

local function disconnectMeshPart(instance)
	if not instance:IsA("MeshPart") then
		return
	end

	local connections = meshPartConnections[instance]
	if connections == nil then
		return
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	meshPartConnections[instance] = nil
	meshPartUpdates[instance] = nil
end

local function watchMeshPart(instance)
	if not instance:IsA("MeshPart") then
		return
	end

	if meshPartConnections[instance] ~= nil then
		return
	end

	meshPartConnections[instance] = {
		instance:GetAttributeChangedSignal(MESH_PART_ATTRIBUTE):Connect(function()
			scheduleMeshUpdate(instance)
		end),
		instance:GetAttributeChangedSignal(MESH_PART_COLLISION_ATTRIBUTE):Connect(function()
			scheduleMeshUpdate(instance)
		end),
		instance:GetAttributeChangedSignal(MESH_PART_RENDER_ATTRIBUTE):Connect(function()
			scheduleMeshUpdate(instance)
		end),
		instance:GetAttributeChangedSignal(MESH_PART_SIZE_ATTRIBUTE):Connect(function()
			scheduleMeshUpdate(instance)
		end),
		instance:GetPropertyChangedSignal("MeshId"):Connect(function()
			syncMeshAttribute(instance)
		end),
		instance:GetPropertyChangedSignal("CollisionFidelity"):Connect(function()
			scheduleMeshUpdate(instance)
		end),
		instance:GetPropertyChangedSignal("RenderFidelity"):Connect(function()
			scheduleMeshUpdate(instance)
		end),
		instance:GetPropertyChangedSignal("Size"):Connect(function()
			scheduleMeshUpdate(instance)
		end),
	}

	syncMeshAttribute(instance)
	task.spawn(updateMeshPart, instance)
end

local function decodeStyleValue(value)
	local kind = type(value)

	if kind == "boolean" or kind == "number" or kind == "string" then
		return value
	end

	if kind ~= "table" then
		return nil
	end

	local valueType = value["$type"]
	if valueType == "Array" then
		local items = value.items
		if type(items) ~= "table" then
			return nil
		end

		local result = {}
		for index, item in ipairs(items) do
			result[index] = decodeStyleValue(item)
		end

		return result
	end

	if valueType == "Map" then
		local entries = value.entries
		if type(entries) ~= "table" then
			return nil
		end

		local result = {}
		for key, nestedValue in pairs(entries) do
			result[key] = decodeStyleValue(nestedValue)
		end

		return result
	end

	if valueType == "EnumItem" then
		local enumGroup = Enum[value.enumType]
		if enumGroup == nil then
			return nil
		end

		return enumGroup[value.name]
	end

	if valueType == "Vector2" then
		return Vector2.new(value.x, value.y)
	end

	if valueType == "Vector3" then
		return Vector3.new(value.x, value.y, value.z)
	end

	if valueType == "Color3" then
		return Color3.new(value.r, value.g, value.b)
	end

	if valueType == "BrickColor" then
		return BrickColor.new(value.number)
	end

	if valueType == "UDim" then
		return UDim.new(value.scale, value.offset)
	end

	if valueType == "UDim2" then
		return UDim2.new(value.xScale, value.xOffset, value.yScale, value.yOffset)
	end

	if valueType == "CFrame" then
		local orientation = value.orientation
		if type(orientation) ~= "table" then
			return nil
		end

		return CFrame.new(
			value.x,
			value.y,
			value.z,
			orientation[1][1],
			orientation[1][2],
			orientation[1][3],
			orientation[2][1],
			orientation[2][2],
			orientation[2][3],
			orientation[3][1],
			orientation[3][2],
			orientation[3][3]
		)
	end

	if valueType == "Font" then
		local weightGroup = Enum.FontWeight
		local styleGroup = Enum.FontStyle
		if weightGroup == nil or styleGroup == nil then
			return nil
		end

		local weight = weightGroup[value.weight]
		local style = styleGroup[value.style]
		if weight == nil or style == nil then
			return nil
		end

		return Font.new(value.family, weight, style)
	end

	if valueType == "NumberRange" then
		return NumberRange.new(value.min, value.max)
	end

	if valueType == "ColorSequence" then
		local keypoints = {}
		for _, keypoint in ipairs(value.keypoints or {}) do
			local color = keypoint.color
			if type(color) ~= "table" then
				return nil
			end

			table.insert(keypoints, ColorSequenceKeypoint.new(keypoint.time, Color3.new(color[1], color[2], color[3])))
		end

		return ColorSequence.new(keypoints)
	end

	if valueType == "NumberSequence" then
		local keypoints = {}
		for _, keypoint in ipairs(value.keypoints or {}) do
			table.insert(keypoints, NumberSequenceKeypoint.new(keypoint.time, keypoint.value, keypoint.envelope))
		end

		return NumberSequence.new(keypoints)
	end

	if valueType == "Rect" then
		return Rect.new(value.minX, value.minY, value.maxX, value.maxY)
	end

	if valueType == "Ray" then
		return Ray.new(
			Vector3.new(value.origin.x, value.origin.y, value.origin.z),
			Vector3.new(value.direction.x, value.direction.y, value.direction.z)
		)
	end

	if valueType == "PhysicalProperties" then
		return PhysicalProperties.new(
			value.density,
			value.friction,
			value.elasticity,
			value.frictionWeight,
			value.elasticityWeight
		)
	end

	if valueType == "Faces" then
		return Faces.new(value.right, value.top, value.back, value.left, value.bottom, value.front)
	end

	if valueType == "Axes" then
		return Axes.new(value.x, value.y, value.z)
	end

	return nil
end

local function decodeStyleJsonAttribute(instance, attributeName)
	local encoded = instance:GetAttribute(attributeName)
	if type(encoded) ~= "string" or encoded == "" then
		return nil
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(encoded)
	end)

	if not ok then
		warn(("[%s] Failed to decode %s on %s: %s"):format(Constants.PLUGIN_NAME, attributeName, instance:GetFullName(), tostring(decoded)))
		return nil
	end

	local decodeOk, decodedValue = pcall(function()
		return decodeStyleValue(decoded)
	end)

	if not decodeOk then
		warn(("[%s] Failed to interpret %s on %s: %s"):format(Constants.PLUGIN_NAME, attributeName, instance:GetFullName(), tostring(decodedValue)))
		return nil
	end

	return decodedValue
end

local function splitPath(path)
	local segments = {}
	for segment in string.gmatch(path, "[^%.]+") do
		table.insert(segments, segment)
	end

	return segments
end

local function resolveInstancePath(pathData)
	local segments = nil

	if type(pathData) == "string" and pathData ~= "" then
		segments = splitPath(pathData)
	elseif type(pathData) == "table" then
		segments = pathData
	else
		return nil
	end

	local current = game
	for _, segment in ipairs(segments) do
		current = current:FindFirstChild(segment)
		if current == nil then
			return nil
		end
	end

	return current
end

local function isStyleInstanceSuppressed(instance)
	return suppressedStyleInstances[instance] == true
end

local function setStyleInstanceSuppressed(instance, suppressed)
	if suppressed then
		suppressedStyleInstances[instance] = true
	else
		suppressedStyleInstances[instance] = nil
	end
end

local function hasOrderedStyleRuleChildren(container, orderedRuleNames)
	local childIndex = 1

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("StyleRule") then
			if orderedRuleNames[childIndex] ~= child.Name then
				return false
			end

			childIndex += 1
		end
	end

	return childIndex - 1 == #orderedRuleNames
end

local function reorderStyleRuleChildren(container, orderedRuleNames)
	if type(orderedRuleNames) ~= "table" or #orderedRuleNames == 0 then
		return false
	end

	if hasOrderedStyleRuleChildren(container, orderedRuleNames) then
		return false
	end

	local matchingChildrenByName = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("StyleRule") then
			if matchingChildrenByName[child.Name] ~= nil then
				return false
			end

			matchingChildrenByName[child.Name] = child
		end
	end

	local orderedChildren = {}
	local consumedChildren = {}

	for _, childName in ipairs(orderedRuleNames) do
		local child = matchingChildrenByName[childName]
		if child == nil then
			return false
		end

		table.insert(orderedChildren, child)
		consumedChildren[child] = true
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("StyleRule") and not consumedChildren[child] then
			table.insert(orderedChildren, child)
		end
	end

	setStyleInstanceSuppressed(container, true)
	for _, child in ipairs(orderedChildren) do
		setStyleInstanceSuppressed(child, true)
	end

	local ok, err = pcall(function()
		for _, child in ipairs(orderedChildren) do
			child.Parent = nil
		end

		for _, child in ipairs(orderedChildren) do
			child.Parent = container
		end
	end)

	for _, child in ipairs(orderedChildren) do
		setStyleInstanceSuppressed(child, false)
	end
	setStyleInstanceSuppressed(container, false)

	if not ok then
		warn(("[%s] Failed to reorder style children for %s: %s"):format(Constants.PLUGIN_NAME, container:GetFullName(), tostring(err)))
		return false
	end

	return true
end

local function updateStyleRule(rule)
	if rule.Parent == nil or not rule:IsA("StyleRule") then
		return
	end

	local properties = decodeStyleJsonAttribute(rule, STYLE_RULE_PROPERTIES_ATTRIBUTE)
	if type(properties) == "table" then
		local ok, errorMessage = pcall(function()
			rule:SetProperties(properties)
		end)

		if not ok then
			warn(("[%s] Failed to restore style properties for %s: %s"):format(Constants.PLUGIN_NAME, rule:GetFullName(), tostring(errorMessage)))
		end
	end

	local transitions = decodeStyleJsonAttribute(rule, STYLE_RULE_TRANSITIONS_ATTRIBUTE)
	if type(transitions) == "table" then
		local ok, errorMessage = pcall(function()
			rule:SetPropertyTransitions(transitions)
		end)

		if not ok then
			warn(("[%s] Failed to restore style transitions for %s: %s"):format(Constants.PLUGIN_NAME, rule:GetFullName(), tostring(errorMessage)))
		end
	end

	local orderedRuleNames = decodeStyleJsonAttribute(rule, STYLE_RULE_ORDER_ATTRIBUTE)
	if type(orderedRuleNames) == "table" and #orderedRuleNames > 0 then
		reorderStyleRuleChildren(rule, orderedRuleNames)

		local orderedRules = {}

		for _, childName in ipairs(orderedRuleNames) do
			local child = rule:FindFirstChild(childName)
			if child == nil or not child:IsA("StyleRule") then
				return
			end

			table.insert(orderedRules, child)
		end

		local ok, errorMessage = pcall(function()
			rule:SetStyleRules(orderedRules)
		end)

		if not ok then
			warn(("[%s] Failed to restore nested style rule order for %s: %s"):format(Constants.PLUGIN_NAME, rule:GetFullName(), tostring(errorMessage)))
		end
	end
end

local function scheduleStyleRuleUpdate(rule)
	if styleRuleUpdates[rule] then
		return
	end

	styleRuleUpdates[rule] = true

	task.defer(function()
		styleRuleUpdates[rule] = nil
		updateStyleRule(rule)
	end)
end

local function updateStyleSheet(sheet)
	if sheet.Parent == nil or not sheet:IsA("StyleSheet") then
		return
	end

	local derives = decodeStyleJsonAttribute(sheet, STYLE_SHEET_DERIVES_ATTRIBUTE)
	if type(derives) == "table" then
		local resolved = {}

		for _, path in ipairs(derives) do
			local target = resolveInstancePath(path)
			if target ~= nil and target:IsA("StyleSheet") then
				table.insert(resolved, target)
			else
				return
			end
		end

		local ok, errorMessage = pcall(function()
			sheet:SetDerives(resolved)
		end)

		if not ok then
			warn(("[%s] Failed to restore derives for %s: %s"):format(Constants.PLUGIN_NAME, sheet:GetFullName(), tostring(errorMessage)))
		end
	end

	local orderedRuleNames = decodeStyleJsonAttribute(sheet, STYLE_RULE_ORDER_ATTRIBUTE)
	if type(orderedRuleNames) == "table" and #orderedRuleNames > 0 then
		reorderStyleRuleChildren(sheet, orderedRuleNames)

		local orderedRules = {}

		for _, childName in ipairs(orderedRuleNames) do
			local child = sheet:FindFirstChild(childName)
			if child == nil or not child:IsA("StyleRule") then
				return
			end

			table.insert(orderedRules, child)
		end

		local ok, errorMessage = pcall(function()
			sheet:SetStyleRules(orderedRules)
		end)

		if not ok then
			warn(("[%s] Failed to restore style rule order for %s: %s"):format(Constants.PLUGIN_NAME, sheet:GetFullName(), tostring(errorMessage)))
		end
	end

end

local function scheduleStyleSheetUpdate(sheet)
	if styleSheetUpdates[sheet] then
		return
	end

	styleSheetUpdates[sheet] = true

	task.defer(function()
		styleSheetUpdates[sheet] = nil
		updateStyleSheet(sheet)
	end)
end

local function updateStyleLink(styleLink)
	if styleLink.Parent == nil or not styleLink:IsA("StyleLink") then
		return
	end

	local targetPath = decodeStyleJsonAttribute(styleLink, STYLE_LINK_ATTRIBUTE)
	if targetPath == nil then
		return
	end

	local target = resolveInstancePath(targetPath)
	if target == nil or not target:IsA("StyleSheet") then
		return
	end

	local ok, errorMessage = pcall(function()
		styleLink.StyleSheet = target
	end)

	if not ok then
		warn(("[%s] Failed to restore StyleLink target for %s: %s"):format(Constants.PLUGIN_NAME, styleLink:GetFullName(), tostring(errorMessage)))
	end
end

local function scheduleStyleLinkUpdate(styleLink)
	if styleLinkUpdates[styleLink] then
		return
	end

	styleLinkUpdates[styleLink] = true

	task.defer(function()
		styleLinkUpdates[styleLink] = nil
		updateStyleLink(styleLink)
	end)
end

local function scheduleStyleReferenceRefresh()
	if styleReferenceRefreshQueued then
		return
	end

	styleReferenceRefreshQueued = true

	task.defer(function()
		styleReferenceRefreshQueued = false

		for _, sheet in ipairs(CollectionService:GetTagged(STYLE_SHEET_TAG)) do
			scheduleStyleSheetUpdate(sheet)
		end

		for _, styleLink in ipairs(CollectionService:GetTagged(STYLE_LINK_TAG)) do
			scheduleStyleLinkUpdate(styleLink)
		end
	end)
end

local function disconnectStyleRule(instance)
	if not instance:IsA("StyleRule") then
		return
	end

	if isStyleInstanceSuppressed(instance) then
		return
	end

	local connections = styleRuleConnections[instance]
	if connections == nil then
		return
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	styleRuleConnections[instance] = nil
	styleRuleUpdates[instance] = nil
end

local function watchStyleRule(instance)
	if not instance:IsA("StyleRule") or styleRuleConnections[instance] ~= nil then
		return
	end

	styleRuleConnections[instance] = {
		instance:GetAttributeChangedSignal(STYLE_RULE_PROPERTIES_ATTRIBUTE):Connect(function()
			if isStyleInstanceSuppressed(instance) then
				return
			end
			scheduleStyleRuleUpdate(instance)
		end),
		instance:GetAttributeChangedSignal(STYLE_RULE_TRANSITIONS_ATTRIBUTE):Connect(function()
			if isStyleInstanceSuppressed(instance) then
				return
			end
			scheduleStyleRuleUpdate(instance)
		end),
		instance:GetAttributeChangedSignal(STYLE_RULE_ORDER_ATTRIBUTE):Connect(function()
			if isStyleInstanceSuppressed(instance) then
				return
			end
			scheduleStyleRuleUpdate(instance)
		end),
		instance.ChildAdded:Connect(function()
			if isStyleInstanceSuppressed(instance) then
				return
			end
			scheduleStyleRuleUpdate(instance)
		end),
		instance.ChildRemoved:Connect(function()
			if isStyleInstanceSuppressed(instance) then
				return
			end
			scheduleStyleRuleUpdate(instance)
		end),
		instance.AncestryChanged:Connect(function()
			if isStyleInstanceSuppressed(instance) then
				return
			end
			scheduleStyleRuleUpdate(instance)
			scheduleStyleReferenceRefresh()
		end),
	}

	scheduleStyleRuleUpdate(instance)
	scheduleStyleReferenceRefresh()
end

local function disconnectStyleSheet(instance)
	if not instance:IsA("StyleSheet") then
		return
	end

	if isStyleInstanceSuppressed(instance) then
		return
	end

	local connections = styleSheetConnections[instance]
	if connections == nil then
		return
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	styleSheetConnections[instance] = nil
	styleSheetUpdates[instance] = nil
end

local function watchStyleSheet(instance)
	if not instance:IsA("StyleSheet") or styleSheetConnections[instance] ~= nil then
		return
	end

	styleSheetConnections[instance] = {
		instance:GetAttributeChangedSignal(STYLE_SHEET_DERIVES_ATTRIBUTE):Connect(function()
			if isStyleInstanceSuppressed(instance) then
				return
			end
			scheduleStyleSheetUpdate(instance)
			scheduleStyleReferenceRefresh()
		end),
		instance:GetAttributeChangedSignal(STYLE_RULE_ORDER_ATTRIBUTE):Connect(function()
			if isStyleInstanceSuppressed(instance) then
				return
			end
			scheduleStyleSheetUpdate(instance)
		end),
		instance.ChildAdded:Connect(function()
			if isStyleInstanceSuppressed(instance) then
				return
			end
			scheduleStyleSheetUpdate(instance)
		end),
		instance.ChildRemoved:Connect(function()
			if isStyleInstanceSuppressed(instance) then
				return
			end
			scheduleStyleSheetUpdate(instance)
		end),
		instance.AncestryChanged:Connect(function()
			if isStyleInstanceSuppressed(instance) then
				return
			end
			scheduleStyleSheetUpdate(instance)
			scheduleStyleReferenceRefresh()
		end),
	}

	scheduleStyleSheetUpdate(instance)
	scheduleStyleReferenceRefresh()
end

local function disconnectStyleLink(instance)
	if not instance:IsA("StyleLink") then
		return
	end

	local connections = styleLinkConnections[instance]
	if connections == nil then
		return
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	styleLinkConnections[instance] = nil
	styleLinkUpdates[instance] = nil
end

local function watchStyleLink(instance)
	if not instance:IsA("StyleLink") or styleLinkConnections[instance] ~= nil then
		return
	end

	styleLinkConnections[instance] = {
		instance:GetAttributeChangedSignal(STYLE_LINK_ATTRIBUTE):Connect(function()
			scheduleStyleLinkUpdate(instance)
			scheduleStyleReferenceRefresh()
		end),
		instance.AncestryChanged:Connect(function()
			scheduleStyleLinkUpdate(instance)
			scheduleStyleReferenceRefresh()
		end),
	}

	scheduleStyleLinkUpdate(instance)
	scheduleStyleReferenceRefresh()
end

local function emitWarnings(warnings)
	if type(warnings) ~= "table" then
		return
	end

	for _, warningMessage in ipairs(warnings) do
		warn(("[%s] %s"):format(Constants.PLUGIN_NAME, warningMessage))
	end
end

local function exportSelection(preserveOriginalDuplicateNames)
	local payload, serializerWarningsOrError = ExportSerializer.serializeSelection(Selection:Get())

	if payload == nil then
		warn(("[%s] %s"):format(Constants.PLUGIN_NAME, serializerWarningsOrError))
		return
	end

	payload.version = Constants.FORMAT_VERSION
	payload.preserveOriginalDuplicateNames = preserveOriginalDuplicateNames

	local ok, responseOrError = HttpClient.export(plugin, payload)

	emitWarnings(serializerWarningsOrError)

	if not ok then
		warn(("[%s] %s"):format(Constants.PLUGIN_NAME, responseOrError))
		return
	end

	emitWarnings(responseOrError.warnings)

	local outputPath = responseOrError.bundlePath or responseOrError.outputPath or "the configured exporter output directory"
	print(("[%s] Exported %d root instance(s) to %s"):format(Constants.PLUGIN_NAME, #payload.selection, outputPath))

	if type(responseOrError.projectFiles) == "table" and #responseOrError.projectFiles > 0 then
		for _, projectFile in ipairs(responseOrError.projectFiles) do
			print(("[%s] Project file: %s"):format(Constants.PLUGIN_NAME, projectFile))
		end
		return
	end

	if type(responseOrError.projectFile) == "string" and responseOrError.projectFile ~= "" then
		print(("[%s] Project file: %s"):format(Constants.PLUGIN_NAME, responseOrError.projectFile))
	end
end

exportButton.Click:Connect(function()
	exportSelection(true)
end)

dedupedNameButton.Click:Connect(function()
	exportSelection(false)
end)

CollectionService:GetInstanceAddedSignal(MESH_PART_TAG):Connect(watchMeshPart)
CollectionService:GetInstanceRemovedSignal(MESH_PART_TAG):Connect(disconnectMeshPart)
CollectionService:GetInstanceAddedSignal(STYLE_RULE_TAG):Connect(watchStyleRule)
CollectionService:GetInstanceRemovedSignal(STYLE_RULE_TAG):Connect(disconnectStyleRule)
CollectionService:GetInstanceAddedSignal(STYLE_SHEET_TAG):Connect(watchStyleSheet)
CollectionService:GetInstanceRemovedSignal(STYLE_SHEET_TAG):Connect(disconnectStyleSheet)
CollectionService:GetInstanceAddedSignal(STYLE_LINK_TAG):Connect(watchStyleLink)
CollectionService:GetInstanceRemovedSignal(STYLE_LINK_TAG):Connect(disconnectStyleLink)

for _, instance in ipairs(CollectionService:GetTagged(MESH_PART_TAG)) do
	task.spawn(watchMeshPart, instance)
end

for _, instance in ipairs(CollectionService:GetTagged(STYLE_RULE_TAG)) do
	task.spawn(watchStyleRule, instance)
end

for _, instance in ipairs(CollectionService:GetTagged(STYLE_SHEET_TAG)) do
	task.spawn(watchStyleSheet, instance)
end

for _, instance in ipairs(CollectionService:GetTagged(STYLE_LINK_TAG)) do
	task.spawn(watchStyleLink, instance)
end
