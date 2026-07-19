local FUNCS_TO_ATTEMPT = {}
local FUNCS_TO_ATTEMPT_MAP = {}

function VAR_NET_SYS:AttemptUntilDone(attemptionName, canExecute, funcToExecute)
	local olderAttemption = FUNCS_TO_ATTEMPT_MAP[attemptionName]
	if olderAttemption then
		VAR_NET_SYS:StopAttempting(attemptionName)
		VAR_NET_SYS:Log(LOG_WARNING, "Replaced older attemption %s with a newer one of same name", attemptionName)
	end

	local attemptionIndex = table.insert(FUNCS_TO_ATTEMPT, { Name = attemptionName, CanExecute = canExecute, Execution = funcToExecute })
	FUNCS_TO_ATTEMPT_MAP[attemptionName] = attemptionIndex

	return attemptionIndex
end

function VAR_NET_SYS:StopAttempting(unwantedAttemptionName)
	local unwantedAttemptionIndex = FUNCS_TO_ATTEMPT_MAP[unwantedAttemptionName]
	if not unwantedAttemptionIndex or not table.remove(FUNCS_TO_ATTEMPT, unwantedAttemptionIndex) then return false end

	FUNCS_TO_ATTEMPT_MAP[unwantedAttemptionName] = nil

	for attemptionName, attemptionIndex in pairs(FUNCS_TO_ATTEMPT_MAP) do
		if attemptionIndex < unwantedAttemptionIndex then continue end
		FUNCS_TO_ATTEMPT_MAP[attemptionName] = attemptionIndex - 1
	end

	return true
end

function VAR_NET_SYS:GetAttemptionList()
	return FUNCS_TO_ATTEMPT
end

local function DoAttempts()
	local attemptionList = VAR_NET_SYS:GetAttemptionList()

	VAR_NET_SYS:SafeSequentialLoop(attemptionList, function(iteration)
		local entry = attemptionList[iteration]

		if not entry.CanExecute() then return end

		entry.Execution()
		return false
	end)
end

hook.Add("Think", "VAR_NET_SYS_Think_DoAttempts", function()
	DoAttempts()
end)
