--!strict

local Types = require(script.Parent.Types)

type Writer = Types.Writer
type Reader = Types.Reader
type Schema = Types.Schema
type SchemaContext = Types.SchemaContext
type StructField = Types.StructField

local Schemas = {}

const MAX_NESTING_DEPTH = 16

local function assertDepth(context: SchemaContext)
	assert(context.Depth < MAX_NESTING_DEPTH, `Maximum schema nesting depth of {MAX_NESTING_DEPTH} exceeded`) -- Unlikely at 16 but why not
end

local function childContext(context: SchemaContext): SchemaContext
	assertDepth(context)

	return {
		Depth = context.Depth + 1,
	}
end

local function assertInteger(value: any, minimum: number, maximum: number, typeName: string): number
	assert(
		type(value) == "number",
		`Expected {typeName}, got {typeof(value)}`
	)

	assert(
		value % 1 == 0,
		`Expected {typeName} to be an integer`
	)

	assert(
		value >= minimum and value <= maximum,
		`{typeName} must be between {minimum} and {maximum}`
	)

	return value
end

local function assertFiniteNumber(value: any, typeName: string): number
	assert(
		type(value) == "number",
		`Expected {typeName}, got {typeof(value)}`
	)

	assert(
		value == value
			and value ~= math.huge
			and value ~= -math.huge,
		`{typeName} must be finite`
	)

	return value
end

-- Support for all types of data
-- Searching up the value range for every one took some time 😂
-- Again, assumes UTF8 encoding

Schemas.UInt8 = {
	Name = "UInt8",

	Write = function(
		writer: Writer,
		value: any,
		_context: SchemaContext
	)
		writer:WriteUInt8(
			assertInteger(value, 0, 255, "UInt8")
		)
	end,

	Read = function(
		reader: Reader,
		_context: SchemaContext
	): number
		return reader:ReadUInt8()
	end,
} :: Schema

Schemas.UInt16 = {
	Name = "UInt16",

	Write = function(
		writer: Writer,
		value: any,
		_context: SchemaContext
	)
		writer:WriteUInt16(
			assertInteger(value, 0, 65535, "UInt16")
		)
	end,

	Read = function(
		reader: Reader,
		_context: SchemaContext
	): number
		return reader:ReadUInt16()
	end,
} :: Schema

Schemas.UInt32 = {
	Name = "UInt32",

	Write = function(
		writer: Writer,
		value: any,
		_context: SchemaContext
	)
		writer:WriteUInt32(
			assertInteger(
				value,
				0,
				4294967295,
				"UInt32"
			)
		)
	end,

	Read = function(
		reader: Reader,
		_context: SchemaContext
	): number
		return reader:ReadUInt32()
	end,
} :: Schema

Schemas.Int8 = {
	Name = "Int8",

	Write = function(
		writer: Writer,
		value: any,
		_context: SchemaContext
	)
		writer:WriteInt8(
			assertInteger(value, -128, 127, "Int8")
		)
	end,

	Read = function(
		reader: Reader,
		_context: SchemaContext
	): number
		return reader:ReadInt8()
	end,
} :: Schema

Schemas.Int16 = {
	Name = "Int16",

	Write = function(
		writer: Writer,
		value: any,
		_context: SchemaContext
	)
		writer:WriteInt16(
			assertInteger(
				value,
				-32768,
				32767,
				"Int16"
			)
		)
	end,

	Read = function(
		reader: Reader,
		_context: SchemaContext
	): number
		return reader:ReadInt16()
	end,
} :: Schema

Schemas.Int32 = {
	Name = "Int32",

	Write = function(
		writer: Writer,
		value: any,
		_context: SchemaContext
	)
		writer:WriteInt32(
			assertInteger(
				value,
				-2147483648,
				2147483647,
				"Int32"
			)
		)
	end,

	Read = function(
		reader: Reader,
		_context: SchemaContext
	): number
		return reader:ReadInt32()
	end,
} :: Schema

Schemas.Float32 = {
	Name = "Float32",

	Write = function(
		writer: Writer,
		value: any,
		_context: SchemaContext
	)
		writer:WriteFloat32(
			assertFiniteNumber(value, "Float32")
		)
	end,

	Read = function(
		reader: Reader,
		_context: SchemaContext
	): number
		return reader:ReadFloat32()
	end,
} :: Schema

