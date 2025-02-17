
local NO_STATE_ERR = "'%s' does not have a StateMachine"
local STATE_FUNCTION_PROMISE_ERR = "\n\nError running '%s' function for state '%s'\n\n%s\n\n"
local NO_STATE_FUNCTION_ERR = "'%s' does not have function '%s'"

local Promise = require(script.Parent.Parent.Promise)

local State = {}
local StateMT = {}
StateMT.__index = StateMT

export type StateFunction = (self:typeof(State.new())) -> nil

function State.new(name:string)
    local self = {}
    setmetatable(self, StateMT)

    self._stateMachine = nil
    self._name = name or "Unnamed State"

    return self
end

function StateMT:GetStateMachine()
    return self._stateMachine
end

function StateMT:AttachStateMachine(stateMachine)
    self._stateMachine = stateMachine
end

function StateMT:GetName()
    return self._name
end

function StateMT:_entered()
    assert(self:GetStateMachine(), NO_STATE_ERR:format(self:GetName()))
    assert(typeof(self.Entered) == "function", NO_STATE_FUNCTION_ERR:format(self:GetName(), "Entered"))

    return Promise.try(self.Entered, self):catch(function(err)
        warn(STATE_FUNCTION_PROMISE_ERR:format("Entered", self:GetName(), tostring(err)))
    end)
end

function StateMT:_exited()
    assert(self:GetStateMachine(), NO_STATE_ERR:format(self:GetName()))
    assert(typeof(self.Exited) == "function", NO_STATE_FUNCTION_ERR:format(self:GetName(), "Exited"))

    return Promise.try(self.Exited, self):catch(function(err)
        warn(STATE_FUNCTION_PROMISE_ERR:format("Exited", self:GetName(), tostring(err)))
    end)
end


function StateMT:_cycled()
    assert(self:GetStateMachine(), NO_STATE_ERR:format(self:GetName()))
    assert(typeof(self.Cycled) == "function", NO_STATE_FUNCTION_ERR:format(self:GetName(), "Cycled"))

    local function setNextState()
        local stateMachine = self:GetStateMachine()
        stateMachine:SetNextState(self:GetName())
    end

    return Promise.try(self.Cycled, self, setNextState):catch(function(err)
        warn(STATE_FUNCTION_PROMISE_ERR:format("Cycled", self:GetName(), tostring(err)))
    end)
end

function StateMT:Clone()
    return table.clone(self)
end

return State