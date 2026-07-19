local meta = FindMetaTable("Player")

local setTeamBase = meta.SetTeam
function meta:SetTeam(newTeamId)
	local currentTeamId = self:Team()
	setTeamBase(self, newTeamId)

	if currentTeamId ~= newTeamId then
		VAR_NET_SYS:SendNetworkVariablesFullUpdate(self)
	end
end

local setUserGroup = meta.SetUserGroup
function meta:SetUserGroup(newUserGroup)
	local currentUserGroup = self:GetUserGroup()
	setUserGroup(self, newUserGroup)

	if currentUserGroup ~= newUserGroup then
		VAR_NET_SYS:SendNetworkVariablesFullUpdate(self)
	end
end
