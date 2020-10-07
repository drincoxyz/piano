include "shared.lua"

ENT.HeldNotes   = {}
ENT.NoteQueue   = {}
ENT.Sustained   = false
ENT.ResetAng    = Angle()
ENT.CurrentTick = 0

if file.Find("lua/bin/gmcl_midi_*", "GAME")[1] then require "midi" end

local midiport = CreateClientConVar("piano_midi_port", 0, true, false, "This MIDI port will be used to control pianos."):GetInt()
local clnotes  = CreateClientConVar("piano_clientside_notes", 1, true, true, "When enabled, piano notes will be updated immediately.", 0, 1):GetBool()
cvars.RemoveChangeCallback("piano_clientside_notes", "def")
cvars.AddChangeCallback("piano_clientside_notes", function(cvar, old, new) clnotes = tobool(new) end, "def")
cvars.RemoveChangeCallback("piano_midi_port", "def")
cvars.AddChangeCallback("piano_midi_port", function(cvar, old, new) midiport = math.floor(tonumber(new) || -1) end, "def")
concommand.Add("piano_print_midi_ports", function(pl, cmd, args, argstr) if !midi then return end PrintTable(midi.GetPorts()) end)

net.Receive("piano_leave", function(len)
	local piano = net.ReadEntity()
	if !IsValid(piano) then return end
	local pl = net.ReadEntity()
	if !IsValid(pl) then return end

	piano:ReleaseAllNotes()
	piano:StopSustain()

	if pl == LocalPlayer() then
		if IsValid(piano.PianoVGUI) then
			piano.PianoVGUI:Remove()
			piano.PianoVGUI = nil
		end
	end
end)

net.Receive("piano_enter", function(len)
	local piano = net.ReadEntity()
	if !IsValid(piano) then return end
	local pl = net.ReadEntity()
	if !IsValid(pl) then return end

	piano:ReleaseAllNotes()
	piano:StopSustain()

	if pl == LocalPlayer() then
		if midi && midi.GetPorts()[midiport] then midi.Open(midiport) end
		piano.PianoVGUI = vgui.Create(piano.PianoPanel)
	end
end)

net.Receive("piano_queue", function(len)
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

	piano.Sustained = sus

	for i, note in pairs(queue) do
		timer.Simple(note.time, function()
			if note.vel > 0 then
				piano:HoldNote(note.note, note.oct, note.vel, true)
			else
				piano:ReleaseNote(note.note, note.oct, true)
			end
		end)
	end
end)

vgui.Register("DPiano", {
	Init = function(self)
		self:SetSize(ScrW(), ScrW() / 8)
		self:CenterHorizontal()
		self:AlignBottom()
	end,
}, "DFrame")

function ENT:Initialize()
	self:SharedInitialize()

	hook.Add("MIDI", self, function(self, time, cmd, ...)
		if LocalPlayer() != self:GetPlayer() then return end
		return self:MIDI(time, cmd, ...)
	end)

	hook.Add("Tick", self, function(self)
		return self:Tick()
	end)
end

function ENT:Tick()
	if self.CurrentTick < self.TickRate then self.CurrentTick = self.CurrentTick + 1 return end
	self.CurrentTick = 0

	local pl = self:GetPlayer()
	if !IsValid(pl) || #self.NoteQueue < 1 then return end

	local start
	for i, queue in pairs(self.NoteQueue) do
		if !start then start = queue.time queue.time = 0 continue end
		queue.time = queue.time - start
	end

	local data = {self:EntIndex(), self.Sustained, self.NoteQueue}
	local comp = util.Compress(util.TableToJSON(data))
	local len  = comp:len()

	net.Start "piano_queue" net.WriteData(comp, len) net.SendToServer()

	table.Empty(self.NoteQueue)
end

function ENT:MIDI(time, cmd, ...)
	if !cmd then return end

	local cmdname = midi.GetCommandName(cmd)

	if cmdname == "NOTE_ON" || cmdname == "NOTE_OFF" then
		local rawnote = select(1, ...)
		local vel     = select(2, ...)
		local oct     = math.floor(rawnote / 12) - 2
		local start   = ((rawnote % 12) * 2) + 1
		local note    = self.NoteStr:sub(start, start + 1):Trim()

		if cmdname == "NOTE_ON" && vel > 0 then
			self:HoldNote(note, oct, vel)
		else
			self:ReleaseNote(note, oct)
		end
	elseif cmdname == "CONTINUOUS_CONTROLLER" then
		local cont = select(1, ...)
		
		-- Hold pedal (Sustain) on/off
		if cont == 64 then
			if select(2, ...) > 63 then
				self:StartSustain()
			else
				self:StopSustain()
			end
		end
	end
