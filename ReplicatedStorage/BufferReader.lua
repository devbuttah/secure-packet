--!strict

local BufferReader = {}
BufferReader.__index = BufferReader

export type BufferReader = typeof(
	setmetatable(
		{} :: {
			Data: buffer,
			Position: number,
		},
		BufferReader
	)
)

function BufferReader.new(data: buffer): BufferReader
	assert( -- I don't think this is ever going to happen but wtv
		typeof(data) == "buffer", 
		"BufferReader requires a buffer"
	)

	return setmetatable({
		Data = data,
		Position = 0,
	}, BufferReader)
end

function BufferReader:_ensureReadable(bytes: number) -- Check not get an out of bounds exception
	if self.Position + bytes > buffer.len(self.Data) then
		error(
			`Unexpected end of buffer at byte {self.Position}`,
			3
		)
	end
end

-- Support for reading all data types

function BufferReader:ReadUInt8(): number
	self:_ensureReadable(1)

	local value = buffer.readu8(
		self.Data,
		self.Position
	)

	self.Position += 1

	return value
end

function BufferReader:ReadUInt16(): number
	self:_ensureReadable(2)

	local value = buffer.readu16(
		self.Data,
		self.Position
	)

	self.Position += 2

	return value
end

function BufferReader:ReadUInt32(): number
	self:_ensureReadable(4)

	local value = buffer.readu32(
		self.Data,
		self.Position
	)

	self.Position += 4

	return value
end

function BufferReader:ReadInt8(): number
	self:_ensureReadable(1)

	local value = buffer.readi8(
		self.Data,
		self.Position
	)

	self.Position += 1

	return value
end

function BufferReader:ReadInt16(): number
	self:_ensureReadable(2)

	local value = buffer.readi16(
		self.Data,
		self.Position
	)

	self.Position += 2

	return value
end

function BufferReader:ReadInt32(): number
	self:_ensureReadable(4)

	local value = buffer.readi32(
		self.Data,
		self.Position
	)

	self.Position += 4

	return value
end

function BufferReader:ReadFloat32(): number
	self:_ensureReadable(4)

	local value = buffer.readf32(
		self.Data,
		self.Position
	)

	self.Position += 4

	return value
end

function BufferReader:ReadFloat64(): number
	self:_ensureReadable(8)

	local value = buffer.readf64(
		self.Data,
		self.Position
	)

	self.Position += 8

	return value
end

function BufferReader:ReadString(length: number): string -- Reads a string of a given length (As I mentioned in BufferWriter.WriteString, this won't work with UTF16 because a character can take up more than 1 byte)
	assert(
		length >= 0 and length % 1 == 0,
		"String length must be a non-negative integer"
	)

	self:_ensureReadable(length)

	local value = buffer.readstring(
		self.Data,
		self.Position,
		length
	)

	self.Position += length

	return value
end

function BufferReader:IsFinished(): boolean -- Returns whether or not the buffer has been read entirely
	return self.Position == buffer.len(self.Data)
end

return BufferReader
