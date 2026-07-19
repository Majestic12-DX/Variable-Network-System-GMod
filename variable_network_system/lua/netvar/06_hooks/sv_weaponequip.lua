-- C++ engine weapons set their owner on pickup without a Lua SetOwner/OwnerChanged
-- call, so the owner-change wrap misses them. Re-network their vars on WeaponEquip.
-- Lua weapons already go through OwnerChanged, so we skip them here (no double send).
hook.Add("WeaponEquip", "VAR_NET_SYS_WeaponEquip_ReNetworkEngineWeapon", function(weapon)
	if not IsValid(weapon) or not VAR_NET_SYS_ENGINE_WEAPONS[weapon:GetClass()] then return end
	if VAR_NET_SYS:GetEntityNetworkVariableDataAmount(weapon) == 0 then return end

	-- defer a tick so the new owner is assigned before we re-send
	timer.Simple(0, function()
		if IsValid(weapon) then VAR_NET_SYS:FullNetworkEntityNetworkData(weapon) end
	end)
end)