end

function ENT:StartSustain()
	if self.Sustained then return end
	self.Sustained = true
	self:OnSustainStarted()
end

function ENT:StopSustain()
	if !self.Sustained then return end
	self.Sustained = false
	self:OnSustainStopped()
end

function ENT:OnSustainStarted()
	if self.SustainBoneName && self.SustainBoneAng then
		local bone   = self:LookupBone(self.SustainBoneName)
		self:ManipulateBoneAngles(bone, self.SustainBoneAng)
		self:EmitSound(self.SoundPath.."/pedal."..self.SoundExt)
	end
end

function ENT:OnSustainStopped()
	if self.SustainBoneName && self.SustainBoneAng then
		local bone   = self:LookupBone(self.SustainBoneName)
		self:ManipulateBoneAngles(bone, self.ResetAng)
	end
end

function ENT:QueueNote(note, oct, vel)
	table.insert(self.NoteQueue, {
		time = SysTime(),
		note = note,
		oct  = oct,
		vel  = vel || 0
	})
end

function ENT:TranslateNote(note, oct, sv)
	local noteid  = note..oct
	local notesnd = self.SoundPath.."/"..noteid.."."..self.SoundExt
	return noteid, notesnd
end

function ENT:HoldNote(note, oct, vel, sv)
	local pl = self:GetPlayer()
	if !IsValid(pl) then return end

	if !sv && LocalPlayer() == pl then
		self:QueueNote(note, oct, vel)
		if !clnotes then return end
	end

	local noteid, notesnd = self:TranslateNote(note, oct)
	local heldnote        = self.HeldNotes[noteid]
	if heldnote && IsValid(heldnote.station) then return end

	sound.PlayFile("sound/"..notesnd, "3d noplay", function(station, errcode, errstr)
		if !IsValid(self) || !IsValid(station) then return end

		local vol = math.EaseInOut(math.min(100, vel / 100), 1, 0)
		local pos = self:GetPos()

		station:SetPos(pos)
		station:SetVolume(vol)
		station:Play()
		self.HeldNotes[noteid] = {
			station = station,
			note    = note,
			id      = noteid,
			snd     = notesnd,
			sus     = self.Sustained,
			oct     = oct,
			vel     = vel
		}
	end)

	self:OnNoteHeld(note, oct, vel)
end

function ENT:ReleaseNote(note, oct, sv)
	if !sv && LocalPlayer() == self:GetPlayer() then
		self:QueueNote(note, oct)
	end

	if self.Sustain then return end

	local noteid, notesnd = self:TranslateNote(note, oct)
	local heldnote        = self.HeldNotes[noteid]
	if !heldnote || !IsValid(heldnote.station) then return end

	local startvol = heldnote.station:GetVolume()

	hook.Add("Think", heldnote.station, function(station)
		if !IsValid(self) then return station:Stop() end
		local vol = station:GetVolume()
		if vol <= 0 then return station:Stop() end
		if heldnote.sus && !self.Sustained then heldnote.sus = false end
		if heldnote.sus then return end

		station:SetVolume(math.Approach(vol, 0, RealFrameTime() * (startvol * 3)))
	end)

	self.HeldNotes[noteid] = nil
	self:OnNoteReleased(note, oct)
end

function ENT:ReleaseAllNotes()
	for noteid, heldnote in pairs(self.HeldNotes) do
		self:ReleaseNote(heldnote.note, heldnote.oct)
	end
end

function ENT:OnNoteHeld(note, oct, vel)
	if self.KeyBoneAng then
		local bonename = self:TranslateKeyBoneName(note, oct)
		local bone     = self:LookupBone(bonename)
		self:ManipulateBoneAngles(bone, self.KeyBoneAng --[[* (vel / 100)]])
	end
end

function ENT:OnNoteReleased(note, oct)
	if self.KeyBoneAng then
		local bonename = self:TranslateKeyBoneName(note, oct)
		local bone     = self:LookupBone(bonename)
		self:ManipulateBoneAngles(bone, self.ResetAng)
	end
end