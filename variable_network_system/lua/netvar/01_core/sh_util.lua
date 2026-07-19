util.EncodeTableUserdataForJSON = function(elementInTable, visited)
	visited = visited or {}

	if istable(elementInTable) then
		if visited[elementInTable] then return elementInTable end
		visited[elementInTable] = true

		local snapshottedKeys = table.GetKeys(elementInTable)
		for _, key in ipairs(snapshottedKeys) do
			local value = elementInTable[key]

			local newKey = util.EncodeTableUserdataForJSON(key, visited)
			local newValue = util.EncodeTableUserdataForJSON(value, visited)

			if newKey ~= key then
				elementInTable[key] = nil
			end

			elementInTable[newKey] = newValue
		end

		return elementInTable
	elseif IsEntity(elementInTable) then
		if IsValid(elementInTable) or elementInTable:IsWorld() then
			return string.format("[ %s ent %s creation ]", elementInTable:EntIndex(), elementInTable:GetCreationID())
		else
			return "[ 0 ent -1 creation ]"
		end
	end

	return elementInTable
end

local ENTITY_PATTERN = "^%[%s*(%-?%d+)%s+ent%s+(%-?%d+)%s+creation%s*%]$"
util.DecodeTableUserdataFromJSON = function(elementInTable, visited, shouldExpandUserData)
	visited = visited or {}

	local elementType = type(elementInTable)

	if elementType == "string" then
		local entIndex, entCreationId = elementInTable:match(ENTITY_PATTERN)
		if entIndex and entCreationId then
			entIndex = tonumber(entIndex)
			entCreationId = tonumber(entCreationId)

			local ent = Entity(entIndex)
			if IsValid(ent) or ent:IsWorld() then
				if ent:GetCreationID() ~= entCreationId then
					ent = NULL
				end
			end

			return shouldExpandUserData and { Entity = ent, EntIndex = entIndex, EntCreationId = entCreationId } or ent
		end

		return elementInTable
	elseif elementType == "table" then
		if visited[elementInTable] then return elementInTable end
		visited[elementInTable] = true

		local snapshottedKeys = table.GetKeys(elementInTable)
		for _, key in ipairs(snapshottedKeys) do
			local value = elementInTable[key]

			local newKey = util.DecodeTableUserdataFromJSON(key, visited, shouldExpandUserData)
			local newValue = util.DecodeTableUserdataFromJSON(value, visited, shouldExpandUserData)

			if newKey ~= key then
				elementInTable[key] = nil
			end

			elementInTable[newKey] = newValue
		end

		return elementInTable
	end

	return elementInTable
end
