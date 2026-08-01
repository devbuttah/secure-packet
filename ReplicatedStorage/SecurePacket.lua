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

-- Services
const RunService = game:GetService("RunService")
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const EncodingService = game:GetService("EncodingService")

-- Requires helper modules 
const BufferWriter = require(script.BufferWriter)
const BufferReader = require(script.BufferReader)
const Schemas = require(script.Schemas)
const Types = require(script.Types)

type Schema = Types.Schema
type PacketDefinition = Types.PacketDefinition

const IS_SERVER = RunService:IsServer() -- Utilizes RunService to determine whether the current execution context is Server or Client

const REMOTE_NAME = "ILoveHiddenDevsRemote" -- Just for jokes, it's normally called SecurePacketRemote but wtv
const COMPRESSION_THRESHOLD = 512 -- *Bytes*
const MAX_PAYLOAD_SIZE = 1024 * 1024 -- *Bytes*

const COMPRESSION_ALGORITHM = Enum.CompressionAlgorithm.Zstd --  The only Compression-Algorithm supported by roblox :( (But just incase they decide to add more in the future)

const COMPRESSION_LEVEL = 1 -- * min: -22, max: 22 *

local function getRemote(): RemoteEvent -- Gets the RemoteEvent if it already exists, otherwise it creates a new one. Should the existing object not be of type RemoteEvent, it also outputs an error message
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

		local created = Instance.new("RemoteEvent") -- Creates the new RemoteEvent if it does not already eixst
		created.Name = REMOTE_NAME
		created.Parent = ReplicatedStorage

		return created
	end

	return ReplicatedStorage:WaitForChild(REMOTE_NAME) :: RemoteEvent -- Casts it to a RemoteEvent to fulfill the return type of the function ;)
end

local remote = getRemote() -- Calls the getRemote() function above which handles the logic of wheter or not it already exists to prevent duplicates

local SecurePacket = {}

--[[
	Dictionaries acting as registries, definitionsByName and definitionsById store them as a string and number while serverHandlers and clientHandlers store callback functions
--]]
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

local nextPacketId = 0 -- Super fancy counter... (for making sure every packet gets a unique id)

