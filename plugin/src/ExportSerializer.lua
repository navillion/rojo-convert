local HttpService = game:GetService("HttpService")

local ExportSerializer = {}

local SCRIPT_FILE_CLASSES = {
	Script = true,
	LocalScript = true,
	ModuleScript = true,
}

local MESH_PART_ATTRIBUTE = "RojoMeshId"
local MESH_PART_COLLISION_ATTRIBUTE = "RojoCollisionFidelity"
local MESH_PART_RENDER_ATTRIBUTE = "RojoRenderFidelity"
local MESH_PART_SIZE_ATTRIBUTE = "RojoMeshSize"
local MESH_PART_TAG = "RojoMeshPart"

local ALWAYS_INCLUDE_PROPERTIES = {
	MeshPart = {
		CollisionFidelity = true,
		MeshId = true,
		RenderFidelity = true,
		Size = true,
		TextureID = true,
	},
}

local OMITTED_PROPERTIES = {
	Attributes = true,
	AttributesReplicate = true,
	AttributesSerialize = true,
	ClassName = true,
	HistoryId = true,
	LinkedSource = true,
	Name = true,
	Parent = true,
	Source = true,
	SourceAssetId = true,
	Tags = true,
	UniqueId = true,
}

local FALLBACK_PROPERTIES = {
	Script = { "Disabled", "RunContext" },
	LocalScript = { "Disabled" },
	ModuleScript = {},
	Folder = {},
	Model = { "LevelOfDetail", "ModelStreamingMode", "PrimaryPart", "WorldPivot" },
	Tool = {
		"CanBeDropped",
		"Enabled",
		"Grip",
		"GripForward",
		"GripPos",
		"GripRight",
		"GripUp",
		"ManualActivationOnly",
		"RequiresHandle",
		"TextureId",
		"ToolTip",
	},
	Configuration = {},
	RemoteEvent = {},
	RemoteFunction = {},
	BindableEvent = {},
	BindableFunction = {},
	BoolValue = { "Value" },
	IntValue = { "Value" },
	NumberValue = { "Value" },
	StringValue = { "Value" },
	ObjectValue = { "Value" },
	Vector3Value = { "Value" },
	CFrameValue = { "Value" },
	Color3Value = { "Value" },
	BrickColorValue = { "Value" },
	RayValue = { "Value" },
	Part = {
		"Anchored",
		"CanCollide",
		"CanQuery",
		"CanTouch",
		"CastShadow",
		"Color",
		"Material",
		"Reflectance",
		"Shape",
		"Size",
		"Transparency",
	},
		MeshPart = {
			"Anchored",
			"CanCollide",
			"CanQuery",
			"CanTouch",
			"CollisionFidelity",
			"CastShadow",
			"Color",
			"DoubleSided",
			"Material",
			"MeshId",
			"RenderFidelity",
			"Reflectance",
			"Size",
			"TextureID",
			"Transparency",
	},
}

local PROPERTY_CACHE = {}

local reflectionService = nil
pcall(function()
	reflectionService = game:GetService("ReflectionService")
end)

local function isFiniteNumber(value)
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function makeWarning(path, propertyName, message)
	return ("%s.%s skipped: %s"):format(path, propertyName, message)
end

local function extractPropertyName(descriptor, key)
	if type(descriptor) == "string" then
		return descriptor
	end

	if type(descriptor) ~= "table" then
		if type(key) == "string" then
			return key
		end

		return nil
	end

	return descriptor.Name or descriptor.name or descriptor.Property or descriptor.property or descriptor.Member or descriptor.member
end

local function extractValueType(descriptor)
	if type(descriptor) ~= "table" then
		return nil
	end

	local valueType = descriptor.ValueType or descriptor.valueType or descriptor.Type or descriptor.type

	if type(valueType) == "string" then
		return valueType
	end

	if type(valueType) ~= "table" then
		return nil
	end

	return valueType.Name or valueType.name or valueType.Category or valueType.category
