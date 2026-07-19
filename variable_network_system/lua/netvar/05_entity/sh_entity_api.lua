local meta = FindMetaTable("Entity")

function meta:PrivateNetworkVariable(varType, varName, defaultValue, processValueFunc, shareWithFunc)
	return VAR_NET_SYS:AddNetworkVariableDataToEntity(self, varType, varName, defaultValue, processValueFunc, shareWithFunc)
end

local function ShareWithEveryone(ply, ent, owner)
	return true
end

function meta:PublicNetworkVariable(varType, varName, defaultValue, processValueFunc)
	return self:PrivateNetworkVariable(varType, varName, defaultValue, processValueFunc, ShareWithEveryone)
end

function meta:ClearVarNetSysData()
	local hadData = VAR_NET_SYS:ClearEntityNetworkVariableData(self)
	if not hadData then return end

	self:_ClearVarNetSysData()

	VAR_NET_SYS:Log(LOG_DEBUG, "Cleared VarNetSys Data for %s", self)
end
