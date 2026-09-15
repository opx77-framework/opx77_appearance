--- The server half: what every other client needs to draw a player at all.
---
--- On this platform an observer builds its proxy of another player only from what it is handed:
--- the body (family and customization groups, `Open77.puppets.setBody`), each equipment slot
--- (`setSlot`) and the wardrobe (`setWardrobe`). The engine replicates none of them. The
--- platform's open77_appearance, with its open77_equipment and open77_wardrobe relays, does this;
--- this resource replaces all three, so it does too: a player's look to everybody else when it
--- is published, everybody's look to a client that asks after entering a world, and both ways
--- between the players of a routing bucket whenever somebody enters it, because the native
--- roster retires the replicas of a player who changes bucket.
---
--- What a client publishes is its own presentation, read from its own engine, and it can only
--- ever describe that one player: the server takes the player id from the connection and checks
--- the shape, never the truth. Nothing here is stored; a restart asks every client again.

local Config = OPX_APPEARANCE_CONFIG

local PRESENT = 'opx77_appearance:present'
local ABSENT = 'opx77_appearance:absent'
local REPLAY = 'opx77_appearance:replay'
local ACK = 'opx77_appearance:presentAck'
local REPLAYED = 'opx77_appearance:replayed'
local LOOK = 'opx77_appearance:look'
local RESEND = 'opx77_appearance:resend'

--- The platform's package: while it runs, it hands looks out and this half stays out of its way.
local OFFICIAL = 'open77_appearance'

--- The least time between two publications, and between two replay requests, of one player, in
--- ms. A client retries either when nobody answered, so a dropped one costs seconds, not a look.
local FLOOR_MS = 500

--- The most one encoded body may weigh, as the platform bounds it, and the clothing beside it.
local MAX_BODY_BYTES = 49152
local MAX_CLOTHING_BYTES = 4096

local SLOTS = { 'Head', 'Face', 'InnerChest', 'OuterChest', 'Legs', 'Feet', 'Outfit',
	'UnderwearTop', 'UnderwearBottom' }
local OUTFIT = { Head = true, Face = true, InnerChest = true, OuterChest = true, Legs = true,
	Feet = true, Outfit = true }

--- player id -> { body, equipment, wardrobe }, the last look accepted for that player.
---@type table<integer, AppearanceLook>
local looks = {}
--- player id -> true while that player's body is away: a reload is putting a new puppet up.
---@type table<integer, boolean>
local absent = {}
--- "kind:player" -> when that player last got through the floor.
---@type table<string, integer>
local lastAt = {}
--- player id -> true once that player's unreadable look has been said in the log.
---@type table<integer, boolean>
local warned = {}

---@return integer
local function nowMs()
	local read, seconds = pcall(Open77.time.monotonic)
	if read and type(seconds) == 'number' and seconds == seconds and seconds >= 0 and
		seconds < math.huge then
		return math.floor(seconds * 1000)
	end
	return 0
end

--- Whether this half hands looks out now: configured on, and the platform's package not running.
local officialSaid = false
---@return boolean
local function enabled()
	if Config.PRESENT_BODIES == false then return false end
	local read, state = pcall(GetResourceState, OFFICIAL)
	if read and state == 'running' then
		if not officialSaid then
			officialSaid = true
			Open77.log.warn(OFFICIAL .. ' is running and hands looks out itself; this resource does ' ..
				'not. Two appearance resources fight over the bootstrap and the face: run one.')
		end
		return false
	end
	officialSaid = false
	return true
end

---@param kind string
---@param player integer
---@return boolean  true when this one is inside the floor
local function cooled(kind, player)
	local key, atMs = kind .. ':' .. player, nowMs()
	if lastAt[key] and atMs - lastAt[key] < FLOOR_MS then return true end
	lastAt[key] = atMs
	return false
end

-- ---------------------------------------------------------------------------
-- Shapes
-- ---------------------------------------------------------------------------

---@param value any
---@return boolean
local function isInteger(value)
	return type(value) == 'number' and value == value and value % 1 == 0
end

--- A native hash as the engine prints it: `0x` and sixteen hex digits, not all zero.
---@param value any
---@return boolean
local function fixedHash(value)
	return type(value) == 'string' and #value == 18 and value:sub(1, 2) == '0x' and
		value:sub(3):match('^%x+$') ~= nil and value ~= '0x0000000000000000'
end