end

local function getPropertyDescriptors(className)
	if PROPERTY_CACHE[className] ~= nil then
		return PROPERTY_CACHE[className]
	end

	local descriptors = {}

	if reflectionService ~= nil then
		local ok, result = pcall(function()
			return reflectionService:GetPropertiesOfClass(className, {})
		end)

		if not ok then
			ok, result = pcall(function()
				return reflectionService:GetPropertiesOfClass(className)
			end)
		end

		if ok and type(result) == "table" then
			for key, descriptor in pairs(result) do
				local name = extractPropertyName(descriptor, key)

				if name ~= nil and not OMITTED_PROPERTIES[name] then
					table.insert(descriptors, {
						name = name,
						valueType = extractValueType(descriptor),
					})
				end
			end
		end
	end

	if #descriptors == 0 then
		local fallbackNames = FALLBACK_PROPERTIES[className] or {}

		for _, name in ipairs(fallbackNames) do
			table.insert(descriptors, {
				name = name,
				valueType = nil,
			})
		end
	end

	table.sort(descriptors, function(left, right)
		return left.name < right.name
	end)

	PROPERTY_CACHE[className] = descriptors
	return descriptors
end

local function cframeImplicit(value)
	return { value:GetComponents() }
end

local function cframeExplicit(value)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = value:GetComponents()

	return {
		CFrame = {
			position = { x, y, z },
			orientation = {
				{ r00, r01, r02 },
				{ r10, r11, r12 },
				{ r20, r21, r22 },
			},
		},
	}
end

local function colorSequenceExplicit(value)
	local keypoints = {}

	for _, keypoint in ipairs(value.Keypoints) do
		table.insert(keypoints, {
			time = keypoint.Time,
			color = {
				keypoint.Value.R,
				keypoint.Value.G,
				keypoint.Value.B,
			},
		})
	end

	return {
		ColorSequence = {
			keypoints = keypoints,
		},
	}
end

local function numberSequenceExplicit(value)
	local keypoints = {}

	for _, keypoint in ipairs(value.Keypoints) do
		table.insert(keypoints, {
			time = keypoint.Time,
			value = keypoint.Value,
			envelope = keypoint.Envelope,
		})
	end

	return {
		NumberSequence = {
			keypoints = keypoints,
		},
	}
end

local function rectExplicit(value)
	return {
		Rect = {
			{ value.Min.X, value.Min.Y },
			{ value.Max.X, value.Max.Y },
		},
	}
end

local function rayExplicit(value)
	return {
		Ray = {
			origin = {
				value.Origin.X,
				value.Origin.Y,
				value.Origin.Z,
			},
			direction = {
				value.Direction.X,
				value.Direction.Y,
				value.Direction.Z,
			},
		},
	}
end

local function physicalPropertiesExplicit(value)
	return {
		PhysicalProperties = {
			density = value.Density,
			friction = value.Friction,
			elasticity = value.Elasticity,
			frictionWeight = value.FrictionWeight,
			elasticityWeight = value.ElasticityWeight,
		},
	}
end

local function fontImplicit(value)
	return {
		family = value.Family,
		weight = value.Weight.Name,
		style = value.Style.Name,
	}
end

local function fontExplicit(value)
	return {
		Font = fontImplicit(value),
	}
end

local function facesExplicit(value)
	local result = {}

	if value.Right then
		table.insert(result, "Right")
	end
	if value.Top then
		table.insert(result, "Top")
	end
	if value.Back then
		table.insert(result, "Back")
	end
	if value.Left then
		table.insert(result, "Left")
	end
	if value.Bottom then
		table.insert(result, "Bottom")
	end
	if value.Front then
		table.insert(result, "Front")
	end

	return {
		Faces = result,
	}
end