function SecurePacket.Define(packetName: string, schema: { Schema }): PacketDefinition -- Creates a new PacketDefinition based on the schema
	assert( -- Makes sure packetName is of type string and that the string is not empty (#packetName > 0), if not, outputs an error message
		type(packetName) == "string"
			and #packetName > 0,
		"SecurePacket - Packet name must be a non-empty string"
	)

	assert( -- Makes sure that the packetName does not already exist in the lookup tables (as explained above, they act as registries)
		definitionsByName[packetName] == nil,
		`SecurePacket - Packet "{packetName}" is already defined`
	)

	assert( -- Makes sure the packetId does not go above 65535 which is the maximum number an unsigned 16 bit integer can hold...
		nextPacketId <= 65535,
		"SecurePacket - Packet has exceeded its UInt16 packet ID limit" -- If this happens you're doing something wrong 😭
	)

	local definition: PacketDefinition = { -- Self explanatory, creates a PacketDefinition and fills its attributes with the values parsed into the function
		Id = nextPacketId,
		Name = packetName,
		Schema = schema,
	}

	nextPacketId += 1 -- increments the counter

	--[[
		Adds the packet name and packet id into the lookup tables / registries to ensure no other packet is created with the same id / name
	--]]
	definitionsByName[packetName] = definition
	definitionsById[definition.Id] = definition

	return definition
end

local function encodePacket(definition: PacketDefinition, arguments: { [number]: any } & { n: number }): buffer -- Converts the data inside a packet into binary using buffers
	assert(arguments.n == #definition.Schema, `Packet "{definition.Name}" expected {#definition.Schema} arguments, got {arguments.n}`) -- Maybe I should have used a line break here, it makes sure that you actually parse as many values as were pre-defined in the schema

	local writer = BufferWriter.new() -- creates a new BufferWriter
	local context = {
		Depth = 0,
	}

	for index, fieldSchema in definition.Schema do -- iterates through every field in the packet schema
		local success, problem = pcall( -- uses pcall to catch an error if one occurs
			fieldSchema.Write, -- calls fieldSchema.Write with writer, arguments[index] and context as the function parameters
			writer,
			arguments[index],
			context
		)

		if not success then -- outputs an error explaining that there was a problem when encoding the packet
			error(`Failed to encode argument {index} of "{definition.Name}" as {fieldSchema.Name}: {problem}`, 3)
		end
	end

	return writer:ToBuffer() -- returns the final buffer
end

local function decodePacket( -- converts the data inside a packet that is already in binary back to normal data
	definition: PacketDefinition,
	data: buffer
): { [number]: any } & { n: number }
	local reader = BufferReader.new(data) -- creates a new BufferReader and includes the data (buffer) to read
	local context = {
		Depth = 0,
	}

	local arguments = table.create(#definition.Schema)
	arguments.n = #definition.Schema

	for index, fieldSchema in definition.Schema do -- iterates through all fields in the packet schema
		local success, value = pcall( -- using pcall to catch an error should one occur
			fieldSchema.Read, -- calls fieldSchema.Read with the reader and context as function parameters
			reader,
			context
		)

		if not success then -- outputs an error that there was a problem when decoding the packet
			error(`Failed to decode argument {index} of "{definition.Name}" as {fieldSchema.Name}: {value}`)
		end

		arguments[index] = value
	end

	assert(reader:IsFinished(), `Packet "{definition.Name}" contains trailing bytes`) -- If the reader does not finish reading all bytes, it outputs an error

	return arguments -- returns the "normalized" data
end

local function compressPayload(data: buffer): (buffer, boolean) -- Uses EncodingService to compress the buffer
	if buffer.len(data) < COMPRESSION_THRESHOLD then -- Skips compression if the packet is too small (not worth the cpu usage)
		return data, false
	end

	local compressed = EncodingService:CompressBuffer( -- Compresses the buffer using the compression algo and compression level which are defined at the top of this module
		data,
		COMPRESSION_ALGORITHM,
		COMPRESSION_LEVEL
	)

	if buffer.len(compressed) >= buffer.len(data) then -- If the compressed version of the buffer is bigger than the non-compressed version, it returns the non-compressed version (This should honestly not happen normally...)
		return data, false
	end

	return compressed, true -- Returns the compressed buffer
end

local function decompressPayload(payload: any, isCompressed: any): buffer -- Uses EncodingService to decompress the buffer
	assert( -- Should the payload not be of type buffer, it outputs an error
		typeof(payload) == "buffer",
		"Payload must be a buffer"
	)

	assert( -- Should isCompressed not be a boolean for whatever reason, it outputs an error
		type(isCompressed) == "boolean",
		"Compression flag must be a boolean"
	)

	if not isCompressed then -- if the buffer is not compressed, we simply return it as it is, since it does not need to be decompressed
		assert(buffer.len(payload) <= MAX_PAYLOAD_SIZE, "Payload exceeds the size limit") -- Outputs an error if the buffer is too big

		return payload
	end

	local decompressedSize =
		EncodingService:GetDecompressedBufferSize(payload, COMPRESSION_ALGORITHM) -- I'm so happy they let you get the Decompressed size without having to decompress it

	assert( -- Checks if the decompressedSize of the buffer is nil, if yes, it outputs an error
		decompressedSize ~= nil,
		"Compressed payload is invalid"
	)

	assert( -- Checks if the decompressed buffer is too big, if yes, it outputs an error
		decompressedSize <= MAX_PAYLOAD_SIZE,
		"Decompressed payload exceeds the size limit"
	)

	return EncodingService:DecompressBuffer( -- Decompressed the buffer using the same algo we used to compress it
		payload,
		COMPRESSION_ALGORITHM
	)
end

--[[
	Defines the type PacketObject, which contains all relevant information about a Packet, including callback functions
--]]
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

local function encodePacketObject(self: PacketObject): (buffer, boolean) -- Helper function that allows you to parse a PacketObject and get the encoded buffer as well as whether or not it was actually compressed 
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

function Packet:FireServer() -- FireServer implementation for Packets
	assert(not IS_SERVER, "FireServer can only be called from the client") -- Check if the function is called from the client, if not, it ouputs an error

	local payload, compressed = encodePacketObject(self) -- encodes and compresses the content of the Packet (only if it hasnt already be done)

	remote:FireServer(self.Definition.Id, payload, compressed) -- fires the remote containing the data to the server
end

function Packet:FireClient(player: Player) -- FireClient implementation for Packets
	assert(IS_SERVER, "FireClient can only be called from the server") -- Check if the function is called from the server, if not, it outputs an error

	assert(typeof(player) == "Instance" and player:IsA("Player"), "FireClient requires a Player") -- Makes sure the remote is being fired to a valid player

	local payload, compressed = encodePacketObject(self) -- encodes and compresses the content of the packet (only if not already done)

	remote:FireClient(player, self.Definition.Id, payload, compressed) --  fires the remote containing the data to the client
end

function Packet:FireAllClients() -- FireAllClients implementation for Packets
	assert(IS_SERVER, "FireAllClients can only be called from the server") -- Yeah I think you get the idea by now

	local payload, compressed = encodePacketObject(self) -- Just read the documentation in FireServer or FireClient

	remote:FireAllClients(self.Definition.Id, payload, compressed) -- fires the remote containing the data to all clients
end

function SecurePacket.OnServer(packetName: string, handler: (Player, ...any) -> ()): () -> () -- Creates a server Listener on the client for a packet (Same as RemoteEvent.OnServerEvent). Clarification: Function returns an anonymous function with no args or return type
	assert( -- Makes sure it gets called by the server, if not, it outputs an error
		IS_SERVER,
		"OnServer can only be called from the server"
	)

	assert( -- Checks if the registry already contains that packetName, if not, it outputs an error
		definitionsByName[packetName] ~= nil,
		`Packet "{packetName}" has not been defined`
	)

	assert( -- Checks if the registry already contains a server handler for that packet, if it does, it outputs an error
		serverHandlers[packetName] == nil,
		`Packet "{packetName}" already has a server handler`
	)

	serverHandlers[packetName] = handler -- adds the server handler to the registry so there cant be multiple for the same packet

	return function() -- returns a closure to allow for unregistering the handler later
		if serverHandlers[packetName] == handler then
			serverHandlers[packetName] = nil
		end
	end
end

function SecurePacket.OnClient(packetName: string, handler: (...any) -> ()): () -> () -- Creates a Listener on the server for a packet (Same as RemoteEvent.OnClientEvent)
	assert(not IS_SERVER, "OnClient can only be called from the client") -- Makes sure it gets called by the client, if not, it outputs an error

	assert(definitionsByName[packetName] ~= nil, `Packet "{packetName}" has not been defined`) -- Checks if the registry already contains that packetName, if not, it outputs an error

	assert(clientHandlers[packetName] == nil, `Packet "{packetName}" already has a client handler`) -- Checks if the registry already contains a client handler for that packet, if it does, it outputs an error

	clientHandlers[packetName] = handler -- adds the client handler to the registry so there cant be multiple for the same packet

	return function() -- returns a closure to allow for unregistering the handler later
		if clientHandlers[packetName] == handler then
			clientHandlers[packetName] = nil
		end
	end
end

local function createPacket(packetName: string, ...: any): PacketObject -- Creates a packet with a name and optional arguments
	local definition = definitionsByName[packetName]

	assert(definition ~= nil, `Packet "{packetName}" has not been defined`) -- Checks if the packet name has already been registered, if not, it throws an error

	return setmetatable({ -- creates and returns the new packet object
		Definition = definition,
		Arguments = table.pack(...),
	}, Packet) :: any
end

--[[
	Makes it possible to create a packet by doing SecurePacket(...) instead of having to do SecurePacket.createPacket(...), so basically its a constructor
--]]
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
		if type(packetId) ~= "number" -- Makes sure packetId is of type number and that its a whole number
			or packetId % 1 ~= 0
		then
			return
		end

		local definition = definitionsById[packetId]

		if not definition then -- Makes sure the id is registered
			return
		end

		local handler = serverHandlers[definition.Name]

		if not handler then -- Makes sure a handler is registered
			return
		end

		local success, problem = pcall(function() -- Pcall to make sure if any of the three steps below fail, that it outputs an error
			local restored = decompressPayload( -- Decompresses the packet if it was compressed
				payload,
				compressed
			)

			local arguments = decodePacket( -- Converts it from bytes to Luau values
				definition,
				restored
			)

			handler( -- Calls the packets registered handler
				player,
				table.unpack(
					arguments,
					1,
					arguments.n
				)
			)
		end)

		if not success then
			warn(`SecurePacket rejected "{definition.Name}" from {player.Name}: {problem}`) -- outputs an error if there was one
		end
	end)
else -- Redirects client RemoteEvent calls to the client listener (again, if there is one) Same documentation as above btw
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
