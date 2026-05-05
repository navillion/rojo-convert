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
local STYLE_RULE_PROPERTIES_ATTRIBUTE = "RojoStyleProperties"
local STYLE_RULE_TRANSITIONS_ATTRIBUTE = "RojoStyleTransitions"
local STYLE_RULE_ORDER_ATTRIBUTE = "RojoStyleRuleOrder"
local STYLE_SHEET_DERIVES_ATTRIBUTE = "RojoStyleDerives"
local STYLE_LINK_ATTRIBUTE = "RojoStyleSheetRef"
local STYLE_RULE_TAG = "RojoStyleRule"
local STYLE_SHEET_TAG = "RojoStyleSheet"
local STYLE_LINK_TAG = "RojoStyleLink"

local ALWAYS_INCLUDE_PROPERTIES = {
	MeshPart = {
		CollisionFidelity = true,
		MeshId = true,
		RenderFidelity = true,
		Size = true,
		TextureID = true,
	},
	TextLabel = {
		Font = true,
		FontFace = true,
		Text = true,
		TextColor3 = true,
		TextStrokeColor3 = true,
		TextStrokeTransparency = true,
		TextTransparency = true,
	},
	TextButton = {
		Font = true,
		FontFace = true,
		Text = true,
		TextColor3 = true,
		TextStrokeColor3 = true,
		TextStrokeTransparency = true,
		TextTransparency = true,
	},
	TextBox = {
		Font = true,
		FontFace = true,
		PlaceholderColor3 = true,
		PlaceholderText = true,
		Text = true,
		TextColor3 = true,
		TextStrokeColor3 = true,
		TextStrokeTransparency = true,
		TextTransparency = true,
	},
	StyleRule = {
		Priority = true,
		Selector = true,
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

local TEXT_PROPERTIES = {
	"Font",
	"FontFace",
	"LineHeight",
	"MaxVisibleGraphemes",
	"OpenTypeFeatures",
	"RichText",
	"Text",
	"TextColor3",
	"TextDirection",
	"TextScaled",
	"TextSize",
	"TextStrokeColor3",
	"TextStrokeTransparency",
	"TextTransparency",
	"TextTruncate",
	"TextWrapped",
	"TextXAlignment",
	"TextYAlignment",
}

local FALLBACK_PROPERTY_GROUPS = {
	{ className = "Script", properties = { "Disabled", "RunContext" } },
	{ className = "LocalScript", properties = { "Disabled" } },
	{ className = "ModuleScript", properties = {} },
	{ className = "Folder", properties = {} },
	{ className = "Model", properties = { "LevelOfDetail", "ModelStreamingMode", "PrimaryPart", "WorldPivot" } },
	{
		className = "Tool",
		properties = {
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
	},
	{ className = "Configuration", properties = {} },
	{ className = "RemoteEvent", properties = {} },
	{ className = "RemoteFunction", properties = {} },
	{ className = "BindableEvent", properties = {} },
	{ className = "BindableFunction", properties = {} },
	{ className = "StyleSheet", properties = {} },
	{ className = "StyleRule", properties = { "Priority", "Selector" } },
	{ className = "StyleLink", properties = { "Enabled" } },
	{ className = "BoolValue", properties = { "Value" } },
	{ className = "IntValue", properties = { "Value" } },
	{ className = "NumberValue", properties = { "Value" } },
	{ className = "StringValue", properties = { "Value" } },
	{ className = "ObjectValue", properties = { "Value" } },
	{ className = "Vector3Value", properties = { "Value" } },
	{ className = "CFrameValue", properties = { "Value" } },
	{ className = "Color3Value", properties = { "Value" } },
	{ className = "BrickColorValue", properties = { "Value" } },
	{ className = "RayValue", properties = { "Value" } },
	{
		className = "Part",
		properties = {
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
	},
	{
		className = "MeshPart",
		properties = {
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
	},
	{
		className = "GuiObject",
		properties = {
			"Active",
			"AnchorPoint",
			"AutomaticSize",
			"BackgroundColor3",
			"BackgroundTransparency",
			"BorderColor3",
			"BorderMode",
			"BorderSizePixel",
			"ClipsDescendants",
			"LayoutOrder",
			"Position",
			"Rotation",
			"Selectable",
			"SelectionOrder",
			"Size",
			"SizeConstraint",
			"Visible",
			"ZIndex",
		},
	},
	{
		className = "GuiButton",
		properties = {
			"AutoButtonColor",
			"Modal",
			"Selected",
			"Style",
		},
	},
	{
		className = "TextLabel",
		properties = TEXT_PROPERTIES,
	},
	{
		className = "TextButton",
		properties = TEXT_PROPERTIES,
	},
	{
		className = "TextBox",
		properties = {
			"Font",
			"FontFace",
			"ClearTextOnFocus",
			"LineHeight",
			"MaxVisibleGraphemes",
			"MultiLine",
			"OpenTypeFeatures",
			"PlaceholderColor3",
			"PlaceholderText",
			"RichText",
			"ShowNativeInput",
			"Text",
			"TextColor3",
			"TextDirection",
			"TextEditable",
			"TextScaled",
			"TextSize",
			"TextStrokeColor3",
			"TextStrokeTransparency",
			"TextTransparency",
			"TextTruncate",
			"TextWrapped",
			"TextXAlignment",
			"TextYAlignment",
		},
	},
	{
		className = "ImageLabel",
		properties = {
			"Image",
			"ImageColor3",
			"ImageRectOffset",
			"ImageRectSize",
			"ImageTransparency",
			"ResampleMode",
			"ScaleType",
			"SliceCenter",
			"SliceScale",
			"TileSize",
		},
	},
	{
		className = "ImageButton",
		properties = {
			"HoverImage",
			"PressedImage",
		},
	},
	{
		className = "LayerCollector",
		properties = {
			"Enabled",
			"ResetOnSpawn",
			"ZIndexBehavior",
		},
	},
	{
		className = "ScreenGui",
		properties = {
			"ClipToDeviceSafeArea",
			"DisplayOrder",
			"IgnoreGuiInset",
			"SafeAreaCompatibility",
			"ScreenInsets",
		},
	},
	{
		className = "ScrollingFrame",
		properties = {
			"AutomaticCanvasSize",
			"BottomImage",
			"CanvasPosition",
			"CanvasSize",
			"ElasticBehavior",
			"HorizontalScrollBarInset",
			"MidImage",
			"ScrollBarImageColor3",
			"ScrollBarImageTransparency",
			"ScrollBarThickness",
			"ScrollingDirection",
			"ScrollingEnabled",
			"TopImage",
			"VerticalScrollBarInset",
			"VerticalScrollBarPosition",
		},
	},
	{
		className = "UIAspectRatioConstraint",
		properties = {
			"AspectRatio",
			"AspectType",
			"DominantAxis",
		},
	},
	{
		className = "UICorner",
		properties = {
			"CornerRadius",
		},
	},
	{
		className = "UIGradient",
		properties = {
			"Color",
			"Enabled",
			"Offset",
			"Rotation",
			"Transparency",
		},
	},
	{
		className = "UIGridLayout",
		properties = {
			"CellPadding",
			"CellSize",
			"FillDirection",
			"FillDirectionMaxCells",
			"HorizontalAlignment",
			"SortOrder",
			"StartCorner",
			"VerticalAlignment",
		},
	},
	{
		className = "UIListLayout",
		properties = {
			"FillDirection",
			"HorizontalAlignment",
			"Padding",
			"SortOrder",
			"VerticalAlignment",
			"Wraps",
		},
	},
	{
		className = "UIPadding",
		properties = {
			"PaddingBottom",
			"PaddingLeft",
			"PaddingRight",
			"PaddingTop",
		},
	},
	{
		className = "UIPageLayout",
		properties = {
			"Animated",
			"EasingDirection",
			"EasingStyle",
			"FillDirection",
			"GamepadInputEnabled",
			"Padding",
			"ScrollWheelInputEnabled",
			"TouchInputEnabled",
			"TweenTime",
		},
	},
	{
		className = "UIScale",
		properties = {
			"Scale",
		},
	},
	{
		className = "UISizeConstraint",
		properties = {
			"MaxSize",
			"MinSize",
		},
	},
	{
		className = "UIStroke",
		properties = {
			"ApplyStrokeMode",
			"Color",
			"Enabled",
			"LineJoinMode",
			"Thickness",
			"Transparency",
		},
	},
	{
		className = "UITextSizeConstraint",
		properties = {
			"MaxTextSize",
			"MinTextSize",
		},
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

local function hasOnlyFiniteNumbers(value)
	local kind = typeof(value)

	if kind == "number" then
		return isFiniteNumber(value)
	end

	if kind ~= "table" then
		return true
	end

	for _, nestedValue in pairs(value) do
		if not hasOnlyFiniteNumbers(nestedValue) then
			return false
		end
	end

	return true
end

local function validateEncodedValue(encodedValue)
	if encodedValue == nil then
		return nil, "value was nil"
	end

	if not hasOnlyFiniteNumbers(encodedValue) then
		return nil, "contains a non-finite number"
	end

	return encodedValue
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

local function instanceIsA(instance, className)
	local ok, result = pcall(function()
		return instance:IsA(className)
	end)

	return ok and result
end

local function getPropertyDescriptors(instance)
	local className = instance.ClassName

	if PROPERTY_CACHE[className] ~= nil then
		return PROPERTY_CACHE[className]
	end

	local descriptors = {}
	local seenNames = {}

	local function addDescriptor(name, valueType)
		if name == nil or OMITTED_PROPERTIES[name] or seenNames[name] then
			return
		end

		seenNames[name] = true
		table.insert(descriptors, {
			name = name,
			valueType = valueType,
		})
	end

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
				addDescriptor(name, extractValueType(descriptor))
			end
		end
	end

	for _, group in ipairs(FALLBACK_PROPERTY_GROUPS) do
		if instanceIsA(instance, group.className) then
			for _, name in ipairs(group.properties) do
				addDescriptor(name, nil)
			end
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
			local validatedValue, validateError = validateEncodedValue(encodedValue)

			if validatedValue ~= nil then
				encodedAttributes[name] = validatedValue
			else
				table.insert(warnings, makeWarning(instance:GetFullName(), ("Attributes[%s]"):format(name), validateError))
			end
		else
			table.insert(warnings, makeWarning(instance:GetFullName(), ("Attributes[%s]"):format(name), encodeError))
		end
	end

	if next(encodedAttributes) == nil then
		return nil
	end

	return encodedAttributes
end

local function isArrayTable(value)
	if type(value) ~= "table" then
		return false
	end

	local count = 0
	for key in pairs(value) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return false
		end

		count += 1
	end

	for index = 1, count do
		if value[index] == nil then
			return false
		end
	end

	return true
end

local function getEnumTypeName(enumItem)
	local enumType = enumItem.EnumType

	if type(enumType) == "table" and type(enumType.Name) == "string" then
		return enumType.Name
	end

	local enumTypeString = tostring(enumType)
	local parsedName = string.match(enumTypeString, "^Enum%.(.+)$")

	if type(parsedName) == "string" and parsedName ~= "" then
		return parsedName
	end

	return enumTypeString
end

local function encodeStyleValue(value)
	local kind = typeof(value)

	if kind == "boolean" or kind == "string" then
		return value
	end

	if kind == "number" then
		if not isFiniteNumber(value) then
			return nil, "contains a non-finite number"
		end

		return value
	end

	if kind == "EnumItem" then
		return {
			["$type"] = "EnumItem",
			enumType = getEnumTypeName(value),
			name = value.Name,
		}
	end

	if kind == "Vector2" then
		return {
			["$type"] = "Vector2",
			x = value.X,
			y = value.Y,
		}
	end

	if kind == "Vector3" then
		return {
			["$type"] = "Vector3",
			x = value.X,
			y = value.Y,
			z = value.Z,
		}
	end

	if kind == "Color3" then
		return {
			["$type"] = "Color3",
			r = value.R,
			g = value.G,
			b = value.B,
		}
	end

	if kind == "BrickColor" then
		return {
			["$type"] = "BrickColor",
			number = value.Number,
		}
	end

	if kind == "UDim" then
		return {
			["$type"] = "UDim",
			scale = value.Scale,
			offset = value.Offset,
		}
	end

	if kind == "UDim2" then
		return {
			["$type"] = "UDim2",
			xScale = value.X.Scale,
			xOffset = value.X.Offset,
			yScale = value.Y.Scale,
			yOffset = value.Y.Offset,
		}
	end

	if kind == "CFrame" then
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = value:GetComponents()

		return {
			["$type"] = "CFrame",
			x = x,
			y = y,
			z = z,
			orientation = {
				{ r00, r01, r02 },
				{ r10, r11, r12 },
				{ r20, r21, r22 },
			},
		}
	end

	if kind == "Font" then
		return {
			["$type"] = "Font",
			family = value.Family,
			weight = value.Weight.Name,
			style = value.Style.Name,
		}
	end

	if kind == "NumberRange" then
		return {
			["$type"] = "NumberRange",
			min = value.Min,
			max = value.Max,
		}
	end

	if kind == "ColorSequence" then
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
			["$type"] = "ColorSequence",
			keypoints = keypoints,
		}
	end

	if kind == "NumberSequence" then
		local keypoints = {}
		for _, keypoint in ipairs(value.Keypoints) do
			table.insert(keypoints, {
				time = keypoint.Time,
				value = keypoint.Value,
				envelope = keypoint.Envelope,
			})
		end

		return {
			["$type"] = "NumberSequence",
			keypoints = keypoints,
		}
	end

	if kind == "Rect" then
		return {
			["$type"] = "Rect",
			minX = value.Min.X,
			minY = value.Min.Y,
			maxX = value.Max.X,
			maxY = value.Max.Y,
		}
	end

	if kind == "Ray" then
		return {
			["$type"] = "Ray",
			origin = {
				x = value.Origin.X,
				y = value.Origin.Y,
				z = value.Origin.Z,
			},
			direction = {
				x = value.Direction.X,
				y = value.Direction.Y,
				z = value.Direction.Z,
			},
		}
	end

	if kind == "PhysicalProperties" then
		return {
			["$type"] = "PhysicalProperties",
			density = value.Density,
			friction = value.Friction,
			elasticity = value.Elasticity,
			frictionWeight = value.FrictionWeight,
			elasticityWeight = value.ElasticityWeight,
		}
	end

	if kind == "Faces" then
		return {
			["$type"] = "Faces",
			right = value.Right,
			top = value.Top,
			back = value.Back,
			left = value.Left,
			bottom = value.Bottom,
			front = value.Front,
		}
	end

	if kind == "Axes" then
		return {
			["$type"] = "Axes",
			x = value.X,
			y = value.Y,
			z = value.Z,
		}
	end

	if kind == "table" then
		if isArrayTable(value) then
			local items = {}
			for index, item in ipairs(value) do
				local encodedItem, encodeError = encodeStyleValue(item)
				if encodedItem == nil then
					return nil, ("array item %d %s"):format(index, encodeError)
				end

				items[index] = encodedItem
			end

			return {
				["$type"] = "Array",
				items = items,
			}
		end

		local entries = {}
		for key, item in pairs(value) do
			if type(key) ~= "string" then
				return nil, "contains a non-string map key"
			end

			local encodedItem, encodeError = encodeStyleValue(item)
			if encodedItem == nil then
				return nil, ("map entry %s %s"):format(key, encodeError)
			end

			entries[key] = encodedItem
		end

		return {
			["$type"] = "Map",
			entries = entries,
		}
	end

	return nil, ("unsupported style value type %s"):format(kind)
end

local function encodeStyleJson(value)
	local encodedValue, encodeError = encodeStyleValue(value)
	if encodedValue == nil then
		return nil, encodeError
	end

	local ok, encodedJson = pcall(function()
		return HttpService:JSONEncode(encodedValue)
	end)

	if not ok then
		return nil, tostring(encodedJson)
	end

	return encodedJson
end

local function appendTag(tags, tagName)
	if not table.find(tags, tagName) then
		table.insert(tags, tagName)
	end
end

local function getOrCreateEncodedAttributes(properties)
	local encodedAttributes = properties.Attributes

	if type(encodedAttributes) ~= "table" then
		encodedAttributes = {}
	end

	return encodedAttributes
end

local function getOrCreateTags(properties)
	local tags = {}
	if type(properties.Tags) == "table" then
		for _, tag in ipairs(properties.Tags) do
			table.insert(tags, tag)
		end
	end

	properties.Tags = tags
	return tags
end

local function encodeInstancePath(instance)
	if typeof(instance) ~= "Instance" then
		return nil
	end

	local path = {}
	local current = instance

	while current ~= nil and current ~= game do
		table.insert(path, 1, current.Name)
		current = current.Parent
	end

	return path
end

local function collectStyleRuleOrder(instance, warnings)
	local seenNames = {}
	local orderedNames = {}

	for _, child in ipairs(instance:GetChildren()) do
		if child:IsA("StyleRule") then
			if seenNames[child.Name] then
				table.insert(warnings, makeWarning(instance:GetFullName(), STYLE_RULE_ORDER_ATTRIBUTE, "contains duplicate StyleRule names and was not exported"))
				return nil
			end

			seenNames[child.Name] = true
			table.insert(orderedNames, child.Name)
		end
	end

	if #orderedNames == 0 then
		return nil
	end

	return orderedNames
end

local function augmentStyleRuleProperties(instance, properties, warnings)
	local result = properties or {}
	local encodedAttributes = getOrCreateEncodedAttributes(result)

	local propertiesOk, stylePropertiesOrError = pcall(function()
		return instance:GetProperties()
	end)

	if propertiesOk and type(stylePropertiesOrError) == "table" and next(stylePropertiesOrError) ~= nil then
		local encodedJson, encodeError = encodeStyleJson(stylePropertiesOrError)
		if encodedJson ~= nil then
			encodedAttributes[STYLE_RULE_PROPERTIES_ATTRIBUTE] = {
				String = encodedJson,
			}
		else
			table.insert(warnings, makeWarning(instance:GetFullName(), STYLE_RULE_PROPERTIES_ATTRIBUTE, encodeError))
		end
	elseif not propertiesOk then
		table.insert(warnings, makeWarning(instance:GetFullName(), STYLE_RULE_PROPERTIES_ATTRIBUTE, tostring(stylePropertiesOrError)))
	end

	local transitionsOk, transitionsOrError = pcall(function()
		return instance:GetPropertyTransitions()
	end)

	if transitionsOk and type(transitionsOrError) == "table" and next(transitionsOrError) ~= nil then
		local encodedJson, encodeError = encodeStyleJson(transitionsOrError)
		if encodedJson ~= nil then
			encodedAttributes[STYLE_RULE_TRANSITIONS_ATTRIBUTE] = {
				String = encodedJson,
			}
		else
			table.insert(warnings, makeWarning(instance:GetFullName(), STYLE_RULE_TRANSITIONS_ATTRIBUTE, encodeError))
		end
	elseif not transitionsOk then
		table.insert(warnings, makeWarning(instance:GetFullName(), STYLE_RULE_TRANSITIONS_ATTRIBUTE, tostring(transitionsOrError)))
	end

	local orderedNames = collectStyleRuleOrder(instance, warnings)
	if orderedNames ~= nil then
		local encodedJson, encodeError = encodeStyleJson(orderedNames)
		if encodedJson ~= nil then
			encodedAttributes[STYLE_RULE_ORDER_ATTRIBUTE] = {
				String = encodedJson,
			}
		else
			table.insert(warnings, makeWarning(instance:GetFullName(), STYLE_RULE_ORDER_ATTRIBUTE, encodeError))
		end
	end

	if next(encodedAttributes) ~= nil then
		result.Attributes = encodedAttributes
	else
		result.Attributes = nil
	end

	local tags = getOrCreateTags(result)
	appendTag(tags, STYLE_RULE_TAG)
	table.sort(tags)

	return result
end

local function augmentStyleSheetProperties(instance, properties, warnings)
	local result = properties or {}
	local encodedAttributes = getOrCreateEncodedAttributes(result)

	local derivesOk, derivesOrError = pcall(function()
		return instance:GetDerives()
	end)

	if derivesOk and type(derivesOrError) == "table" and #derivesOrError > 0 then
		local derives = {}
		for _, derive in ipairs(derivesOrError) do
			local instancePath = encodeInstancePath(derive)
			if instancePath ~= nil then
				table.insert(derives, instancePath)
			end
		end

		if #derives > 0 then
			local encodedJson, encodeError = encodeStyleJson(derives)
			if encodedJson ~= nil then
				encodedAttributes[STYLE_SHEET_DERIVES_ATTRIBUTE] = {
					String = encodedJson,
				}
			else
				table.insert(warnings, makeWarning(instance:GetFullName(), STYLE_SHEET_DERIVES_ATTRIBUTE, encodeError))
			end
		end
	elseif not derivesOk then
		table.insert(warnings, makeWarning(instance:GetFullName(), STYLE_SHEET_DERIVES_ATTRIBUTE, tostring(derivesOrError)))
	end

	local orderedNames = collectStyleRuleOrder(instance, warnings)
	if orderedNames ~= nil then
		local encodedJson, encodeError = encodeStyleJson(orderedNames)
		if encodedJson ~= nil then
			encodedAttributes[STYLE_RULE_ORDER_ATTRIBUTE] = {
				String = encodedJson,
			}
		else
			table.insert(warnings, makeWarning(instance:GetFullName(), STYLE_RULE_ORDER_ATTRIBUTE, encodeError))
		end
	end

	if next(encodedAttributes) ~= nil then
		result.Attributes = encodedAttributes
	else
		result.Attributes = nil
	end

	local tags = getOrCreateTags(result)
	appendTag(tags, STYLE_SHEET_TAG)
	table.sort(tags)

	return result
end

local function augmentStyleLinkProperties(instance, properties, warnings)
	local result = properties or {}
	local encodedAttributes = getOrCreateEncodedAttributes(result)

	local styleSheetOk, styleSheetOrError = pcall(function()
		return instance.StyleSheet
	end)

	if styleSheetOk and typeof(styleSheetOrError) == "Instance" then
		local instancePath = encodeInstancePath(styleSheetOrError)
		if instancePath ~= nil then
			local encodedJson, encodeError = encodeStyleJson(instancePath)
			if encodedJson ~= nil then
				encodedAttributes[STYLE_LINK_ATTRIBUTE] = {
					String = encodedJson,
				}
			else
				table.insert(warnings, makeWarning(instance:GetFullName(), STYLE_LINK_ATTRIBUTE, encodeError))
			end
		end
	elseif not styleSheetOk then
		table.insert(warnings, makeWarning(instance:GetFullName(), STYLE_LINK_ATTRIBUTE, tostring(styleSheetOrError)))
	end

	if next(encodedAttributes) ~= nil then
		result.Attributes = encodedAttributes
	else
		result.Attributes = nil
	end

	local tags = getOrCreateTags(result)
	appendTag(tags, STYLE_LINK_TAG)
	table.sort(tags)

	return result
end

local function augmentSpecialCaseProperties(instance, properties, warnings)
	if instance:IsA("MeshPart") then
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

	if instance:IsA("StyleRule") then
		return augmentStyleRuleProperties(instance, properties, warnings)
	end

	if instance:IsA("StyleSheet") then
		return augmentStyleSheetProperties(instance, properties, warnings)
	end

	if instance:IsA("StyleLink") then
		return augmentStyleLinkProperties(instance, properties, warnings)
	end

	return properties
end

local function normalizeLegacyProperties(properties)
	if properties == nil then
		return nil
	end

	local modernAliases = {
		BackgroundColor = "BackgroundColor3",
		BorderColor = "BorderColor3",
		Font = "FontFace",
		FontSize = "TextSize",
		TextColor = "TextColor3",
		TextWrap = "TextWrapped",
	}

	for legacyName, modernName in pairs(modernAliases) do
		if properties[legacyName] ~= nil and properties[modernName] ~= nil then
			properties[legacyName] = nil
		end
	end

	if properties.Transparency ~= nil then
		if properties.BackgroundTransparency ~= nil or properties.ImageTransparency ~= nil or properties.TextTransparency ~= nil then
			properties.Transparency = nil
		end
	end

	return properties
end

local function collectProperties(instance, warnings)
	local properties = {}
	local seen = {}
	local forceExportProperties = ALWAYS_INCLUDE_PROPERTIES[instance.ClassName]

	for _, descriptor in ipairs(getPropertyDescriptors(instance)) do
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
						local validatedValue, validateError = validateEncodedValue(encodedValue)

						if validatedValue ~= nil then
							properties[propertyName] = validatedValue
						else
							table.insert(warnings, makeWarning(instance:GetFullName(), propertyName, validateError))
						end
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
	properties = normalizeLegacyProperties(properties)

	if next(properties) == nil then
		return nil
	end

	return properties
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
