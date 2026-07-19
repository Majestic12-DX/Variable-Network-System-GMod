VAR_NET_SYS = VAR_NET_SYS or {}
VAR_NET_SYS.Version = "1.0.0"

local ENABLE_LOADER_LOG = true

local TAG_COLOR    = Color(0, 200, 255)
local REALM_COLOR  = SERVER and Color(0, 128, 255) or Color(255, 128, 0)

local LOG_COLOR = SERVER and Color(0, 128, 255) or Color(255, 128, 0)
local LOADER_COLOR = Color(255, 255, 0)

local function LoaderLog(message)
	if not ENABLE_LOADER_LOG then return end
	MsgC(LOADER_COLOR, "[VARIABLE NETWORK SYSTEM LOADER] ", LOG_COLOR, string.format("%s", message.."\n"))
end

local function LoadServerFile(filePath)
	if CLIENT then return end

	include(filePath)
	LoaderLog(string.format("Loaded server-side file: %s", filePath))
end

local function LoadSharedFile(filePath)
	AddCSLuaFile(filePath)
	include(filePath)

	LoaderLog(string.format("Loaded shared file: %s", filePath))
end

local function LoadClientFile(filePath)
	if SERVER then 
		AddCSLuaFile(filePath) 
		return 
	end

	include(filePath)
	LoaderLog(string.format("Loaded client-side file: %s", filePath))
end

local function LoadDirectory(directory)
	directory = directory .. "/"

	local tblFiles, tblDirectories = file.Find(directory .. "*", "LUA")

	for _, scriptFile in ipairs(tblFiles) do
		if not string.EndsWith(scriptFile, ".lua") then continue end
		local filePath = directory .. scriptFile

		-- If marked as server file
		if string.StartWith(scriptFile, "sv_") then
			LoadServerFile(filePath)
		-- If marked as shared file
		elseif string.StartWith(scriptFile, "sh_") then
			LoadSharedFile(filePath)
		-- If marked as client file
		elseif string.StartWith(scriptFile, "cl_") then
			LoadClientFile(filePath)
		-- If not marked
		else
			LoaderLog("Skipped file " .. filePath)
		end
	end

	for _, nestedDirectory in ipairs(tblDirectories) do
		LoadDirectory(directory .. nestedDirectory)
	end
end

LoadDirectory("netvar")
LoaderLog("Loaded Variable Network System V" .. VAR_NET_SYS.Version)
