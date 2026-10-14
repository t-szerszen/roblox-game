--!strict
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Config=require(ReplicatedStorage.Shared.Activity.EconomyConfig)
local Math={}
export type Motion={position: Vector3,anchor: Vector3,pending: number,weighted: number,wheelieTime: number,wheelieDistance: number,direction: Vector3?}
local MultiplierSteps=1/Config.WheelieMultiplierStep
function Math.WheelieMultiplier(seconds: number): number
	local raw=1+(Config.WheelieMaxMultiplier-1)*math.clamp(seconds/Config.WheelieRampSeconds,0,1)
	-- The paid value must match the 0.01 value shown to the player.
	return math.floor(raw*MultiplierSteps+0.000001)/MultiplierSteps
end
function Math.Delivery(distance: number): number
	return math.floor(Config.DeliveryMinCoins+(Config.DeliveryMaxCoins-Config.DeliveryMinCoins)*math.clamp(distance/Config.DeliveryFullRewardStuds,0,1)+0.5)
end
function Math.NewMotion(position: Vector3): Motion
	return {position=position,anchor=position,pending=0,weighted=0,wheelieTime=0,wheelieDistance=0,direction=nil}
end
function Math.Sample(motion: Motion, position: Vector3, velocity: Vector3, maxSpeed: number,
	grounded: boolean, wheelie: boolean, burnout: boolean, dt: number): (number,number,number)
	local offset=position-motion.position;motion.position=position
	local delta=Vector3.new(offset.X,0,offset.Z);local distance=delta.Magnitude
	local speed=Vector3.new(velocity.X,0,velocity.Z).Magnitude
	local valid=dt>0 and dt<=Config.MaxSampleSeconds and grounded and not burnout
		and distance>=0.05 and speed>=Config.MinimumRideSpeed
		and distance<=maxSpeed*dt*Config.MotionTolerance+0.5 and math.abs(offset.Y)<=Config.MaxVerticalStep
		and delta:Dot(velocity)>distance*speed*0.25
	if not valid then
		motion.anchor=position;motion.pending=0;motion.weighted=0;motion.wheelieTime=0;motion.wheelieDistance=0;motion.direction=nil
		return 0,1,1
	end
	motion.wheelieTime=if wheelie then motion.wheelieTime+dt else 0
	motion.wheelieDistance=if wheelie then motion.wheelieDistance+distance else 0
	local multiplier=Math.WheelieMultiplier(motion.wheelieTime)
	if motion.direction and delta.Unit:Dot(motion.direction)<0 then
		-- Small back-and-forth movements must not accumulate into a paid kilometer.
		motion.anchor=position-delta;motion.pending=0;motion.weighted=0
	end
	motion.direction=delta.Unit;motion.pending+=distance;motion.weighted+=distance*multiplier
	local net=position-motion.anchor;net=Vector3.new(net.X,0,net.Z)
	if net.Magnitude<Config.MinimumNetTravelStuds then return 0,multiplier,1 end
	local credited,average=motion.pending,motion.weighted/motion.pending
	motion.pending=0;motion.weighted=0;motion.anchor=position
	return credited,multiplier,average
end
return Math