local function axesExplicit(value)
	local result = {}

	if value.X then
		table.insert(result, "X")
	end
	if value.Y then
		table.insert(result, "Y")
	end
	if value.Z then
		table.insert(result, "Z")
	end

	return {
		Axes = result,
	}
end

local function encodePropertyValue(value, explicitTypeName)
	local kind = typeof(value)

	if kind == "boolean" then
		return value
	end

	if kind == "number" then
		if not isFiniteNumber(value) then
			return nil, "contains a non-finite number"
		end

		return value
	end

	if kind == "string" then
		if explicitTypeName == "BinaryString" then
			return {
				BinaryString = HttpService:Base64Encode(value),
			}
		end

		return value
	end

	if kind == "EnumItem" then
		return value.Name
	end

	if kind == "Vector2" then
		return { value.X, value.Y }
	end

	if kind == "Vector2int16" then
		return { value.X, value.Y }
	end

	if kind == "Vector3" then
		return { value.X, value.Y, value.Z }
	end

	if kind == "Vector3int16" then
		return { value.X, value.Y, value.Z }
	end

	if kind == "Color3" then
		if explicitTypeName == "Color3uint8" then
			return {
				Color3uint8 = {
					math.floor(value.R * 255 + 0.5),
					math.floor(value.G * 255 + 0.5),
					math.floor(value.B * 255 + 0.5),
				},
			}
		end

		return { value.R, value.G, value.B }
	end

	if kind == "CFrame" then
		return cframeImplicit(value)
	end

	if kind == "BrickColor" then
		return {
			BrickColor = value.Number,
		}
	end

	if kind == "UDim" then
		return {
			UDim = {
				value.Scale,
				value.Offset,
			},
		}
	end

	if kind == "UDim2" then
		return {
			UDim2 = {
				{ value.X.Scale, value.X.Offset },
				{ value.Y.Scale, value.Y.Offset },
			},
		}
	end

	if kind == "NumberRange" then
		return {
			NumberRange = {
				value.Min,
				value.Max,
			},
		}
	end

	if kind == "NumberSequence" then
		return numberSequenceExplicit(value)
	end

	if kind == "ColorSequence" then
		return colorSequenceExplicit(value)
	end

	if kind == "Rect" then
		return rectExplicit(value)
	end

	if kind == "Ray" then
		return rayExplicit(value)
	end

	if kind == "PhysicalProperties" then
		return physicalPropertiesExplicit(value)
	end

	if kind == "Faces" then
		return facesExplicit(value)
	end

	if kind == "Axes" then
		return axesExplicit(value)
	end

	if kind == "Font" then
		return fontImplicit(value)
	end

	if kind == "Instance" then
		return nil, "Rojo project and meta files do not support Ref properties"
	end

	if explicitTypeName == "MaterialColors" then
		return nil, "MaterialColors properties are not emitted by this exporter"
	end

	if explicitTypeName == "OptionalCoordinateFrame" then
		return nil, "OptionalCoordinateFrame properties are not emitted by this exporter"
	end

	if explicitTypeName == "Region3" or explicitTypeName == "Region3int16" or explicitTypeName == "SharedString" then
		return nil, ("%s is not supported in Rojo project/meta files"):format(explicitTypeName)
	end

	return nil, ("unsupported value type %s"):format(kind)
end