--- The body `Open77.appearance.captureBody` reads: a family and up to 64 groups of head, body
--- or arms customization keys, each a pair of hashes. The platform's own bounds.
---@param body any
---@return boolean
local function validBody(body)
	if type(body) ~= 'table' or type(body.groups) ~= 'table' then return false end
	if body.family ~= 'male' and body.family ~= 'female' then return false end
	local count = #body.groups
	if count == 0 or count > 64 then return false end
	local seen = {}
	for index, group in pairs(body.groups) do
		if not isInteger(index) or index < 1 or index > count or type(group) ~= 'table' then
			return false
		end
		if group.part ~= 'head' and group.part ~= 'body' and group.part ~= 'arms' then return false end
		if not fixedHash(group.name) or type(group.keys) ~= 'table' then return false end
		local id = group.part .. ':' .. group.name:lower()
		if seen[id] then return false end
		seen[id] = true
		local keys = #group.keys
		if keys == 0 or keys > 64 then return false end
		for keyIndex, key in pairs(group.keys) do
			if not isInteger(keyIndex) or keyIndex < 1 or keyIndex > keys or type(key) ~= 'table' or
				#key ~= 2 or not fixedHash(key[1]) or not fixedHash(key[2]) then
				return false
			end
		end
	end
	local encoded, text = pcall(json.encode, body)
	return encoded and type(text) == 'string' and #text <= MAX_BODY_BYTES
end

--- A record name, or false for an empty slot.
---@param value any
---@return boolean
local function validItem(value)
	return value == false or (type(value) == 'string' and #value >= 1 and #value <= 160 and
		value:match('^[%w_%.%-]+$') ~= nil)
end

--- The nine equipment slots, every one stated: a record name, or false. What cannot be read is
--- an empty slot, never a refused look: a hat must not cost the player their body.
---@param value any
---@return table<string, string|false>
local function equipmentOf(value)
	local clean = {}
	for _, slot in ipairs(SLOTS) do
		local item = type(value) == 'table' and value[slot] or false
		clean[slot] = validItem(item) and item or false
	end
	return clean
end

--- The wardrobe: the active outfit index or none, and up to seven outfits by index "0".."6",
--- each overriding the seven visible slots. What cannot be read is left out.
---@param value any
---@return table
local function wardrobeOf(value)
	local wardrobe = { outfits = {}, names = {} }
	if type(value) ~= 'table' then return wardrobe end
	if isInteger(value.active) and value.active >= 0 and value.active <= 6 then
		wardrobe.active = value.active
	end
	for index, slots in pairs(type(value.outfits) == 'table' and value.outfits or {}) do
		local number = tonumber(index)
		if isInteger(number) and number >= 0 and number <= 6 and type(slots) == 'table' then
			local clean = {}
			for slot, item in pairs(slots) do
				if OUTFIT[slot] and validItem(item) then clean[slot] = item end
			end
			wardrobe.outfits[tostring(math.floor(number))] = clean
		end
	end
	return wardrobe
end

-- ---------------------------------------------------------------------------
-- Delivery
-- ---------------------------------------------------------------------------

