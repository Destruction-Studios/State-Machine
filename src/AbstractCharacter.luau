local AbstractCharacter = {}
AbstractCharacter.__index = AbstractCharacter

function AbstractCharacter.new(model: Model)
	local self = {}
	setmetatable(self, AbstractCharacter)

	self._humanoid = model:WaitForChild("Humanoid")
	self._root = model:WaitForChild("HumanoidRootPart")
	self._head = model:WaitForChild("Head")

	return self
end

function AbstractCharacter:GetHumanoid(): Humanoid
	return self._humanoid
end

function AbstractCharacter:GetRoot(): Part
	return self._root
end

function AbstractCharacter:GetHead(): Part
	return self._head
end

function AbstractCharacter:Destroy()
	table.clear(self)
	setmetatable(self, nil)
end

return AbstractCharacter