local function encodeAttributeValue(value)
	local kind = typeof(value)

	if kind == "boolean" then
		return { Bool = value }
	end

	if kind == "number" then
		if not isFiniteNumber(value) then
			return nil, "contains a non-finite number"
		end

		return { Float64 = value }
	end

	if kind == "string" then
		return { String = value }
	end

	if kind == "BrickColor" then
		return { BrickColor = value.Number }
	end

	if kind == "CFrame" then
		return cframeExplicit(value)
	end

	if kind == "Color3" then
		return {
			Color3 = {
				value.R,
				value.G,
				value.B,
			},
		}
	end

	if kind == "ColorSequence" then
		return colorSequenceExplicit(value)
	end

	if kind == "Font" then
		return fontExplicit(value)
	end

	if kind == "NumberRange" then
		return {
			NumberRange = {
				value.Min,
				value.Max,
			},
		}
	end

	if kind == "NumberSequence" then
		return numberSequenceExplicit(value)
	end

	if kind == "Rect" then
		return rectExplicit(value)
	end

	if kind == "UDim" then
		return {
			UDim = {
				value.Scale,
				value.Offset,
			},
		}
	end

	if kind == "UDim2" then
		return {
			UDim2 = {
				{ value.X.Scale, value.X.Offset },
				{ value.Y.Scale, value.Y.Offset },
			},
		}
	end

	if kind == "Vector2" then
		return {
			Vector2 = {
				value.X,
				value.Y,
			},
		}
	end

	if kind == "Vector3" then
		return {
			Vector3 = {
				value.X,
				value.Y,
				value.Z,
			},
		}
	end

	return nil, ("attribute type %s is not supported by Rojo"):format(kind)
end

local function encodeAttributes(instance, warnings)
	local attributes = instance:GetAttributes()

	if next(attributes) == nil then
		return nil
	end

	local encodedAttributes = {}
	local names = {}

	for name in pairs(attributes) do
		table.insert(names, name)
	end

	table.sort(names)

	for _, name in ipairs(names) do
		local encodedValue, encodeError = encodeAttributeValue(attributes[name])

		if encodedValue ~= nil then
			encodedAttributes[name] = encodedValue
		else
			table.insert(warnings, makeWarning(instance:GetFullName(), ("Attributes[%s]"):format(name), encodeError))
		end
	end

	if next(encodedAttributes) == nil then
		return nil
	end

	return encodedAttributes
end

local function augmentSpecialCaseProperties(instance, properties, warnings)
	if not instance:IsA("MeshPart") then
		return properties
	end

	local result = properties or {}
	local encodedAttributes = result.Attributes

	if type(encodedAttributes) ~= "table" then
		encodedAttributes = {}
	end

	local meshId = instance:GetAttribute(MESH_PART_ATTRIBUTE)
	if type(meshId) ~= "string" or meshId == "" then
		meshId = instance.MeshId
	end

	if type(meshId) == "string" and meshId ~= "" then
		encodedAttributes[MESH_PART_ATTRIBUTE] = {
			String = meshId,
		}
	end

	encodedAttributes[MESH_PART_COLLISION_ATTRIBUTE] = {
		String = instance.CollisionFidelity.Name,
	}
	encodedAttributes[MESH_PART_RENDER_ATTRIBUTE] = {
		String = instance.RenderFidelity.Name,
	}

	local encodedSize, sizeError = encodeAttributeValue(instance.Size)
	if encodedSize ~= nil then
		encodedAttributes[MESH_PART_SIZE_ATTRIBUTE] = encodedSize
	elseif sizeError ~= nil then
		table.insert(warnings, makeWarning(instance:GetFullName(), MESH_PART_SIZE_ATTRIBUTE, sizeError))
	end

	if next(encodedAttributes) ~= nil then
		result.Attributes = encodedAttributes
	end

	local tags = {}
	if type(result.Tags) == "table" then
		for _, tag in ipairs(result.Tags) do
			table.insert(tags, tag)
		end
	end

	if not table.find(tags, MESH_PART_TAG) then
		table.insert(tags, MESH_PART_TAG)
	end

	table.sort(tags)
	result.Tags = tags

	return result
end

