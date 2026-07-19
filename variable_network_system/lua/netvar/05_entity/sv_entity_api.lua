local meta = FindMetaTable("Entity")

function meta:_ClearVarNetSysData()
	VAR_NET_SYS:SendNetworkVariableClearData(self)
end
