include "shared.lua"

-- held notes
ENT.HeldNotes = {}
-- queued network notes
ENT.NoteQueue = {}
-- generic zero angle
ENT.ResetAng = Angle()
-- sustain state
ENT.Sustained = false
-- client's tick
ENT.CurrentTick = 0

-- optional midi module
if file.Find("lua/bin/gmcl_midi_*", "GAME")[1] then require "midi" end

-- selected midi port
local midiport = CreateClientConVar("piano_midi_port", 0, true, false, "This MIDI port will be used to control pianos."):GetInt()
cvars.RemoveChangeCallback("piano_midi_port", "def")
cvars.AddChangeCallback("piano_midi_port", function(cvar, old, new) midiport = math.floor(tonumber(new) || -1) end, "def")
-- forced note networking
local clnotes = CreateClientConVar("piano_clientside_notes", 1, true, true, "When enabled, piano notes will be updated immediately.", 0, 1):GetBool()
cvars.RemoveChangeCallback("piano_clientside_notes", "def")
cvars.AddChangeCallback("piano_clientside_notes", function(cvar, old, new) clnotes = tobool(new) end, "def")
-- shows available midi ports
concommand.Add("piano_print_midi_ports", function(pl, cmd, args, argstr) if !midi then return end PrintTable(midi.GetPorts()) end)

-- leave event
net.Receive("piano_leave", function(len)
	-- piano and player required
	local piano = net.ReadEntity()
	if !IsValid(piano) then return end
	local pl = net.ReadEntity()
	if !IsValid(pl) then return end

	-- reset piano
	piano:ReleaseAllNotes()
	piano:StopSustain()

	-- cleanup for local pianist
	if pl == LocalPlayer() then
		if IsValid(piano.PianoVGUI) then
			piano.PianoVGUI:Remove()
			piano.PianoVGUI = nil
		end
	end
end)
-- enter event
net.Receive("piano_enter", function(len)
	-- piano and player required
	local piano = net.ReadEntity()
	if !IsValid(piano) then return end
	local pl = piano:GetPlayer()
	if !IsValid(pl) then return end

	-- reset piano
	piano:ReleaseAllNotes()
	piano:StopSustain()

	-- setup for local pianist
	if pl == LocalPlayer() then
		if midi && midi.GetPorts()[midiport] then midi.Open(midiport) end
		piano.PianoVGUI = vgui.Create(piano.PianoPanel)
	end
end)
-- receive note queue
net.Receive("piano_queue", function(len)
	-- net data must be valid
	local comp = net.ReadData(len)
	if !comp || !isstring(comp) then return end
	local data = util.JSONToTable(util.Decompress(comp))
	if !data || !istable(data) then return end

	-- piano must be valid
	local piano = Entity(data[1])
	if !IsValid(piano) || !piano:IsScripted() || !scripted_ents.IsBasedOn(piano:GetClass(), "base_piano") then return end

	-- sustain state must be valid
	local sus = data[2]
	if !isbool(sus) then return end

	-- queue must be valid
	local queue = data[3]
	if !queue || !istable(queue) then return end

	-- update sustain state
	piano.Sustained = sus

	-- hold/release notes in queue at given times
	for i, note in pairs(queue) do
		timer.Simple(note.time, function()
			-- piano must still be valid
			if !IsValid(piano) then return end

			if note.vel > 0 then
				piano:HoldNote(note.note, note.oct, note.vel, true)
			else
				piano:ReleaseNote(note.note, note.oct, true)
			end
		end)
	end
end)

-- default piano GUI
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
	-- obey tick rate
	if self.CurrentTick < self.TickRate then self.CurrentTick = self.CurrentTick + 1 return end
	self.CurrentTick = 0

	-- player must be valid
	local pl = self:GetPlayer()
	if !IsValid(pl) then return end
	
	-- note net queue must be populated
	if #self.NoteQueue < 1 then return end

	-- make note timestamps local to first note
	local start
	for i, note in pairs(self.NoteQueue) do
		if !start then start = note.time note.time = 0 continue end
		note.time = note.time - start
	end

	-- construct net data w/ LZMA compression
	local data = {self:EntIndex(), self.Sustained, self.NoteQueue}
	local comp = util.Compress(util.TableToJSON(data))
	local len  = comp:len()

	-- send net data to server for processing
	net.Start "piano_queue" net.WriteData(comp, len) net.SendToServer()

	-- empty note queue
	table.Empty(self.NoteQueue)
end

function ENT:MIDI(time, cmd, ...)
	-- this is possible for some reason
	if !cmd then return end

	-- process command based on its name
	local cmdname = midi.GetCommandName(cmd)
	-- note was pressed or released
	if cmdname == "NOTE_ON" || cmdname == "NOTE_OFF" then
		-- conversions from MIDI message to note, octave, vel etc.
		local rawnote = select(1, ...)
		local vel     = select(2, ...)
		local oct     = math.floor(rawnote / 12) - 2 -- TODO: this is probably supposed to be '- 1' instead
		local start   = ((rawnote % 12) * 2) + 1
		local note    = self.NoteStr:sub(start, start + 1):Trim()

		-- hold/release processed note
		if cmdname == "NOTE_ON" && vel > 0 then
			self:HoldNote(note, oct, vel)
		else
			self:ReleaseNote(note, oct)
		end
	-- continous controller message
	elseif cmdname == "CONTINUOUS_CONTROLLER" then	
		-- start/stop sustain state
		-- 64 = Hold pedal (Sustain) on/off
		local cont = select(1, ...)
		if cont == 64 then
			if select(2, ...) > 63 then
				self:StartSustain()
			else
				self:StopSustain()
			end
		end
	end
