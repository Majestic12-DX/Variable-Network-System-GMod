local CREATIONID_TO_ENTITY = {}

function VAR_NET_SYS:AddEntityToCreationIDLookup(ent)
	local creationId = ent:GetCreationID()
	CREATIONID_TO_ENTITY[creationId] = ent
end

function VAR_NET_SYS:RemoveEntityFromCreationIDLookup(ent)
	local creationId = ent:GetCreationID()
	CREATIONID_TO_ENTITY[creationId] = nil
end

function VAR_NET_SYS:GetEntityByCreationID(creationId)
	return CREATIONID_TO_ENTITY[creationId]
end

hook.Add("OnEntityCreated", "VAR_NET_SYS_OnEntityCreated_CreationIDLookup", function(ent)
	VAR_NET_SYS:AddEntityToCreationIDLookup(ent)
end)

hook.Add("EntityRemoved", "VAR_NET_SYS_EntityRemoved_Destructor", function(ent, fullUpdate)
	if fullUpdate then return end

	if isfunction(ent.ClearVarNetSysData) then
		ent:ClearVarNetSysData()
	end

	VAR_NET_SYS:RemoveEntityFromCreationIDLookup(ent)
end)
