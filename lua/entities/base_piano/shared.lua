ENT.Type = "anim"

ENT.SoundPath = "piano"
ENT.SoundExt  = ".ogg"

-- models
ENT.BaseModel = "models/error.mdl"
ENT.SeatModel = "models/error.mdl"

ENT.PianoPanel = "DPiano"

-- base/seat transform
ENT.BasePos = Vector()
ENT.BaseAng = Angle()
ENT.SeatPos = Vector()
ENT.SeatAng = Angle()

-- note bone(s)
ENT.NoteBoneAng = Angle()

-- sustain pedal bone
ENT.SustainBoneName = nil
ENT.SustainBoneAng  = Angle()

-- note format
ENT.NoteStr = "c c#d d#e f f#g g#a a#b "

-- network tick rate
ENT.TickRate = 3

-- translates note to bone name
function ENT:TranslateNoteBoneName(note, oct)
	return note..oct
end
-- translates note to sound file
function ENT:TranslateNoteSoundFile(note, oct)
	return self.SoundPath.."/"..note..oct..self.SoundExt
end
-- translates note to id
function ENT:TranslateNoteID(note, oct, sv)
	return note..oct
end

function ENT:SetupDataTables()
	self:NetworkVar("Entity", 0, "Seat")
end

function ENT:SharedInitialize()
	self:SetModel(self.BaseModel)

	-- sound precache
	for i, snd in pairs(file.Find("sound/"..self.SoundPath.."/*", "GAME")) do
		util.PrecacheSound(self.SoundPath.."/"..snd)
	end
end

function ENT:GetPlayer()
	local seat = self:GetSeat()
	return IsValid(seat) && seat:GetDriver() || NULL
end
