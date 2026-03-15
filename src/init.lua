local State = require(script.State)
local AbstractCharacter = require(script.AbstractCharacter)
local Signal = require(script.Parent.Signal)

-- Types

export type Signal = typeof(Signal.new())
export type StateIdentifier = string | number

export type TroveLike = {
	Clean: (self: TroveLike) -> nil,
	Add: <T>(self: TroveLike, object: T, cleanup: any?) -> T,
}

export type AbstractCharacter = {
	GetRoot: (self: AbstractCharacter) -> Part,
	GetHead: (self: AbstractCharacter) -> Part,
	GetHumanoid: (self: AbstractCharacter) -> Humanoid,
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
	Data: {},

	Debug: (self: StateMachine) -> StateMachine,

	GetState: (self: StateMachine, stateIdentifier: StateIdentifier) -> State,
	GetStates: (self: StateMachine) -> { [number]: State },
	GetCurrentState: (self: StateMachine) -> State,
	GetLastState: (self: StateMachine) -> State,
	GetAbstractCharacter: (self: StateMachine) -> AbstractCharacter?,

	SetAbstractCharacter: (self: StateMachine, abstractCharacter: AbstractCharacter) -> StateMachine,
	SetStates: (self: StateMachine, states: { State }) -> StateMachine,
	SetDefaultState: (self: StateMachine, defaultState: StateIdentifier) -> StateMachine,
	SetNextState: (self: StateMachine, nextState: StateIdentifier) -> StateMachine,

	UpdateState: (self: StateMachine) -> StateMachine,
	Start: (self: StateMachine) -> StateMachine,
	Stop: (self: StateMachine) -> nil,
	Destroy: (self: StateMachine) -> nil,

	EnteredState: Signal,
	EnteringState: Signal,
}

-- Errors

local ERR_NO_STATE_AT_INDEX = "Could not find state at index '%s'"
local ERR_NO_STATE_AT_KEY = "Could not find state at key '%s'"
local ERR_NO_DEFAULT_STATE = "StateMachine does not have a default state set"
local ERR_ALREADY_STARTED = "StateMachine has already been started"
local ERR_NOT_STARTED = "StateMachine has not been started yet"
local ERR_NO_STATES = "StateMachine has no states"
local ERR_DUPE_STATE_NAME = "Duplicate state name '%s'"
local ERR_INVALID_STATES_ARG = "SetStates expected a table, got '%s'"

-- Implementation

local StateMachine = {}
local StateMachineMT = {}
StateMachineMT.__index = StateMachineMT

StateMachine.State = State :: {
	new: (name: string) -> State,
}
StateMachine.AbstractCharacter = AbstractCharacter :: {
	new: (model: Model) -> AbstractCharacter,
}

local function cloneStates(states: { State }): { State }
	local cloned = {}
	for i, state in states do
		cloned[i] = state:Clone()
	end
	return cloned
end

local function assertNoDuplicateNames(states: { State })
	local seen = {}
	for _, state in states do
		local name = state:GetName()
		assert(not seen[name], ERR_DUPE_STATE_NAME:format(name))
		seen[name] = true
	end
end

function StateMachine.new(states: { State }): StateMachine
	assert(typeof(states) == "table", ERR_INVALID_STATES_ARG:format(typeof(states)))
	assertNoDuplicateNames(states)

	local self = setmetatable({}, StateMachineMT)

	self._states = cloneStates(states)
	self._currentState = nil
	self._defaultState = nil
	self._queuedState = nil
	self._lastState = nil
	self._abstractChar = nil
	self._started = false
	self._stopped = false
	self._debug = false

	self.Data = {}
	self.EnteredState = Signal.new()
	self.EnteringState = Signal.new()

	return self
end

-- Debug

function StateMachineMT:_log(str: string)
	if self._debug then
		print(`\n[STATE-MACHINE] {str}\n`)
	end
end

function StateMachineMT:Debug(): StateMachine
	self._debug = true
	return self
end

-- Getters

function StateMachineMT:GetStates(): { [number]: State }
	return self._states
end

function StateMachineMT:GetCurrentState(): State
	return self._currentState
end

function StateMachineMT:GetLastState(): State
	return self._lastState
end

