--!strict

-- Not much to go into detail here, fairly self-explanatory
-- return nil because this module does not have any behavior during runtime, it's only for exporting types

export type Writer = {
	Data: buffer,
	Position: number,

	WriteUInt8: (self: Writer, value: number) -> (),
	WriteUInt16: (self: Writer, value: number) -> (),
	WriteUInt32: (self: Writer, value: number) -> (),

	WriteInt8: (self: Writer, value: number) -> (),
	WriteInt16: (self: Writer, value: number) -> (),
	WriteInt32: (self: Writer, value: number) -> (),

	WriteFloat32: (self: Writer, value: number) -> (),
	WriteFloat64: (self: Writer, value: number) -> (),

	WriteString: (self: Writer, value: string) -> (),
	ToBuffer: (self: Writer) -> buffer,
};

export type Reader = {
	Data: buffer,
	Position: number,

	ReadUInt8: (self: Reader) -> number,
	ReadUInt16: (self: Reader) -> number,
	ReadUInt32: (self: Reader) -> number,

	ReadInt8: (self: Reader) -> number,
	ReadInt16: (self: Reader) -> number,
	ReadInt32: (self: Reader) -> number,

	ReadFloat32: (self: Reader) -> number,
	ReadFloat64: (self: Reader) -> number,

	ReadString: (self: Reader, length: number) -> string,
	IsFinished: (self: Reader) -> boolean,
};

export type SchemaContext = {
	Depth: number,
};

export type Schema = {
	Name: string,

	Write: (
		writer: Writer,
		value: any,
		context: SchemaContext
	) -> (),

	Read: (
		reader: Reader,
		context: SchemaContext
	) -> any,
};

export type StructField = {
	Name: string,
	Type: Schema,
};

export type PacketDefinition = {
	Id: number,
	Name: string,
	Schema: { Schema },
};

return nil;
