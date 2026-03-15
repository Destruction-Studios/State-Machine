local NO_STATE_ERR = "'%s' does not have a StateMachine attached"
local STATE_FUNCTION_PROMISE_ERR = "\n\nError running '%s' function for state '%s'\n\n%s\n\n"

local Promise = require(script.Parent.Parent.Promise)
local Trove = require(script.Parent.Parent.Trove)

local State = {}
local StateMT = {}
StateMT.__index = StateMT

export type StateFunction = (self: typeof(State.new())) -> nil

function State.new(name: string)
	local self = {}
	setmetatable(self, StateMT)

	self._trove = nil
	self._stateMachine = nil
	self._name = name or "Unnamed State"

	return self
end

-- Public API

function StateMT:GetName(): string
	return self._name
end

function StateMT:GetStateMachine()
	return self._stateMachine
end

function StateMT:AttachStateMachine(stateMachine)
	self._stateMachine = stateMachine
end

function StateMT:CreateTrove()
	self:_clean()
	self._trove = Trove.new()
	return self._trove
end

function StateMT:Clone()
	local clone = table.clone(self)
	setmetatable(clone, StateMT)
	-- Clear instance-specific state so the clone is fresh
	clone._trove = nil
	clone._stateMachine = nil
	return clone
end

-- Private helpers

function StateMT:_clean()
	if self._trove then
		self._trove:Clean()
		self._trove = nil
	end
end

function StateMT:_tryCall(fnName: string, ...)
	local fn = self[fnName]
	if fn == nil then
		return Promise.resolve(false)
	end
	assert(
		typeof(fn) == "function",
		`Expected '{fnName}' on state '{self:GetName()}' to be a function, got {typeof(fn)}`
	)
	return Promise.try(fn, self, ...):catch(function(err)
		warn(STATE_FUNCTION_PROMISE_ERR:format(fnName, self:GetName(), tostring(err)))
	end)
end

function StateMT:_machineStart()
	return self:_tryCall("MachineStart")
end

function StateMT:_machineStop()
	return self:_tryCall("MachineStop")
end

function StateMT:_entered()
	assert(self:GetStateMachine(), NO_STATE_ERR:format(self:GetName()))
	-- Entered is optional; states may only need Cycled
	return self:_tryCall("Entered")
end

function StateMT:_exited()
	assert(self:GetStateMachine(), NO_STATE_ERR:format(self:GetName()))
	self:_clean()
	return self:_tryCall("Exited")
end

function StateMT:_cycled()
	assert(self:GetStateMachine(), NO_STATE_ERR:format(self:GetName()))
	assert(typeof(self.Cycled) == "function", `State '{self:GetName()}' is missing a required 'Cycled' function`)

	local function setNextState()
		self:GetStateMachine():SetNextState(self:GetName())
	end

	return self:_tryCall("Cycled", setNextState)
end

return State
