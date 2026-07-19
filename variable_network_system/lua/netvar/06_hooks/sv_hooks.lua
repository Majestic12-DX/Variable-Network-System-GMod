local PLAYERS_READY = {}

net.Receive("netvar_ready", function(len, ply)
	if not VAR_NET_SYS:IsValidPlayer(ply) then return end
	if PLAYERS_READY[ply] then return end

	PLAYERS_READY[ply] = true
	VAR_NET_SYS:SendNetworkVariablesFullUpdate(ply)
end)

hook.Add("PlayerDisconnected", "VAR_NET_SYS_PlayerDisconnected_ClearReady", function(ply)
	PLAYERS_READY[ply] = nil
end)
