local State = require(script.State)
local Signal = require(script.Parent.Signal)

-- export type State = typeof(State.new())
export type StateIdentifier = string | number

export type TroveLike = {
	Clean: (self: TroveLike) -> nil,
	Add: <T>(self: TroveLike, object: T, cleanup: any?) -> T,
}

export type State = {
	GetStateMachine: (self: State) -> StateMachine,
	GetName: (self: State) -> string,

	CreateTrove: (self: State) -> TroveLike,

	AttachStateMachine: (self: State, stateMachine: StateMachine) -> nil,

	Cycled: (self: State, enterState: () -> nil) -> nil,
	Entered: (self: State) -> nil,
	Exited: (self: State) -> nil,

	MachineStart: (self: State) -> nil,
	MachineStop: (self: State) -> nil,

	Clone: (self: State) -> State,
}

export type StateMachine = {
	Debug: (self: StateMachine) -> StateMachine,

	GetState: (self: StateMachine, stateIdentifier: StateIdentifier) -> State,
	GetStates: (self: StateMachine) -> { [number]: State },
	GetCurrentState: (self: StateMachine) -> State,
	GetLastState: (self: StateMachine) -> State,

	SetStates: (self: StateMachine, states: { State }) -> StateMachine,
	SetDefaultState: (self: StateMachine, defaultState: StateIdentifier) -> StateMachine,
	SetNextState: (self: StateMachine, nextState: StateIdentifier) -> StateMachine,

	UpdateState: (self: StateMachine) -> StateMachine,
	Start: (self: StateMachine) -> StateMachine,
	Stop: (self: StateMachine) -> nil,
	Destroy: (self: StateMachine) -> nil,
}

local NO_STATE_AT_INDEX_ERR = "Could not find state at index '%s'"
local NO_STATE_AT_KEY_ERR = "Could not find state at key '%s'"
local NO_DEFAULT_STATE_ERR = "State Machine does not have a Default State"
local ALREADY_STARTED_ERR = "State Machine has already been started"
local NOT_STARTED_ERR = "State Machine has not been started"
local NO_STATES_ERR = "State Machine has no states"
local DUPE_STATE_NAME = "Duplicate state name of '%s'"

local StateMachine = {}
local StateMachineMT = {}
StateMachineMT.__index = StateMachineMT

StateMachine.State = State :: {
	new: (name: string) -> State,
}

function StateMachine.new(states: { State }): StateMachine
	local self = {}
	setmetatable(self, StateMachineMT)

	self._states = states

	self._stopped = false

	self._currentState = nil
	self._defaultState = nil
	self._queuedState = nil
	self._lastState = nil

	self._debug = false

	self.StateChanged = Signal.new()

	self._started = false

	return self
end

function StateMachineMT:_printDebug(str)
	if self._debug then
		print(`\n[STATE-MACHINE] {str}\n`)
	end
end

function StateMachineMT:Debug()
	self._debug = true

	return self
end

function StateMachineMT:GetLastState()
	return self._lastState
end

function StateMachineMT:GetStateFromKey(stateKey: StateIdentifier): State
	local states = self:GetStates()
	local newState = nil
	if typeof(stateKey) == "number" then
		newState = states[stateKey]
		assert(newState, NO_STATE_AT_INDEX_ERR:format(stateKey))
	elseif typeof(stateKey) == "string" then
		for _, state in states do
			if state:GetName() == stateKey then
				newState = state
				break
			end
		end
		assert(newState, NO_STATE_AT_KEY_ERR:format(stateKey))
	end

	return newState
end

function StateMachineMT:GetCurrentState(): State
	return self._currentState
end

function StateMachineMT:GetStates(): { [number]: State }
	return self._states
end

function StateMachineMT:SetStates(states: { State })
	assert(typeof(states) == "table", `Invalid type for argument #1 :SetStates expected 'table' got {typeof(states)}`)

	local tracked = {}
	for _, v in states do
		if table.find(tracked, v:GetName()) then
			error(DUPE_STATE_NAME:format(v:GetName()))
		end
		table.insert(tracked, v:GetName())
	end
	table.clear(tracked)

	self._states = states

	return self
end

function StateMachineMT:SetDefaultState(defaultState: StateIdentifier)
	assert(not self._started, ALREADY_STARTED_ERR)

	self._defaultState = self:GetStateFromKey(defaultState)

	return self
end

function StateMachineMT:SetNextState(state: StateIdentifier)
	assert(self._started, NOT_STARTED_ERR)
	self._queuedState = self:GetStateFromKey(state)

	return self
end

function StateMachineMT:_machineStart()
	for _, v in self:GetStates() do
		v:_machineStart()
	end
end

function StateMachineMT:_machineStop()
	for _, v in self:GetStates() do
		v:_machineStop()
	end
end

function StateMachineMT:UpdateState()
	local nextState = nil
	if self._queuedState ~= nil then
		self:_printDebug(`State Override Found.`)
		nextState = self._queuedState
		self._queuedState = nil
	else
		for _, v in self:GetStates() do
			if self._stopped then
				return
			end
			local shouldBreak = v:_cycled()
				:andThen(function()
					if self._queuedState ~= nil then
						return true
					end
					return false
				end)
				:expect()
			self:_printDebug(`{v:GetName()} Cycled result: {shouldBreak}`)
			if shouldBreak then
				nextState = v
				break
			end
		end
	end

	if self._stopped then
		return
	end

	self._queuedState = nil

	nextState = nextState or self._defaultState

	self:_printDebug(`Entering new state {nextState:GetName()}`)

	if self._lastState then
		self._lastState:_exited()
	end

	self._lastState = self._currentState

	self._currentState = nextState
	self._currentState:_entered()

	return self
end

function StateMachineMT:Start()
	assert(not self._started, ALREADY_STARTED_ERR)
	assert(self._defaultState, NO_DEFAULT_STATE_ERR)
	assert(self._states ~= nil, NO_STATES_ERR)
	assert(#self._states > 0, NO_STATES_ERR)

	for _, state in self:GetStates() do
		state:AttachStateMachine(self)
	end

	self._queuedState = self._defaultState
	self._started = true

	self:_machineStart()
	self:UpdateState()

	self:_printDebug(`Started State Machine with default state {self._currentState:GetName()}`)

	return self
end

function StateMachineMT:Stop()
	self._stopped = true

	for _, v in self:GetStates() do
		v:_clean()
	end
	if self._currentState then
		self:GetCurrentState():_exited()
	end
	self:_machineStop()
end

function StateMachineMT:Destroy()
	self:Stop()
end

return StateMachine
