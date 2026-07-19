local meta = FindMetaTable("Player")

local setTeamBase = meta.SetTeam
function meta:SetTeam(newTeamId)
	local currentTeamId = self:Team()
	if currentTeamId ~= newTeamId then
		VAR_NET_SYS:SendNetworkVariablesFullUpdate(self)
	end

	setTeamBase(self, newTeamId)
end

local setUserGroup = meta.SetUserGroup
function meta:SetUserGroup(newUserGroup)
	local currentUserGroup = self:GetUserGroup()
	if currentUserGroup ~= newUserGroup then
		VAR_NET_SYS:SendNetworkVariablesFullUpdate(self)
	end

	setUserGroup(self, newUserGroup)
end
