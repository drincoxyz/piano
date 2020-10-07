ENT.Type            = "anim"
ENT.SoundPath       = "piano"
ENT.SoundExt        = "ogg"
ENT.BaseModel       = "models/error.mdl"
ENT.SeatModel       = "models/error.mdl"
ENT.PianoPanel      = "DPiano"
ENT.BasePos         = Vector()
ENT.BaseAng         = Angle()
ENT.Animated        = false
ENT.NoteStr         = "c c#d d#e f f#g g#a a#b "
ENT.TickRate        = 3
ENT.KeyBoneAng      = Angle()
ENT.SustainBoneName = nil
ENT.SustainBoneAng  = Angle()

function ENT:SetupDataTables()
	self:NetworkVar("Entity", 0, "Seat")
end

function ENT:SharedInitialize()
	self:SetModel(self.BaseModel)

	for i, snd in pairs(file.Find("sound/"..self.SoundPath.."/*."..self.SoundExt, "GAME")) do
		util.PrecacheSound(self.SoundPath.."/"..snd)
	end
end

function ENT:GetPlayer()
	local seat = self:GetSeat()
	return IsValid(seat) && seat:GetDriver() || NULL
end

function ENT:TranslateKeyBoneName(note, oct)
	return note..oct
end