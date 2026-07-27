--!strict

-- Roblox Username: devbuddah / devbuttah (main, currently suspended) 
-- Discord: devbuttah (1183123383693627557)

--[[ 
	Fun little project mostly for personal use to reduce network load when dealing with things like sending large amounts of data (like inventories, etc.)
	Inspired by "Packet" which was made by @5uphi
	No code was copied, just inspiration for the actual functionality / usage of the module!
	Plans for the future: Add DDOS-Protection (Rate Limiting Client -> Server), Add some sort of encryption (Obviously can be reverse-engineered easily since the client has to be able to encrypt / decrypt, just would make it harder for the average exploiter)
	Thanks for taking your time to review this, please don't take all comments too seriously, some are joke-ish.
--]]

--[[
	! USAGE !
	1. The SecurePacket Module & All Sub-Modules have to be put inside ReplicatedStorage.
	2. Create a new Module called "PacketSchemas", or whatever you feel like naming it.
	3. In it, you define a schema for your packets.
	4. You create a Script on the server (ServerScriptService) and a local script in StarterPlayerScripts.
	5. In the Server and the Client, you require PacketSchemas, inside PacketSchemas, you require the actual SecurePacket Module and define your packets:
	
	EXAMPLE:
		SecurePacket.Define("UpdateCash", {
			Schema.UInt16,
		})
		
	6. On the Client, you can then parse in the data into your packet (Make sure to use the correct datatype!)
	
	EXAMPLE:
		local ExamplePacket = SecurePacket(		-- When I require PacketSchemas I call it SecurePacket, but you can name it whatever you want
			"UpdateCash",						-- Use the exact name you defined!
			1,									-- Parse in the data
		)
		
	7. On the Server, you can once again require PacketSchemas and create a Listener for a specific Packet. (This is the same as OnServerEvent on normal Remotes)
	
	EXAMPLE: 
		SecurePacket.OnServer(
			"UpdateCash",
			function(player: Player, cash: number)
				print(player.Name, "has", cash, "Cash")
				-- Your logic here!
			end
		)
		
	8. SecurePacket automatically also includes the player instance who sent the Packet, just like in normal RemoteEvents.
	9. That's it, as you probably understand now, you can do the exact same thing but Server -> Client, there is also a FireAllClients option!
--]]

const RunService = game:GetService("RunService")
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const EncodingService = game:GetService("EncodingService")

const BufferWriter = require(script.BufferWriter)
const BufferReader = require(script.BufferReader)
const Schemas = require(script.Schemas)
const Types = require(script.Types)

type Schema = Types.Schema
type PacketDefinition = Types.PacketDefinition

const IS_SERVER = RunService:IsServer()

const REMOTE_NAME = "ILoveHiddenDevsRemote" -- Just for jokes, it's normally called SecurePacketRemote but wtv
const COMPRESSION_THRESHOLD = 512 -- *Bytes*
const MAX_PAYLOAD_SIZE = 1024 * 1024 -- *Bytes*

const COMPRESSION_ALGORITHM = Enum.CompressionAlgorithm.Zstd --  The only Compression-Algorithm supported by roblox :( (But just incase they decide to add more in the future)

const COMPRESSION_LEVEL = 1 -- * min: -22, max: 22 *

local function getRemote(): RemoteEvent -- Gets the RemoteEvent if it already exists, otherwise it creates a new one
	if IS_SERVER then
		local existing = ReplicatedStorage:FindFirstChild(
			REMOTE_NAME
		)

		if existing then
			assert(
				existing:IsA("RemoteEvent"),
				`{REMOTE_NAME} must be a RemoteEvent`
			)

			return existing
		end

		local created = Instance.new("RemoteEvent")
		created.Name = REMOTE_NAME
		created.Parent = ReplicatedStorage

		return created
	end

	return ReplicatedStorage:WaitForChild(REMOTE_NAME) :: RemoteEvent -- Casts it to a RemoteEvent to fulfill the return type of the function ;)
end

local remote = getRemote()

local SecurePacket = {}

local definitionsByName: {
	[string]: PacketDefinition
} = {}

local definitionsById: {
	[number]: PacketDefinition
} = {}

local serverHandlers: {
	[string]: (Player, ...any) -> ()
} = {}

local clientHandlers: {
	[string]: (...any) -> ()
} = {}

local nextPacketId = 0 -- Super fancy counter...

