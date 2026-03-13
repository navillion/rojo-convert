local CollectionService = game:GetService("CollectionService")
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

local meshPartConnections = {}
local meshPartUpdates = {}

local toolbar = plugin:CreateToolbar(Constants.TOOLBAR_NAME)
local button = toolbar:CreateButton(Constants.BUTTON_ID, Constants.BUTTON_TOOLTIP, "")
button.ClickableWhenViewportHidden = true

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

button.Click:Connect(exportSelection)

CollectionService:GetInstanceAddedSignal(MESH_PART_TAG):Connect(watchMeshPart)
CollectionService:GetInstanceRemovedSignal(MESH_PART_TAG):Connect(disconnectMeshPart)

for _, instance in ipairs(CollectionService:GetTagged(MESH_PART_TAG)) do
	task.spawn(watchMeshPart, instance)
end
