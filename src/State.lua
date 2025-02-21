
local NO_STATE_ERR = "'%s' does not have a StateMachine"
local STATE_FUNCTION_PROMISE_ERR = "\n\nError running '%s' function for state '%s'\n\n%s\n\n"
local NO_STATE_FUNCTION_ERR = "'%s' does not have function '%s'"

local Promise = require(script.Parent.Parent.Promise)
local Trove = require(script.Parent.Parent.Trove)

local State = {}
local StateMT = {}
StateMT.__index = StateMT

export type StateFunction = (self:typeof(State.new())) -> nil

function State.new(name:string)
    local self = {}
    setmetatable(self, StateMT)

    self._trove = nil
    self._stateMachine = nil
    self._name = name or "Unnamed State"

    return self
end

function StateMT:CreateTrove()
    self:_clean()
    self._trove = Trove.new()
    return self._trove
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

function StateMT:_clean()
    if self._trove then
        self._trove:Clean()
        self._trove = nil
    end
end

function StateMT:_machineStart()
    if not self.MachineStart then
        return
    end
    return Promise.try(self.MachineStart, self):catch(function(err)
        warn(STATE_FUNCTION_PROMISE_ERR:format("MachineStart", self:GetName(), tostring(err)))
    end)
end

function StateMT:_machineStop()
    if not self.MachineStop then
        return
    end
    return Promise.try(self.MachineStop, self):catch(function(err)
        warn(STATE_FUNCTION_PROMISE_ERR:format("MachineStop", self:GetName(), tostring(err)))
    end)
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
    -- assert(typeof(self.Exited) == "function", NO_STATE_FUNCTION_ERR:format(self:GetName(), "Exited"))

    self:_clean()

    if self.Exited == nil then
        return
    end


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