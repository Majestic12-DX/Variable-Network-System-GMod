hook.Add("InitPostEntity", "VAR_NET_SYS_InitPostEntity_Ready", function()
	net.Start("netvar_ready")
	net.SendToServer()
end)
