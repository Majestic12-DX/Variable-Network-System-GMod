local function LogSendNetError(logType, identifier, message)
	VAR_NET_SYS:Log(logType, "%s Net Message Problem: %s", identifier, message)
end

function VAR_NET_SYS:AddNetworkSender(networkSenderName, networkSenderBody)
	if self[networkSenderName] then
		VAR_NET_SYS:Log(LOG_WARNING, "Element %s already exists in VAR_NET_SYS! Replacing with a network sender!", networkSenderName)
	end

	self[networkSenderName] = function(...)
		local args, argsVarCount = table.Pack(...)

		local startArg = args[1] == self and 2 or 1

		local handlerResult, resultVarCount = table.Pack(networkSenderBody(unpack(args, startArg, argsVarCount)))
		if resultVarCount == 0 then return end

		local errorText = handlerResult[1]
		if isstring(errorText) then
			LogSendNetError(LOG_ERROR, networkSenderName, errorText)
		elseif errorText then
			LogSendNetError(LOG_ERROR, networkSenderName, "errorText is " .. type(errorText) .. ", should be string or nil!")
		end

		if resultVarCount > 1 then
			return unpack(handlerResult, 2, resultVarCount)
		end
	end
end
