--- @author DemiAutomatic
--- @file server/presence.lua
--- @description Hands every player's look to the other players, in memory.

local Config = OPX_APPEARANCE_CONFIG

--- @author DemiAutomatic
--- @type {string}
--- @description Net event a client publishes its look on.
local PRESENT = 'opx77_appearance:present'

--- @author DemiAutomatic
--- @type {string}
--- @description Net event a client withdraws its body on.
local ABSENT = 'opx77_appearance:absent'

--- @author DemiAutomatic
--- @type {string}
--- @description Net event a client asks for everybody else's look on.
local REPLAY = 'opx77_appearance:replay'

--- @author DemiAutomatic
--- @type {string}
--- @description Net event answering a publication.
local ACK = 'opx77_appearance:presentAck'

--- @author DemiAutomatic
--- @type {string}
--- @description Net event answering a replay request.
local REPLAYED = 'opx77_appearance:replayed'

--- @author DemiAutomatic
--- @type {string}
--- @description Net event carrying one player's look to a viewer.
local LOOK = 'opx77_appearance:look'

--- @author DemiAutomatic
--- @type {string}
--- @description Net event asking every client to publish and ask again.
local RESEND = 'opx77_appearance:resend'

--- @author DemiAutomatic
--- @type {string}
--- @description The platform's package, which hands looks out while it runs.
local OFFICIAL = 'open77_appearance'

--- @author DemiAutomatic
--- @type {integer}
--- @description Least milliseconds between two publications or replays of a player.
local FLOOR_MS = 500

--- @author DemiAutomatic
--- @type {integer}
--- @description Most bytes one encoded body may weigh.
local MAX_BODY_BYTES = 49152

--- @author DemiAutomatic
--- @type {integer}
--- @description Most bytes the encoded equipment and wardrobe may weigh.
local MAX_CLOTHING_BYTES = 4096

--- @author DemiAutomatic
--- @type {string[]}
--- @description The nine equipment slots of a look.
local SLOTS = { 'Head', 'Face', 'InnerChest', 'OuterChest', 'Legs', 'Feet', 'Outfit',
	'UnderwearTop', 'UnderwearBottom' }

--- @author DemiAutomatic
--- @type {table<string, boolean>}
--- @description The seven visible slots an outfit may override.
local OUTFIT = { Head = true, Face = true, InnerChest = true, OuterChest = true, Legs = true,
	Feet = true, Outfit = true }

--- @author DemiAutomatic
--- @type {table<integer, AppearanceLook>}
--- @description The last look accepted for each player.
local looks = {}

--- @author DemiAutomatic
--- @type {table<integer, boolean>}
--- @description Players whose body is away during a reload.
local absent = {}

--- @author DemiAutomatic
--- @type {table<string, integer>}
--- @description When each player last got through the floor, by kind.
local lastAt = {}

--- @author DemiAutomatic
--- @type {table<integer, boolean>}
--- @description Players whose unreadable body was already logged.
local warned = {}

--- @author DemiAutomatic
--- @method nowMs
--- @description Reads the monotonic clock in milliseconds, 0 when unusable.
--- @returns {integer}
local function nowMs()
	local read, seconds = pcall(Open77.time.monotonic)
	if read and type(seconds) == 'number' and seconds == seconds and seconds >= 0 and
		seconds < math.huge then
		return math.floor(seconds * 1000)
	end
	return 0
end

--- @author DemiAutomatic
--- @type {boolean}
--- @description The running platform package was already logged.
local officialSaid = false

--- @author DemiAutomatic
--- @method enabled
--- @description Whether this half hands looks out now.
--- @returns {boolean}
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

--- @author DemiAutomatic
--- @method cooled
--- @description Whether a player's request of this kind falls inside the floor.
--- @param kind {string}
--- @param player {integer}
--- @returns {boolean}
local function cooled(kind, player)
	local key, atMs = kind .. ':' .. player, nowMs()
	if lastAt[key] and atMs - lastAt[key] < FLOOR_MS then return true end
	lastAt[key] = atMs
	return false
end

--- @author DemiAutomatic
--- @method isInteger
--- @description Whether a value is a finite integral number.
--- @param value {any}
--- @returns {boolean}
local function isInteger(value)
	return type(value) == 'number' and value == value and value % 1 == 0
end

--- @author DemiAutomatic
--- @method fixedHash
--- @description Whether a value is a non-zero sixteen-digit native hash.
--- @param value {any}
--- @returns {boolean}
local function fixedHash(value)
	return type(value) == 'string' and #value == 18 and value:sub(1, 2) == '0x' and
		value:sub(3):match('^%x+$') ~= nil and value ~= '0x0000000000000000'
end

--- @author DemiAutomatic
--- @method validBody
--- @description Whether a body has the shape and bounds the platform accepts.
--- @param body {any}
--- @returns {boolean}
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

--- @author DemiAutomatic
--- @method validItem
--- @description Whether a value is a record name or false.
--- @param value {any}
--- @returns {boolean}
local function validItem(value)
	return value == false or (type(value) == 'string' and #value >= 1 and #value <= 160 and
		value:match('^[%w_%.%-]+$') ~= nil)
