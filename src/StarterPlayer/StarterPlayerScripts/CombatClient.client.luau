--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local player = Players.LocalPlayer
local actionRemote = ReplicatedStorage:WaitForChild(CombatConfig.RemoteFolderName):WaitForChild(CombatConfig.ActionRemoteName) :: RemoteEvent
local pepperBound = false

local function requestPepper(_name: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin and UserInputService:GetFocusedTextBox() == nil then
		actionRemote:FireServer("Pepper")
	end
	return Enum.ContextActionResult.Sink
end


local function updatePepperBinding()
	local shouldBind = player:GetAttribute(CombatConfig.PepperOwnershipAttribute) == true
	if shouldBind == pepperBound then
		return
	end
	pepperBound = shouldBind
	if shouldBind then
		ContextActionService:BindAction("CombatPepper", requestPepper, true, Enum.KeyCode.G, Enum.KeyCode.ButtonL2)
		ContextActionService:SetTitle("CombatPepper", "Gaz")
		ContextActionService:SetPosition("CombatPepper", UDim2.new(1, -230, 1, -95))
	else
		ContextActionService:UnbindAction("CombatPepper")
	end
end

local pepperConnection = player:GetAttributeChangedSignal(CombatConfig.PepperOwnershipAttribute):Connect(updatePepperBinding)
updatePepperBinding()

script.Destroying:Connect(function()
	pepperConnection:Disconnect()
	ContextActionService:UnbindAction("CombatPepper")
end)
