-- A better way of sending strings, less bandwidth on longer strings
net.WriteCompressedString = function(str)
	if str == nil then str = "" end
	if not isstring(str) then str = tostring(str) end

	str = util.Compress(str)
	local bytes = #str

	net.WriteUInt(bytes, BYTES_TO_READ_STRING)
	net.WriteData(str, bytes)
end

net.ReadCompressedString = function()
	local bytes = net.ReadUInt(BYTES_TO_READ_STRING)
	local data = net.ReadData(bytes)

	return util.Decompress(data) or ""
end

-- A better way of sending tables, less bandwidth on longer tables. Can be slow.
net.WriteCompressedTable = function(tbl)
	util.EncodeTableUserdataForJSON(tbl)

	local json = util.TableToJSON(tbl)
	net.WriteCompressedString(json)

	util.DecodeTableUserdataFromJSON(tbl)
end

net.ReadCompressedTable = function(shouldExpandUserData)
	local json = net.ReadCompressedString()
	local tbl = util.JSONToTable(json)
	if not tbl then return {} end

	util.DecodeTableUserdataFromJSON(tbl, {}, shouldExpandUserData)
	return tbl
end

-- 32 bit floats instead of the engine's 16 bit vector compression
net.WriteVectorUncompressed = function(vector)
	VAR_NET_SYS:Assert(isvector(vector), "vector must be a vector!")

	net.WriteFloat(vector.x)
	net.WriteFloat(vector.y)
	net.WriteFloat(vector.z)
end

net.ReadVectorUncompressed = function()
	return Vector(net.ReadFloat(), net.ReadFloat(), net.ReadFloat())
end