--- Every connected player id; empty when the host cannot say.
---@return integer[]
local function everybody()
	local read, list = pcall(Open77.players.all)
	local ids = {}
	for _, id in ipairs(read and type(list) == 'table' and list or {}) do
		id = tonumber(id)
		if id then ids[#ids + 1] = id end
	end
	return ids
end

--- One player's look to one viewer. The owner is never sent its own: the platform's relays
--- ignore their own player, whose look is the engine's, not a record.
---@param viewer integer
---@param player integer
local function deliver(viewer, player)
	if viewer == player then return end
	local look = looks[player]
	if look == nil then return end
	-- not `absent and false or look`: that reads the look back whenever the body is away
	if absent[player] then
		TriggerClientEvent(LOOK, viewer, player, false)
	else
		TriggerClientEvent(LOOK, viewer, player, look)
	end
end

--- A player's look to everybody else.
---@param player integer
local function broadcast(player)
	for _, other in ipairs(everybody()) do deliver(other, player) end
end

--- The ids of the players in a routing bucket, or everybody when the host cannot say.
---@param bucket integer
---@return integer[]
local function playersIn(bucket)
	local reader = type(Open77.players) == 'table' and Open77.players.inBucket or nil
	if type(reader) ~= 'function' then reader = rawget(_G, 'GetPlayersInBucket') end
	local read, list = false, nil
	if type(reader) == 'function' then read, list = pcall(reader, bucket) end
	if not read or type(list) ~= 'table' then return everybody() end
	local ids = {}
	for _, id in ipairs(list) do
		id = tonumber(id)
		if id then ids[#ids + 1] = id end
	end
	return ids
end

--- The bucket a player is in now, or nil where the host cannot say.
---@param player integer
---@return integer|nil
local function bucketOf(player)
	local ns = type(Open77.routingBuckets) == 'table' and Open77.routingBuckets or {}
	local reader = ns.getPlayer or rawget(_G, 'GetPlayerRoutingBucket')
	if type(reader) ~= 'function' then return nil end
	local read, bucket = pcall(reader, player)
	return read and tonumber(bucket) or nil
end

---@param player integer
local function forget(player)
	looks[player], absent[player], warned[player] = nil, nil, nil
	local prefix = ':' .. player
	for key in pairs(lastAt) do
		if key:sub(-#prefix) == prefix then lastAt[key] = nil end
	end
end

RegisterNetEvent(PRESENT, function(body, equipment, wardrobe, sequence)
	local player = tonumber(source)
	if not player or player <= 0 or not isInteger(sequence) or sequence < 1 then return end
	if not enabled() or cooled('present', player) then return end

	if not validBody(body) then
		if not warned[player] then
			warned[player] = true
			Open77.log.warn(('player %d published a body this server cannot read; other players ' ..
				'cannot draw them'):format(player))
		end
		-- answered all the same: resending the same unreadable body every few seconds helps nobody
		TriggerClientEvent(ACK, player, sequence, false)
		return
	end
	local look = { body = body, equipment = equipmentOf(equipment), wardrobe = wardrobeOf(wardrobe) }
	local encoded, text = pcall(json.encode, { look.equipment, look.wardrobe })
	if not encoded or type(text) ~= 'string' or #text > MAX_CLOTHING_BYTES then
		look.equipment, look.wardrobe = equipmentOf(nil), wardrobeOf(nil)
	end

	warned[player] = nil
	looks[player] = look
	absent[player] = nil
	broadcast(player)
	TriggerClientEvent(ACK, player, sequence, true)
	Open77.log.debug(('look of player %d published (%s, %d groups)')
		:format(player, body.family, #body.groups))
end)

--- A client that entered a world holds no proxy of anybody: it gets every look there is, whatever
--- state its own is in.
RegisterNetEvent(REPLAY, function(sequence)
	local player = tonumber(source)
	if not player or player <= 0 or not isInteger(sequence) then return end
	if not enabled() or cooled('replay', player) then return end
	for other in pairs(looks) do deliver(player, other) end
	TriggerClientEvent(REPLAYED, player, sequence)
end)

--- The player's body is being reloaded: observers drop their proxy and get it back with the look
--- that follows.
RegisterNetEvent(ABSENT, function()
	local player = tonumber(source)
	if not player or player <= 0 or not enabled() or absent[player] then return end
	absent[player] = true
	if looks[player] ~= nil then broadcast(player) end
end)

--- The native roster retires a player's replicas when that player changes bucket, and nothing
--- the engine replicates rebuilds them: both sides get each other's looks again.
AddEventHandler('onPlayerBucketChange', function(player, bucket, previous)
	player, bucket, previous = tonumber(player), tonumber(bucket), tonumber(previous)
	if not player or player <= 0 or not bucket or bucket == previous or not enabled() then return end
	-- a queued move another one has already superseded, or a player who has left since
	local read, name = pcall(Open77.players.name, player)
	if not read or name == nil then return end
	local current = bucketOf(player)
	if current ~= nil and current ~= bucket then return end
	for _, other in ipairs(playersIn(bucket)) do
		if other ~= player then
			deliver(player, other)
			deliver(other, player)
		end
	end
end)

AddEventHandler('onPlayerDisconnected', function(playerId)
	local player = tonumber(playerId)
	if player then forget(player) end
end)

AddEventHandler('playerDropped', function()
	local player = tonumber(source)
	if player then forget(player) end
end)

AddEventHandler('onResourceStart', function(name)
	if name ~= GetCurrentResourceName() then return end
	if Config.PRESENT_BODIES == false then
		Open77.log.info('PRESENT_BODIES is false: another resource must hand every look out')
		return
	end
	-- nothing survives a restart here: every client already in the world publishes and asks again
	TriggerClientEvent(RESEND, -1)
end)