local function collectProperties(instance, warnings)
	local properties = {}
	local seen = {}
	local forceExportProperties = ALWAYS_INCLUDE_PROPERTIES[instance.ClassName]

	for _, descriptor in ipairs(getPropertyDescriptors(instance.ClassName)) do
		local propertyName = descriptor.name

		if propertyName ~= nil and not seen[propertyName] then
			seen[propertyName] = true

			local shouldExport = forceExportProperties ~= nil and forceExportProperties[propertyName] == true

			if not shouldExport then
				local modifiedOk, isModified = pcall(function()
					return instance:IsPropertyModified(propertyName)
				end)

				shouldExport = modifiedOk and isModified
			end

			if shouldExport then
				local valueOk, propertyValue = pcall(function()
					return instance[propertyName]
				end)

				if valueOk and propertyValue ~= nil then
					local encodedValue, encodeError = encodePropertyValue(propertyValue, descriptor.valueType)

					if encodedValue ~= nil then
						properties[propertyName] = encodedValue
					else
						table.insert(warnings, makeWarning(instance:GetFullName(), propertyName, encodeError))
					end
				end
			end
		end
	end

	local encodedAttributes = encodeAttributes(instance, warnings)

	if encodedAttributes ~= nil then
		properties.Attributes = encodedAttributes
	end

	local tags = instance:GetTags()
	if #tags > 0 then
		table.sort(tags)
		properties.Tags = tags
	end

	properties = augmentSpecialCaseProperties(instance, properties, warnings)

	if next(properties) == nil then
		return nil
	end

	return properties
end

local function childSort(left, right)
	if left.Name == right.Name then
		return left.ClassName < right.ClassName
	end

	return string.lower(left.Name) < string.lower(right.Name)
end

local function serializeInstance(instance, warnings)
	local node = {
		name = instance.Name,
		className = instance.ClassName,
		children = {},
	}

	local properties = collectProperties(instance, warnings)
	if properties ~= nil then
		node.properties = properties
	end

	if SCRIPT_FILE_CLASSES[instance.ClassName] then
		local sourceOk, sourceOrError = pcall(function()
			return instance.Source
		end)

		if sourceOk then
			node.source = sourceOrError
		else
			node.source = ""
			table.insert(warnings, makeWarning(instance:GetFullName(), "Source", tostring(sourceOrError)))
		end
	end

	local children = instance:GetChildren()
	table.sort(children, childSort)

	for _, child in ipairs(children) do
		table.insert(node.children, serializeInstance(child, warnings))
	end

	return node
end

local function buildMountPath(instance)
	local mountPath = {}
	local current = instance.Parent

	while current ~= nil and current ~= game do
		table.insert(mountPath, 1, {
			name = current.Name,
			className = current.ClassName,
			isService = current.Parent == game,
		})
		current = current.Parent
	end

	return mountPath
end

local function normalizeSelection(selection, warnings)
	local candidates = table.clone(selection)
	table.sort(candidates, function(left, right)
		return left:GetFullName() < right:GetFullName()
	end)

	local normalized = {}

	for _, instance in ipairs(candidates) do
		if instance == game then
			table.insert(warnings, "Skipping DataModel root. Select a service or a descendant instead.")
		else
			local covered = false

			for _, root in ipairs(normalized) do
				if instance:IsDescendantOf(root) then
					covered = true
					table.insert(warnings, ("%s is already covered by %s."):format(instance:GetFullName(), root:GetFullName()))
					break
				end
			end

			if not covered then
				table.insert(normalized, instance)
			end
		end
	end

	return normalized
end

function ExportSerializer.serializeSelection(selection)
	if #selection == 0 then
		return nil, "Select at least one instance before clicking Rojo-convert."
	end

	local warnings = {}
	local normalizedSelection = normalizeSelection(selection, warnings)

	if #normalizedSelection == 0 then
		return nil, "Selection did not contain any exportable instances."
	end

	local payload = {
		selection = {},
	}

	for _, root in ipairs(normalizedSelection) do
		local serializedRoot = serializeInstance(root, warnings)
		serializedRoot.mountPath = buildMountPath(root)
		table.insert(payload.selection, serializedRoot)
	end

	return payload, warnings
end

return ExportSerializer
