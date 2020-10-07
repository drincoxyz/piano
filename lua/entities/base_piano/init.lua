include      "shared.lua"
AddCSLuaFile "shared.lua"
AddCSLuaFile "cl_init.lua"

util.AddNetworkString "piano_leave"
util.AddNetworkString "piano_enter"
util.AddNetworkString "piano_queue"

net.Receive("piano_queue", function(len, pl)
	if len >= 3096 then return end
	local comp = net.ReadData(len)
	if !comp || !isstring(comp) then return end
	local data = util.JSONToTable(util.Decompress(comp))
	if !data || !istable(data) then return end
	local piano = Entity(data[1])
	if !IsValid(piano) || !piano:IsScripted() || !scripted_ents.IsBasedOn(piano:GetClass(), "base_piano") then return end
	local sus = data[2]
	if !isbool(sus) then return end
	local queue = data[3]
	if !queue || !istable(queue) then return end

	local filter = RecipientFilter()
	filter:AddPAS(piano:GetPos())
	if tobool(pl:GetInfo "piano_clientside_notes") then filter:RemovePlayer(pl) end
	if filter:GetCount() < 1 then return end

	net.Start "piano_queue" net.WriteData(comp, len) net.Send(filter)
end)

function ENT:Initialize()
	self:SharedInitialize()

	if !self:PhysicsInit(SOLID_VPHYSICS) then return self:Remove() end
	local phys = self:GetPhysicsObject()
	phys:EnableMotion(false)

	local seat = ents.Create "prop_vehicle_prisoner_pod"
	if !IsValid(seat) then return self:Remove() end
	seat:SetModel(self.SeatModel)
	if !seat:PhysicsInit(SOLID_VPHYSICS) then return self:Remove() end
	self:SetSeat(seat)
	seat:SetOwner(self)
	seat:SetPos(self:LocalToWorld(self.SeatPos))
	seat:SetAngles(self:LocalToWorldAngles(self.SeatAng))
	seat:SetVehicleEntryAnim(false)
	seat:SetThirdPersonMode(false)
	seat:Spawn()
	seat:DropToFloor()
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
	local seat = self:GetSeat()
	if IsValid(seat) then
		seat:Remove()
	end
end

function ENT:PlayerEntered(pl, seat)
	net.Start "piano_enter"
		net.WriteEntity(self)
		net.WriteEntity(pl)
	net.Broadcast()
end

function ENT:PlayerLeave(pl, seat)
	local exit = seat:GetAttachment(seat:LookupAttachment "exit1")
	if exit then
		exit.Ang.z = 0
		pl:SetPos(exit.Pos)
		pl:SetEyeAngles(exit.Ang)
	end

	net.Start "piano_leave"
		net.WriteEntity(self)
		net.WriteEntity(pl)
	net.Broadcast()
end