end

-- starts sustaining notes
function ENT:StartSustain()
	if self.Sustained then return end
	-- update sustain state
	self.Sustained = true
	-- sutsain callback
	self:OnSustainStarted()
end

-- stops sustaining notes
function ENT:StopSustain()
	if !self.Sustained then return end
	-- update sustain state
	self.Sustained = false
	-- sutsain callback
	self:OnSustainStopped()
end

-- sustain callbacks
function ENT:OnSustainStarted()
	-- depress sustain pedal bone
	if self.SustainBoneName && self.SustainBoneAng then
		local bone = self:LookupBone(self.SustainBoneName)
		if bone then
		self:ManipulateBoneAngles(bone, self.SustainBoneAng)
		self:EmitSound(self.SoundPath.."/pedal."..self.SoundExt)
		end
	end
end
function ENT:OnSustainStopped()
	-- raise sustain pedal bone
	if self.SustainBoneName && self.SustainBoneAng then
		local bone = self:LookupBone(self.SustainBoneName)
		if bone then self:ManipulateBoneAngles(bone, self.ResetAng) end
	end
end

-- queues note for upcoming network
function ENT:QueueNote(note, oct, vel)
	table.insert(self.NoteQueue, {
		time = SysTime(),
		note = note,
		oct  = oct,
		vel  = vel || 0
	})
end

-- holds a note
function ENT:HoldNote(note, oct, vel, sv)
	-- player required
	local pl = self:GetPlayer()
	if !IsValid(pl) then return end

	-- queue note for network when local playing
	if !sv && LocalPlayer() == pl then
		self:QueueNote(note, oct, vel)
		if !clnotes then return end
	end

	-- no existing station required
	local noteid   = self:TranslateNoteID(note, oct)
	local heldnote = self.HeldNotes[noteid]
	if heldnote && IsValid(heldnote.station) then return end

	-- play note sound attempt
	local notesnd = self:TranslateNoteSoundFile(note, oct)
	sound.PlayFile("sound/"..notesnd, "3d noplay", function(station, errcode, errstr)
		-- valid piano and station required
		if !IsValid(self) || !IsValid(station) then return end

		-- setup & play station
		local vol = math.EaseInOut(math.min(1, vel / 100), 1, 0)
		local pos = self:GetPos()
		station:SetPos(pos)
		station:SetVolume(vol)
		station:Play()

		-- register held note
		self.HeldNotes[noteid] = {
			station = station,
			note    = note,
			id      = noteid,
			snd     = notesnd,
			sus     = self.Sustained,
			oct     = oct,
			vel     = vel
		}

		-- note callback
		self:OnNoteHeld(note, oct, vel)
	end)
end

-- releases a note
function ENT:ReleaseNote(note, oct, sv)
	-- queue note for network when locally playing
	if !sv && LocalPlayer() == self:GetPlayer() then
		self:QueueNote(note, oct)
	end

	-- unstatined required
	if self.Sustain then return end

	-- station required
	local noteid   = self:TranslateNoteID(note, oct)
	local heldnote = self.HeldNotes[noteid]
	if !heldnote || !IsValid(heldnote.station) then return end

	local startvol = heldnote.station:GetVolume()
	hook.Add("Think", heldnote.station, function(station)
		-- destroy w/ invalid piano
		if !IsValid(self) then return station:Stop() end

		-- destroy w/ inaudible volume
		local vol = station:GetVolume()
		if vol <= 0 then return station:Stop() end

		-- notes may only sustain once ever
		if heldnote.sus && !self.Sustained then heldnote.sus = false end
		-- sustain prevents volume change
		if heldnote.sus then return end

		-- fade out volume
		station:SetVolume(math.Approach(vol, 0, RealFrameTime() * (startvol * 3)))
	end)

	-- clear held note from mem
	self.HeldNotes[noteid] = nil
	-- note callback
	self:OnNoteReleased(note, oct)
end

-- releases ALL notes
function ENT:ReleaseAllNotes()
	for noteid, heldnote in pairs(self.HeldNotes) do
		self:ReleaseNote(heldnote.note, heldnote.oct)
	end
end

-- note callbacks
function ENT:OnNoteHeld(note, oct, vel)
	-- depress note bone
	if self.NoteBoneAng then
		local bonename = self:TranslateNoteBoneName(note, oct)
		local bone     = self:LookupBone(bonename)
		if bone then self:ManipulateBoneAngles(bone, self.NoteBoneAng --[[* (vel / 100)]]) end
	end
end
function ENT:OnNoteReleased(note, oct)
	-- raise note bone
	if self.NoteBoneAng then
		local bonename = self:TranslateNoteBoneName(note, oct)
		local bone     = self:LookupBone(bonename)
		if bone then self:ManipulateBoneAngles(bone, self.ResetAng) end
	end
end
