--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScooterConfig = require(ReplicatedStorage.Shared.Scooter.ScooterConfig)

export type State = {
	throttleHeld: boolean,
	brakeHeld: boolean,
	steering: number,
	wheelieHeld: boolean,
	wheelieQueued: boolean,
	lastReceivedAt: number,
}

local ScooterInput = {}

function ScooterInput.New(): State
	return {
		throttleHeld = false,
		brakeHeld = false,
		steering = 0,
		wheelieHeld = false,
		wheelieQueued = false,
		lastReceivedAt = -math.huge,
	}
end

function ScooterInput.Reset(state: State)
	state.throttleHeld = false
	state.brakeHeld = false
	state.steering = 0
	state.wheelieHeld = false
	state.wheelieQueued = false
end

function ScooterInput.IsFresh(state: State, now: number): boolean
	return now - state.lastReceivedAt <= ScooterConfig.DriveInputTimeout
end

function ScooterInput.Apply(
	state: State,
	now: number,
	throttleHeld: unknown,
	brakeHeld: unknown,
	steering: unknown,
	wheelieHeld: unknown
): boolean
	if typeof(throttleHeld) ~= "boolean"
		or typeof(brakeHeld) ~= "boolean"
		or typeof(steering) ~= "number"
		or steering ~= steering
		or math.abs(steering) > 1
		or typeof(wheelieHeld) ~= "boolean"
	then
		return false
	end
	if now - state.lastReceivedAt < ScooterConfig.DriveRemoteMinInterval then
		return false
	end
	local wheeliePressed = wheelieHeld and not state.wheelieHeld
	state.throttleHeld = throttleHeld
	state.brakeHeld = brakeHeld
	state.steering = steering
	state.wheelieHeld = wheelieHeld
	state.wheelieQueued = state.wheelieQueued or wheeliePressed
	state.lastReceivedAt = now
	return true
end

return ScooterInput
