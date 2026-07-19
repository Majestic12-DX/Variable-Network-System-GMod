VAR_NET_SYS = VAR_NET_SYS or {}

if VAR_NET_SYS.EnableLogging == nil then VAR_NET_SYS.EnableLogging = true end
if VAR_NET_SYS.DebugEnabled == nil then VAR_NET_SYS.DebugEnabled = false end

CREATIONID_BYTE_SIZE = 24
MAX_NET_SIZE = 65532

VAR_NET_SYS_MAXVARS = 127

VAR_NET_SYS_NUMBER = 0
VAR_NET_SYS_BOOL   = 1
VAR_NET_SYS_STRING = 2
VAR_NET_SYS_TABLE  = 3
VAR_NET_SYS_ENTITY = 4
VAR_NET_SYS_VECTOR = 5
VAR_NET_SYS_ANGLE  = 6
VAR_NET_SYS_COLOR  = 7

VAR_NET_SYS_VARIABLE_TYPE_MAP = {
	["number"]  = VAR_NET_SYS_NUMBER,
	["boolean"] = VAR_NET_SYS_BOOL,
	["string"]  = VAR_NET_SYS_STRING,
	["table"]   = VAR_NET_SYS_TABLE,
	["entity"]  = VAR_NET_SYS_ENTITY,
	["vector"]  = VAR_NET_SYS_VECTOR,
	["angle"]   = VAR_NET_SYS_ANGLE,
	["color"]   = VAR_NET_SYS_COLOR,
}

LOG_INFO    = 0
LOG_WARNING = 1
LOG_ERROR   = 2
LOG_DEBUG   = 3
LOG_DEV     = 4
LOG_PERF    = 5

VAR_NET_SYS.LogMessageColors = {
	[LOG_INFO]    = Color(0, 255, 255),
	[LOG_WARNING] = Color(255, 255, 0),
	[LOG_ERROR]   = Color(255, 0, 0),
	[LOG_DEBUG]   = Color(128, 255, 128),
	[LOG_DEV]     = Color(255, 0, 255),
	[LOG_PERF]    = Color(0, 128, 255)
}

local LOG_COLOR           = Color(255, 0, 0)
local LOG_COLOR_DEBUG     = Color(255, 255, 0)
local LOG_COLOR_DEVELOPER = Color(0, 255, 0)
local LOG_COLOR_PERFOMANCE = Color(0, 255, 0)
local LOG_COLOR_SERVER    = Color(0, 128, 255)
local LOG_COLOR_CLIENT    = Color(255, 128, 0)

local cvars_Number  = cvars.Number
local string_format = string.format
local MsgC          = MsgC
function VAR_NET_SYS:Log(logType, messageFormat, ...)
	if self.EnableLogging == false then return end

	logType = logType or LOG_INFO

	local isPerf  = logType == LOG_PERF
	local isDev   = logType == LOG_DEV
	local isDebug = logType == LOG_DEBUG
	if (isDebug or isDev) and not self.DebugEnabled then return end
	if isDev or isPerf then
		local devMode = cvars_Number("developer", 0)
		if devMode < (isDev and 2 or isPerf and 3) then return end
	end

	local message = string_format(messageFormat, ...) .. '\n'

	MsgC(LOG_COLOR, "[VARIABLE NETWORK SYSTEM",
		SERVER and LOG_COLOR_SERVER or LOG_COLOR_CLIENT,
		SERVER and " SERVER" or " CLIENT",
		isDebug and LOG_COLOR_DEBUG or isDev and LOG_COLOR_DEVELOPER or isPerf and LOG_COLOR_PERFOMANCE or LOG_COLOR,
		isDebug and " DEBUG" or isDev and " DEV" or isPerf and " PERFOMANCE" or "",
		LOG_COLOR, "] ",
		self.LogMessageColors[logType], message)
end

function VAR_NET_SYS:CalculateByteSize(integer)
	return math.ceil(math.log(integer + 1, 2))
end

function VAR_NET_SYS:GetBoolSafe(boolOrNil)
	return boolOrNil == true or false
end

function VAR_NET_SYS:IsDebug()
	return self:GetBoolSafe(self.DebugEnabled)
end

function VAR_NET_SYS:Assert(assertion, errorText, ...)
	if assertion then return end
	error("Assertion failed: " .. string.format(errorText, ...), 0)
end

function IsValidEntity(ent)
	if IsValid(ent) then return true end
	if not ent then return false end

	local isWorld = ent.IsWorld
	if not isWorld then return false end

	return isWorld(ent)
end

function VAR_NET_SYS:IsValidPlayer(ent)
	return IsValid(ent) and ent:IsPlayer()
end

function VAR_NET_SYS:SafeSequentialLoop(tableToLoop, loopBody, ...)
	local iteration = 0
	local tableLength = #tableToLoop

	while iteration ~= tableLength do
		iteration = iteration + 1

		local isIterationSuccessful = loopBody(iteration, tableToLoop, ...) ~= false

		if not isIterationSuccessful then
			table.remove(tableToLoop, iteration)

			iteration = iteration - 1
			tableLength = tableLength - 1
		end
	end
end

function VAR_NET_SYS:GetPlayerDataString(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return "" end

	return ply:Name() .. " (" .. ply:SteamID64() .. " " .. ply:SteamID() .. ")"
end

BYTES_TO_READ_STRING = VAR_NET_SYS:CalculateByteSize(MAX_NET_SIZE)
VAR_NET_SYS_VARIABLE_TYPE_MAP_BYTE_SIZE = VAR_NET_SYS:CalculateByteSize(table.Count(VAR_NET_SYS_VARIABLE_TYPE_MAP))
VAR_NET_SYS_MAXVARS_BYTE_SIZE = VAR_NET_SYS:CalculateByteSize(VAR_NET_SYS_MAXVARS)
