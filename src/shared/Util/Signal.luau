--!nonstrict
-- Sinal simples (estilo RBXScriptSignal) para comunicação entre módulos do mesmo lado.
--   local s = Signal.new()
--   local conn = s:Connect(function(a, b) end)
--   s:Fire(1, 2)
--   conn:Disconnect()

local Signal = {}
Signal.__index = Signal

export type Connection = { Disconnect: (self: any) -> (), Connected: boolean }

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(handler: (...any) -> ()): Connection
	local connection = { Connected = true }
	local handlers = self._handlers
	function connection.Disconnect(conn)
		if not conn.Connected then
			return
		end
		conn.Connected = false
		local index = table.find(handlers, handler)
		if index then
			table.remove(handlers, index)
		end
	end
	table.insert(handlers, handler)
	return connection
end

function Signal:Once(handler: (...any) -> ()): Connection
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal:Fire(...: any)
	for _, handler in table.clone(self._handlers) do
		task.spawn(handler, ...)
	end
end

function Signal:Wait(): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	table.clear(self._handlers)
end

return Signal