function SecurePacket.Define(packetName: string, schema: { Schema }): PacketDefinition -- Creates a new PacketDefinition based on the schema
	assert(
		type(packetName) == "string"
			and #packetName > 0,
		"SecurePacket - Packet name must be a non-empty string"
	)

	assert(
		definitionsByName[packetName] == nil,
		`SecurePacket - Packet "{packetName}" is already defined`
	)

	assert(
		nextPacketId <= 65535,
		"SecurePacket - Packet has exceeded its UInt16 packet ID limit" -- If this happens you're doing something wrong 😭
	)

	local definition: PacketDefinition = {
		Id = nextPacketId,
		Name = packetName,
		Schema = schema,
	}

	nextPacketId += 1

	definitionsByName[packetName] = definition
	definitionsById[definition.Id] = definition

	return definition
end

local function encodePacket(definition: PacketDefinition, arguments: { [number]: any } & { n: number }): buffer
	assert(arguments.n == #definition.Schema, `Packet "{definition.Name}" expected {#definition.Schema} arguments, got {arguments.n}`) -- Maybe I should have used a line break here

	local writer = BufferWriter.new()
	local context = {
		Depth = 0,
	}

	for index, fieldSchema in definition.Schema do
		local success, problem = pcall(
			fieldSchema.Write,
			writer,
			arguments[index],
			context
		)

		if not success then
			error(`Failed to encode argument {index} of "{definition.Name}" as {fieldSchema.Name}: {problem}`, 3)
		end
	end

	return writer:ToBuffer()
end

local function decodePacket(
	definition: PacketDefinition,
	data: buffer
): { [number]: any } & { n: number }
	local reader = BufferReader.new(data)
	local context = {
		Depth = 0,
	}

	local arguments = table.create(#definition.Schema)
	arguments.n = #definition.Schema

	for index, fieldSchema in definition.Schema do
		local success, value = pcall(
			fieldSchema.Read,
			reader,
			context
		)

		if not success then
			error(`Failed to decode argument {index} of "{definition.Name}" as {fieldSchema.Name}: {value}`)
		end

		arguments[index] = value
	end

	assert(reader:IsFinished(), `Packet "{definition.Name}" contains trailing bytes`)

	return arguments
end

local function compressPayload(data: buffer): (buffer, boolean) -- Uses EncodingService to compress the buffer
	if buffer.len(data) < COMPRESSION_THRESHOLD then
		return data, false
	end

	local compressed = EncodingService:CompressBuffer(
		data,
		COMPRESSION_ALGORITHM,
		COMPRESSION_LEVEL
	)

	if buffer.len(compressed) >= buffer.len(data) then
		return data, false
	end

	return compressed, true
end

local function decompressPayload(payload: any, isCompressed: any): buffer -- Uses EncodingService to decompress the buffer
	assert(
		typeof(payload) == "buffer",
		"Payload must be a buffer"
	)

	assert(
		type(isCompressed) == "boolean",
		"Compression flag must be a boolean"
	)

	if not isCompressed then
		assert(buffer.len(payload) <= MAX_PAYLOAD_SIZE, "Payload exceeds the size limit")

		return payload
	end

	local decompressedSize =
		EncodingService:GetDecompressedBufferSize(payload, COMPRESSION_ALGORITHM) -- I'm so happy they let you get the Decompressed size without having to decompress it

	assert(
		decompressedSize ~= nil,
		"Compressed payload is invalid"
	)

	assert(
		decompressedSize <= MAX_PAYLOAD_SIZE,
		"Decompressed payload exceeds the size limit"
	)

	return EncodingService:DecompressBuffer(
		payload,
		COMPRESSION_ALGORITHM
	)
end

type PacketObject = {
	Definition: PacketDefinition,
	Arguments: { [number]: any } & { n: number },

	GetEncodedSize: (self: PacketObject) -> number,

	FireServer: (self: PacketObject) -> (),
	FireClient: (
		self: PacketObject,
		player: Player
	) -> (),
	FireAllClients: (self: PacketObject) -> (),
}

local Packet = {}
Packet.__index = Packet

local function encodePacketObject(self: PacketObject): (buffer, boolean) -- Helper function
	local encoded = encodePacket(
		self.Definition,
		self.Arguments
	)

	return compressPayload(encoded)
end

function Packet:GetEncodedSize(): number -- Returns the size of the encoded packet (For showcasing purposes only!)
	local encoded = encodePacket(
		self.Definition,
		self.Arguments
	)

	return buffer.len(encoded)
end

function Packet:FireServer()
	assert(not IS_SERVER, "FireServer can only be called from the client") -- Check if the function is called from the client

	local payload, compressed = encodePacketObject(self)

	remote:FireServer(self.Definition.Id, payload, compressed)
end

function Packet:FireClient(player: Player)
	assert(IS_SERVER, "FireClient can only be called from the server") -- Check if the function is called from the server

	assert(typeof(player) == "Instance" and player:IsA("Player"), "FireClient requires a Player") -- Makes sure the remote is being fired to a valid player

	local payload, compressed = encodePacketObject(self)

	remote:FireClient(player, self.Definition.Id, payload, compressed)
end

function Packet:FireAllClients()
	assert(IS_SERVER, "FireAllClients can only be called from the server") -- Yeah I think you get the idea by now

	local payload, compressed = encodePacketObject(self)

	remote:FireAllClients(self.Definition.Id, payload, compressed)
end

function SecurePacket.OnServer(packetName: string, handler: (Player, ...any) -> ()): () -> () -- Creates a server Listener on the client for a packet (Same as RemoteEvent.OnServerEvent). Clarification: Function returns an anonymous function with no args or return type
	assert(
		IS_SERVER,
		"OnServer can only be called from the server"
	)

	assert(
		definitionsByName[packetName] ~= nil,
		`Packet "{packetName}" has not been defined`
	)

	assert(
		serverHandlers[packetName] == nil,
		`Packet "{packetName}" already has a server handler`
	)

	serverHandlers[packetName] = handler

	return function()
		if serverHandlers[packetName] == handler then
			serverHandlers[packetName] = nil
		end
	end
end

function SecurePacket.OnClient(packetName: string, handler: (...any) -> ()): () -> () -- Creates a Listener on the server for a packet (Same as RemoteEvent.OnClientEvent)
	assert(not IS_SERVER, "OnClient can only be called from the client")

	assert(definitionsByName[packetName] ~= nil, `Packet "{packetName}" has not been defined`)

	assert(clientHandlers[packetName] == nil, `Packet "{packetName}" already has a client handler`)

	clientHandlers[packetName] = handler

	return function()
		if clientHandlers[packetName] == handler then
			clientHandlers[packetName] = nil
		end
	end
end

local function createPacket(packetName: string, ...: any): PacketObject -- Creates a packet with a name and optional arguments
	local definition = definitionsByName[packetName]

	assert(definition ~= nil, `Packet "{packetName}" has not been defined`)

	return setmetatable({
		Definition = definition,
		Arguments = table.pack(...),
	}, Packet) :: any
end

setmetatable(SecurePacket, {
	__call = function(
		_,
		packetName: string,
		...: any
	): PacketObject
		return createPacket(packetName, ...)
	end,
})

if IS_SERVER then	-- Redirects server RemoteEvent calls to the server listener (if there is one)
	remote.OnServerEvent:Connect(function(player: Player, packetId: any, payload: any, compressed: any)
		if type(packetId) ~= "number"
			or packetId % 1 ~= 0
		then
			return
		end

		local definition = definitionsById[packetId]

		if not definition then
			return
		end

		local handler = serverHandlers[definition.Name]

		if not handler then
			return
		end

		local success, problem = pcall(function()
			local restored = decompressPayload(
				payload,
				compressed
			)

			local arguments = decodePacket(
				definition,
				restored
			)

			handler(
				player,
				table.unpack(
					arguments,
					1,
					arguments.n
				)
			)
		end)

		if not success then
			warn(`SecurePacket rejected "{definition.Name}" from {player.Name}: {problem}`)
		end
	end)
else -- Redirects client RemoteEvent calls to the client listener (again, if there is one)
	remote.OnClientEvent:Connect(function(packetId: any, payload: any, compressed: any)
		if type(packetId) ~= "number"
			or packetId % 1 ~= 0
		then
			return
		end

		local definition = definitionsById[packetId]

		if not definition then
			return
		end

		local handler = clientHandlers[definition.Name]

		if not handler then
			return
		end

		local success, problem = pcall(function()
			local restored = decompressPayload(
				payload,
				compressed
			)

			local arguments = decodePacket(
				definition,
				restored
			)

			handler(
				table.unpack(
					arguments,
					1,
					arguments.n
				)
			)
		end)

		if not success then
			warn(`SecurePacket failed to decode "{definition.Name}": {problem}`)
		end
	end)
end

SecurePacket.Schema = Schemas

return SecurePacket