Schemas.Float64 = {
	Name = "Float64",

	Write = function(
		writer: Writer,
		value: any,
		_context: SchemaContext
	)
		writer:WriteFloat64(
			assertFiniteNumber(value, "Float64")
		)
	end,

	Read = function(
		reader: Reader,
		_context: SchemaContext
	): number
		return reader:ReadFloat64()
	end,
} :: Schema

Schemas.Boolean = {
	Name = "Boolean",

	Write = function(
		writer: Writer,
		value: any,
		_context: SchemaContext
	)
		assert(
			type(value) == "boolean",
			`Expected Boolean, got {typeof(value)}`
		)

		writer:WriteUInt8(if value then 1 else 0)
	end,

	Read = function(
		reader: Reader,
		_context: SchemaContext
	): boolean
		local value = reader:ReadUInt8()

		assert(
			value == 0 or value == 1,
			`Invalid Boolean value: {value}`
		)

		return value == 1
	end,
} :: Schema

Schemas.Vector2 = {
	Name = "Vector2",

	Write = function(
		writer: Writer,
		value: any,
		_context: SchemaContext
	)
		assert(
			typeof(value) == "Vector2",
			`Expected Vector2, got {typeof(value)}`
		)

		writer:WriteFloat32(value.X)
		writer:WriteFloat32(value.Y)
	end,

	Read = function(
		reader: Reader,
		_context: SchemaContext
	): Vector2
		return Vector2.new(
			reader:ReadFloat32(),
			reader:ReadFloat32()
		)
	end,
} :: Schema

Schemas.Vector3 = {
	Name = "Vector3",

	Write = function(
		writer: Writer,
		value: any,
		_context: SchemaContext
	)
		assert(
			typeof(value) == "Vector3",
			`Expected Vector3, got {typeof(value)}`
		)

		writer:WriteFloat32(value.X)
		writer:WriteFloat32(value.Y)
		writer:WriteFloat32(value.Z)
	end,

	Read = function(
		reader: Reader,
		_context: SchemaContext
	): Vector3
		return Vector3.new(
			reader:ReadFloat32(),
			reader:ReadFloat32(),
			reader:ReadFloat32()
		)
	end,
} :: Schema

Schemas.Color3 = {
	Name = "Color3",

	Write = function(
		writer: Writer,
		value: any,
		_context: SchemaContext
	)
		assert(
			typeof(value) == "Color3",
			`Expected Color3, got {typeof(value)}`
		)

		writer:WriteUInt8(math.round(value.R * 255))
		writer:WriteUInt8(math.round(value.G * 255))
		writer:WriteUInt8(math.round(value.B * 255))
	end,

	Read = function(
		reader: Reader,
		_context: SchemaContext
	): Color3
		return Color3.fromRGB(
			reader:ReadUInt8(),
			reader:ReadUInt8(),
			reader:ReadUInt8()
		)
	end,
} :: Schema