function StateMachineMT:GetAbstractCharacter(): AbstractCharacter?
	return self._abstractChar
end

--- Resolves a StateIdentifier to a State object. Errors if not found.
function StateMachineMT:GetState(stateKey: StateIdentifier): State
	if typeof(stateKey) == "number" then
		local state = self._states[stateKey]
		assert(state, ERR_NO_STATE_AT_INDEX:format(stateKey))
		return state
	elseif typeof(stateKey) == "string" then
		for _, state in self._states do
			if state:GetName() == stateKey then
				return state
			end
		end
		error(ERR_NO_STATE_AT_KEY:format(stateKey))
	end
	error(`Invalid StateIdentifier type: {typeof(stateKey)}`)
end

-- Setters

function StateMachineMT:SetAbstractCharacter(char: AbstractCharacter): StateMachine
	self._abstractChar = char
	return self
end

function StateMachineMT:SetStates(states: { State }): StateMachine
	assert(typeof(states) == "table", ERR_INVALID_STATES_ARG:format(typeof(states)))
	assertNoDuplicateNames(states)

	self._states = cloneStates(states)

	return self
end

function StateMachineMT:SetDefaultState(defaultState: StateIdentifier): StateMachine
	assert(not self._started, ERR_ALREADY_STARTED)
	self._defaultState = self:GetState(defaultState)
	return self
end

function StateMachineMT:SetNextState(state: StateIdentifier): StateMachine
	assert(self._started, ERR_NOT_STARTED)
	self._queuedState = self:GetState(state)
	return self
end

-- Lifecycle helpers

function StateMachineMT:_machineStart()
	for _, state in self._states do
		state:_machineStart()
	end
end

function StateMachineMT:_machineStop()
	for _, state in self._states do
		state:_machineStop()
	end
end

-- Core update loop

function StateMachineMT:UpdateState(): StateMachine
	if self._stopped then
		return self
	end

	local nextState = nil

	if self._queuedState ~= nil then
		-- An explicit override was set via SetNextState
		self:_log("State override found, skipping cycle checks.")
		nextState = self._queuedState
		self._queuedState = nil
	else
		-- Let each state's Cycled function decide if it should become active
		for _, state in self._states do
			if self._stopped then
				return self
			end

			local wantsToEnter = state
				:_cycled()
				:andThen(function()
					-- _cycled may have caused a SetNextState call
					if self._queuedState ~= nil then
						return true
					end
					return false
				end)
				:expect()

			self:_log(`{state:GetName()} Cycled → wantsToEnter: {wantsToEnter}`)

			if wantsToEnter then
				nextState = state
				self._queuedState = nil
				break
			end
		end
	end

	if self._stopped then
		return self
	end

	-- Fall back to the default state if no state requested entry
	nextState = nextState or self._defaultState

	self:_log(`Transitioning to state: {nextState:GetName()}`)

	-- Exit previous state
	if self._currentState then
		self._currentState:_exited()
	end

	self._lastState = self._currentState

	-- Enter next state
	self.EnteringState:Fire(nextState:GetName())
	self._currentState = nextState
	self._currentState:_entered()
	self.EnteredState:Fire(nextState:GetName())

	return self
end

-- Start / Stop / Destroy

function StateMachineMT:Start(): StateMachine
	assert(not self._started, ERR_ALREADY_STARTED)
	assert(self._defaultState ~= nil, ERR_NO_DEFAULT_STATE)
	assert(self._states ~= nil and #self._states > 0, ERR_NO_STATES)

	for _, state in self._states do
		state:AttachStateMachine(self)
	end

	self._started = true
	self._stopped = false
	self._queuedState = self._defaultState

	self:_machineStart()
	self:UpdateState()

	self:_log(`Started with default state: {self._currentState:GetName()}`)

	return self
end

function StateMachineMT:Stop()
	if self._stopped then
		return
	end

	self._stopped = true

	-- Clean all state troves
	for _, state in self._states do
		state:_clean()
	end

	-- Exit the active state
	if self._currentState then
		self._currentState:_exited()
	end

	self:_machineStop()
	self._started = false
end

function StateMachineMT:Destroy()
	self:Stop()
	self.EnteredState:Destroy()
	self.EnteringState:Destroy()
end

return StateMachine
