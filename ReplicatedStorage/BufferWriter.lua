--!strict

local BufferWriter = {}
BufferWriter.__index = BufferWriter

export type BufferWriter = typeof(
	setmetatable(
		{} :: {
			Data: buffer,
			Position: number,
		},
		BufferWriter
	)
)

local DEFAULT_CAPACITY = 128; -- *Bytes*

function BufferWriter.new(size: number?): BufferWriter -- Creates a new BufferWriter with the specified size or the default if none is provided (that's why 'size: number?')
	local capacity = size or DEFAULT_CAPACITY

	assert(capacity >= 0, "Initial capacity cannot be negative")

	return setmetatable({
		Data = buffer.create(capacity),
		Position = 0,
	}, BufferWriter)
end

function BufferWriter:_ensureCapacity(bytes: number) -- Resizes the buffer if required by copying the bytes over to a new buffer
	local requiredCapacity = self.Position + bytes
	local currentCapacity = buffer.len(self.Data)

	if requiredCapacity <= currentCapacity then
		return
	end

	local newCapacity = math.max(
		requiredCapacity,
		math.max(currentCapacity * 2, DEFAULT_CAPACITY)
	)

	local expanded = buffer.create(newCapacity)

	if self.Position > 0 then
		buffer.copy(
			expanded,
			0,
			self.Data,
			0,
			self.Position
		)
	end

	self.Data = expanded
end

-- // Support for writing all data types

function BufferWriter:WriteUInt8(value: number)
	self:_ensureCapacity(1)

	buffer.writeu8(self.Data, self.Position, value)
	self.Position += 1
end

function BufferWriter:WriteUInt16(value: number)
	self:_ensureCapacity(2)

	buffer.writeu16(self.Data, self.Position, value)
	self.Position += 2
end

function BufferWriter:WriteUInt32(value: number)
	self:_ensureCapacity(4)

	buffer.writeu32(self.Data, self.Position, value)
	self.Position += 4
end

function BufferWriter:WriteInt8(value: number)
	self:_ensureCapacity(1)

	buffer.writei8(self.Data, self.Position, value)
	self.Position += 1
end

function BufferWriter:WriteInt16(value: number)
	self:_ensureCapacity(2)

	buffer.writei16(self.Data, self.Position, value)
	self.Position += 2
end

function BufferWriter:WriteInt32(value: number)
	self:_ensureCapacity(4)

	buffer.writei32(self.Data, self.Position, value)
	self.Position += 4
end

function BufferWriter:WriteFloat32(value: number)
	self:_ensureCapacity(4)

	buffer.writef32(self.Data, self.Position, value)
	self.Position += 4
end

function BufferWriter:WriteFloat64(value: number)
	self:_ensureCapacity(8)

	buffer.writef64(self.Data, self.Position, value)
	self.Position += 8
end

function BufferWriter:WriteString(value: string) -- I assume this is UTF8 (I am aware that if it's UTF16 and they enter emojis or other weird characters length = #value will be wrong)
	local length = #value

	self:_ensureCapacity(length)

	buffer.writestring(
		self.Data,
		self.Position,
		value
	)

	self.Position += length
end

function BufferWriter:ToBuffer(): buffer
	local result = buffer.create(self.Position)

	if self.Position > 0 then
		buffer.copy(
			result,
			0,
			self.Data,
			0,
			self.Position
		)
	end

	return result
end

return BufferWriter
