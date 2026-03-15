local AbstractCharacter = {}
local AbstractCharacterMT = {}
AbstractCharacterMT.__index = AbstractCharacterMT

function AbstractCharacter.new(model: Model)
	assert(typeof(model) == "Instance" and model:IsA("Model"), "AbstractCharacter.new expects a Model")

	local self = setmetatable({}, AbstractCharacterMT)

	-- WaitForChild is correct here; character children are not guaranteed
	-- to exist at the moment the AbstractCharacter is constructed
	self._humanoid = model:WaitForChild("Humanoid")
	self._root = model:WaitForChild("HumanoidRootPart")
	self._head = model:WaitForChild("Head")

	return self
end

function AbstractCharacterMT:GetHumanoid(): Humanoid
	return self._humanoid
end

function AbstractCharacterMT:GetRoot(): Part
	return self._root
end

function AbstractCharacterMT:GetHead(): Part
	return self._head
end

function AbstractCharacterMT:Destroy()
	table.clear(self)
	setmetatable(self, nil)
end

return AbstractCharacter
