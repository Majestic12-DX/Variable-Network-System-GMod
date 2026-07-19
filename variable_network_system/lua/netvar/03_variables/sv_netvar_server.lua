-- Handicap solution
local function GetValueType(value, technicalVarType)
	return technicalVarType == "Entity" and IsEntity(value) and "Entity" or type(value)
end

-- Should NOT be called manually. Called by AddNetworkVariableDataToEntity shared function
function VAR_NET_SYS:_AddNetworkVariableDataToEntity(ent, varType, varName, defaultValue, varId, varTypeId, technicalVarType, networkVarData)
	local getFunc = networkVarData.GetFunc
	local processValueFunc = networkVarData.ProcessValueFunc
	local shareWithFunc = networkVarData.ShareWithFunc

	local function setFunc(mySelf, newValue)
		-- Nothing changed
		local oldValue = getFunc(mySelf, varId)
		if newValue == oldValue then return false end

		-- Color is a table type, so the plain type check can't tell it apart from a plain table
		local newValueType = GetValueType(newValue, technicalVarType)
		if newValueType ~= technicalVarType or (varTypeId == VAR_NET_SYS_COLOR and not IsColor(newValue)) then
			local expectedType = varTypeId == VAR_NET_SYS_COLOR and "Color" or technicalVarType
			VAR_NET_SYS:Log(LOG_ERROR, "Network System Variable %s was tried to be set to %s, but type is %s (expected %s)", varName, newValue, newValueType, expectedType)
			return false
		end

		if processValueFunc then
			local processedValue = processValueFunc(newValue)

			local processedValueType = GetValueType(processedValue, technicalVarType)
			if processedValueType == technicalVarType then
				newValue = processedValue
			else
				VAR_NET_SYS:Log(LOG_ERROR, "processValueFunc for %s of entity %s did not return expected type (%s) with %s input (got %s, processed as %s)!",
					varName, mySelf, technicalVarType, processedValueType, newValue, processedValue)

				return false
			end
		end

		local onChangeFunc = mySelf["On" .. varName .. "Change"]
		if isfunction(onChangeFunc) then
			onChangeFunc(mySelf, oldValue, newValue)
		end

		networkVarData.Value = newValue
		return true
	end

	networkVarData.SetFunc = setFunc

	local function networkFunc(mySelf)
		VAR_NET_SYS:SendNetworkVariableUpdate(mySelf, varId)
	end

	networkVarData.NetworkFunc = networkFunc

	ent["Set" .. varName] = function(mySelf, newValue)
		local successful = setFunc(mySelf, newValue)
		if not successful then return false end

		networkFunc(mySelf)
		return true
	end

	ent["Network" .. varName] = networkFunc

	if ent._VarNetSysSetup then return end
	ent._VarNetSysSetup = true

	-- Prefer OwnerChanged if the entity already has it (SENTs), else wrap SetOwner.
	-- Both network AFTER the base runs, so the owner is up to date when we re-send.
	if ent.OwnerChanged then
		local ownerChangedBase = ent.OwnerChanged
		ent.OwnerChanged = function(mySelf)
			ownerChangedBase(mySelf)
			VAR_NET_SYS:FullNetworkEntityNetworkData(mySelf)
		end
	else
		local setOwnerBase = ent.SetOwner
		ent.SetOwner = function(mySelf, newOwner)
			setOwnerBase(mySelf, newOwner)
			VAR_NET_SYS:FullNetworkEntityNetworkData(mySelf)
		end
	end
end

function VAR_NET_SYS:FullNetworkEntityNetworkData(ent)
	local networkVarAmount = VAR_NET_SYS:GetEntityNetworkVariableDataAmount(ent)
	if networkVarAmount == 0 then return end

	for i = 0, networkVarAmount - 1 do
		VAR_NET_SYS:SendNetworkVariableUpdate(ent, i)
	end
end

function VAR_NET_SYS:SetGlobalNetworkedVariable(variableName, value)
	local world = game.GetWorld()
	local setter = world["Set" .. variableName]

	if not setter then
		VAR_NET_SYS:Log(LOG_WARNING, "Tried setting Global Networked Variable %s to %s, but it's missing! Preventing", variableName, value)
		return false
	end

	return setter(world, value)
end

function VAR_NET_SYS:NetworkGlobalNetworkedVariable(variableName)
	local world = game.GetWorld()
	local networker = world["Network" .. variableName]

	if not networker then
		VAR_NET_SYS:Log(LOG_WARNING, "Tried networking Global Networked Variable %s, but it's missing! Preventing", variableName)
		return false
	end

	networker(world)
	return true
end