function Schemas.String8(maxLength: number?): Schema
	local limit = maxLength or 255

	assert(
		limit >= 0
			and limit <= 255
			and limit % 1 == 0,
		"String8 limit must be an integer from 0 to 255"
	)

	return {
		Name = `String8<{limit}>`,

		Write = function(
			writer: Writer,
			value: any,
			_context: SchemaContext
		)
			assert(
				type(value) == "string",
				`Expected string, got {typeof(value)}`
			)

			assert(
				#value <= limit,
				`String exceeds maximum length of {limit} bytes`
			)

			writer:WriteUInt8(#value)
			writer:WriteString(value)
		end,

		Read = function(
			reader: Reader,
			_context: SchemaContext
		): string
			local length = reader:ReadUInt8()

			assert(
				length <= limit,
				`Decoded string exceeds maximum length of {limit}`
			)

			return reader:ReadString(length)
		end,
	}
end

function Schemas.String16(maxLength: number?): Schema
	local limit = maxLength or 65535

	assert(
		limit >= 0
			and limit <= 65535
			and limit % 1 == 0,
		"String16 limit must be an integer from 0 to 65535"
	)

	return {
		Name = `String16<{limit}>`,

		Write = function(
			writer: Writer,
			value: any,
			_context: SchemaContext
		)
			assert(
				type(value) == "string",
				`Expected string, got {typeof(value)}`
			)

			assert(
				#value <= limit,
				`String exceeds maximum length of {limit} bytes`
			)

			writer:WriteUInt16(#value)
			writer:WriteString(value)
		end,

		Read = function(
			reader: Reader,
			_context: SchemaContext
		): string
			local length = reader:ReadUInt16()

			assert(
				length <= limit,
				`Decoded string exceeds maximum length of {limit}`
			)

			return reader:ReadString(length)
		end,
	}
end

function Schemas.Optional(innerSchema: Schema): Schema
	return {
		Name = `Optional<{innerSchema.Name}>`,

		Write = function(
			writer: Writer,
			value: any,
			context: SchemaContext
		)
			if value == nil then
				writer:WriteUInt8(0)
				return
			end

			writer:WriteUInt8(1)
			innerSchema.Write(writer, value, context)
		end,

		Read = function(
			reader: Reader,
			context: SchemaContext
		): any
			local exists = reader:ReadUInt8()

			assert(
				exists == 0 or exists == 1,
				`Invalid Optional flag: {exists}`
			)

			if exists == 0 then
				return nil
			end

			return innerSchema.Read(reader, context)
		end,
	}
end

function Schemas.Array(
	itemSchema: Schema,
	maxLength: number?
): Schema
	local limit = maxLength or 65535

	assert(
		limit >= 0
			and limit <= 65535
			and limit % 1 == 0,
		"Array limit must be an integer from 0 to 65535"
	)

	return {
		Name = `Array<{itemSchema.Name}>`,

		Write = function(
			writer: Writer,
			value: any,
			context: SchemaContext
		)
			assert(
				type(value) == "table",
				`Expected array, got {typeof(value)}`
			)

			assert(
				#value <= limit,
				`Array exceeds maximum length of {limit}`
			)

			local nestedContext = childContext(context)

			writer:WriteUInt16(#value)

			for index = 1, #value do
				itemSchema.Write(
					writer,
					value[index],
					nestedContext
				)
			end
		end,

		Read = function(
			reader: Reader,
			context: SchemaContext
		): { any }
			local length = reader:ReadUInt16()

			assert(
				length <= limit,
				`Decoded array exceeds maximum length of {limit}`
			)

			local nestedContext = childContext(context)
			local result = table.create(length)

			for index = 1, length do
				result[index] = itemSchema.Read(
					reader,
					nestedContext
				)
			end

			return result
		end,
	}
end

function Schemas.Struct(
	fields: { StructField }
): Schema
	assert(
		#fields <= 255,
		"Struct cannot have more than 255 fields"
	)

	local usedNames: { [string]: boolean } = {}

	for _, field in fields do
		assert(
			type(field.Name) == "string"
				and #field.Name > 0,
			"Struct fields require non-empty names"
		)

		assert(
			not usedNames[field.Name],
			`Duplicate struct field: {field.Name}`
		)

		usedNames[field.Name] = true
	end

	return {
		Name = "Struct",

		Write = function(
			writer: Writer,
			value: any,
			context: SchemaContext
		)
			assert(
				type(value) == "table",
				`Expected struct table, got {typeof(value)}`
			)

			local nestedContext = childContext(context)

			for _, field in fields do
				field.Type.Write(
					writer,
					value[field.Name],
					nestedContext
				)
			end
		end,

		Read = function(
			reader: Reader,
			context: SchemaContext
		): { [string]: any }
			local nestedContext = childContext(context)
			local result = {}

			for _, field in fields do
				result[field.Name] = field.Type.Read(
					reader,
					nestedContext
				)
			end

			return result
		end,
	}
end

function Schemas.Enum8(values: { string }): Schema
	assert(
		#values > 0 and #values <= 256,
		"Enum8 requires between 1 and 256 values"
	)

	local valueToId: { [string]: number } = {}

	for index, value in values do
		assert(
			type(value) == "string",
			"Enum8 values must be strings"
		)

		assert(
			valueToId[value] == nil,
			`Duplicate Enum8 value: {value}`
		)

		valueToId[value] = index - 1
	end

	return {
		Name = "Enum8",

		Write = function(
			writer: Writer,
			value: any,
			_context: SchemaContext
		)
			assert(
				type(value) == "string",
				`Expected enum string, got {typeof(value)}`
			)

			local id = valueToId[value]

			assert(
				id ~= nil,
				`Unknown enum value: {value}`
			)

			writer:WriteUInt8(id)
		end,

		Read = function(
			reader: Reader,
			_context: SchemaContext
		): string
			local id = reader:ReadUInt8()
			local value = values[id + 1]

			assert(
				value ~= nil,
				`Unknown Enum8 ID: {id}`
			)

			return value
		end,
	}
end

return Schemas