end

--- @author DemiAutomatic
--- @method equipmentOf
--- @description Answers all nine slots, an unreadable one as empty.
--- @param value {any}
--- @returns {table<string, string|false>}
local function equipmentOf(value)
	local clean = {}
	for _, slot in ipairs(SLOTS) do
		local item = type(value) == 'table' and value[slot] or false
		clean[slot] = validItem(item) and item or false
	end
	return clean
end

--- @author DemiAutomatic
--- @method wardrobeOf
--- @description Answers the readable active outfit and outfit overrides.
--- @param value {any}
--- @returns {table}
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

--- @author DemiAutomatic
--- @method everybody
--- @description Answers every connected player id, empty when unknown.
--- @returns {integer[]}
local function everybody()
	local read, list = pcall(Open77.players.all)
	local ids = {}
	for _, id in ipairs(read and type(list) == 'table' and list or {}) do
		id = tonumber(id)
		if id then ids[#ids + 1] = id end
	end
	return ids
end

--- @author DemiAutomatic
--- @method deliver
--- @description Sends one player's look, or its absence, to one other viewer.
--- @param viewer {integer}
--- @param player {integer}
local function deliver(viewer, player)
	if viewer == player then return end
	local look = looks[player]
	if look == nil then return end
	if absent[player] then
		TriggerClientEvent(LOOK, viewer, player, false)
	else
		TriggerClientEvent(LOOK, viewer, player, look)
	end
end

--- @author DemiAutomatic
--- @method broadcast
--- @description Sends a player's look to everybody else.
--- @param player {integer}
local function broadcast(player)
	for _, other in ipairs(everybody()) do deliver(other, player) end
end

--- @author DemiAutomatic
--- @method playersIn
--- @description Answers the players in a routing bucket, or everybody when unknown.
--- @param bucket {integer}
--- @returns {integer[]}
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

--- @author DemiAutomatic
--- @method bucketOf
--- @description Answers a player's current routing bucket, nil when unknown.
--- @param player {integer}
--- @returns {integer|nil}
local function bucketOf(player)
	local ns = type(Open77.routingBuckets) == 'table' and Open77.routingBuckets or {}
	local reader = ns.getPlayer or rawget(_G, 'GetPlayerRoutingBucket')
	if type(reader) ~= 'function' then return nil end
	local read, bucket = pcall(reader, player)
	return read and tonumber(bucket) or nil
end

--- @author DemiAutomatic
--- @method forget
--- @description Forgets a departed player's look, absence, warning and floors.
--- @param player {integer}
local function forget(player)
	looks[player], absent[player], warned[player] = nil, nil, nil
	local prefix = ':' .. player
	for key in pairs(lastAt) do
		if key:sub(-#prefix) == prefix then lastAt[key] = nil end
	end
end

--- @author DemiAutomatic
--- @event opx77_appearance:present
--- @description Accepts a player's own look, hands it on and answers.
--- @param body {AppearanceBody}
--- @param equipment {table}
--- @param wardrobe {table}
--- @param sequence {integer}
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

--- @author DemiAutomatic
--- @event opx77_appearance:replay
--- @description Sends every held look to a client that entered a world.
--- @param sequence {integer}
RegisterNetEvent(REPLAY, function(sequence)
	local player = tonumber(source)
	if not player or player <= 0 or not isInteger(sequence) then return end
	if not enabled() or cooled('replay', player) then return end
	for other in pairs(looks) do deliver(player, other) end
	TriggerClientEvent(REPLAYED, player, sequence)
end)

--- @author DemiAutomatic
--- @event opx77_appearance:absent
--- @description Withdraws a reloading player's body from every observer.
RegisterNetEvent(ABSENT, function()
	local player = tonumber(source)
	if not player or player <= 0 or not enabled() or absent[player] then return end
	absent[player] = true
	if looks[player] ~= nil then broadcast(player) end
end)

--- @author DemiAutomatic
--- @event onPlayerBucketChange
--- @description Hands a player and its new bucket's players each other's looks.
--- @param player {integer}
--- @param bucket {integer}
--- @param previous {integer}
AddEventHandler('onPlayerBucketChange', function(player, bucket, previous)
	player, bucket, previous = tonumber(player), tonumber(bucket), tonumber(previous)
	if not player or player <= 0 or not bucket or bucket == previous or not enabled() then return end
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

--- @author DemiAutomatic
--- @event onPlayerDisconnected
--- @description Forgets a departing player.
--- @param playerId {integer|string}
AddEventHandler('onPlayerDisconnected', function(playerId)
	local player = tonumber(playerId)
	if player then forget(player) end
end)

--- @author DemiAutomatic
--- @event onResourceStart
--- @description Asks every client to publish and ask again after a start.
--- @param name {string}
AddEventHandler('onResourceStart', function(name)
	if name ~= GetCurrentResourceName() then return end
	if Config.PRESENT_BODIES == false then
		Open77.log.info('PRESENT_BODIES is false: another resource must hand every look out')
		return
	end
	TriggerClientEvent(RESEND, -1)
end)
