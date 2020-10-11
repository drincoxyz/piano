include      "shared.lua"
AddCSLuaFile "shared.lua"
AddCSLuaFile "cl_init.lua"

util.AddNetworkString "piano_leave"
util.AddNetworkString "piano_enter"
util.AddNetworkString "piano_queue"

-- incoming note queue
net.Receive("piano_queue", function(len, pl)
	-- msg size limit
	-- TODO: find a better, (preferrably) dynamic limit
	if len >= 3096 then return end
	-- net data must be valid
	local comp = net.ReadData(len)
	if !comp || !isstring(comp) then return end
	local data = util.JSONToTable(util.Decompress(comp))
	if !data || !istable(data) then return end
	-- piano and player (who also sent the msg) must be valid
	local piano = Entity(data[1])
	if !IsValid(piano) || !piano:IsScripted() || !scripted_ents.IsBasedOn(piano:GetClass(), "base_piano") then return end
	local _pl = piano:GetPlayer()
	if pl != pl then return end
	-- sustain state must be valid
	local sus = data[2]
	if !isbool(sus) then return end
	-- note queue must be valid
	local queue = data[3]
	if !queue || !istable(queue) then return end

	-- recipients of the upcoming relay msg
	local filter = RecipientFilter()
	filter:AddPAS(piano:GetPos())
	-- pianist may opt-in as well if they prefer
	if tobool(pl:GetInfo "piano_clientside_notes") then filter:RemovePlayer(pl) end
	-- relay not necessary if nobody will hear
	if filter:GetCount() < 1 then return end

	-- send relay msg to approrpiate recipients
	net.Start "piano_queue" net.WriteData(comp, len) net.Send(filter)
end)

function ENT:Initialize()
	self:SharedInitialize()

	-- physics must be valid
	if !self:PhysicsInit(SOLID_VPHYSICS) then return self:Remove() end
	-- motion disable by default
	local phys = self:GetPhysicsObject()
	phys:EnableMotion(false)

	-- seat must be valid
	local seat = ents.Create "prop_vehicle_prisoner_pod"
	if !IsValid(seat) then return self:Remove() end
	-- seat phys must also be valid
	seat:SetModel(self.SeatModel)
	if !seat:PhysicsInit(SOLID_VPHYSICS) then return self:Remove() end
	-- setup seat
	self:SetSeat(seat)
	seat:SetOwner(self)
	seat:SetPos(self:LocalToWorld(self.SeatPos))
	seat:SetAngles(self:LocalToWorldAngles(self.SeatAng))
	seat:SetVehicleEntryAnim(false)
	seat:SetThirdPersonMode(false)
	seat:Spawn()
	seat:DropToFloor()
	-- seat motion also disabled by default
	local phys = seat:GetPhysicsObject()
	phys:EnableMotion(false)

	hook.Add("PlayerEnteredVehicle", seat, function(seat, pl, veh, role)
		if veh != seat then return end
		return self:PlayerEntered(pl, veh)
	end)
	hook.Add("PlayerLeaveVehicle", seat, function(seat, pl, veh)
		if veh != seat then return end
		return self:PlayerLeave(pl, veh)
	end)
end

function ENT:OnRemove()
	-- destroy seat if applicable
	local seat = self:GetSeat()
	if IsValid(seat) then
		seat:Remove()
	end
end

function ENT:PlayerEntered(pl, seat)
	-- broadcast enter event
	net.Start "piano_enter"
		net.WriteEntity(self)
		net.WriteEntity(pl)
	net.Broadcast()
end

function ENT:PlayerLeave(pl, seat)
	-- transform player to exit point if applicable
	local exit = seat:GetAttachment(seat:LookupAttachment "exit1")
	if exit then
		exit.Ang.z = 0
		pl:SetPos(exit.Pos)
		pl:SetEyeAngles(exit.Ang)
	end

	-- broadcast leave event
	net.Start "piano_leave"
		net.WriteEntity(self)
		net.WriteEntity(pl)
	net.Broadcast()
end
