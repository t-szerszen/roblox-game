--!strict
local Types = require(script.Parent.TrafficTypes)
local Trajectory = {}
function Trajectory.Finite(n: number): boolean
	return n == n and math.abs(n) < math.huge
end
function Trajectory.ValidVector(v: any): boolean
	return typeof(v) == "Vector3" and Trajectory.Finite(v.X) and Trajectory.Finite(v.Y) and Trajectory.Finite(v.Z)
end
function Trajectory.Evaluate(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: number): (Vector3, Vector3, number)
	local u = 1-t
	local position = a*u*u*u + b*3*u*u*t + c*3*u*t*t + d*t*t*t
	local first = (b-a)*3*u*u + (c-b)*6*u*t + (d-c)*3*t*t
	local second = (c-b*2+a)*6*u + (d-c*2+b)*6*t
	local magnitude = first.Magnitude
	local direction = if magnitude > 0.0001 then first/magnitude else (d-a).Unit
	local curvature = if magnitude > 0.0001 then first:Cross(second).Magnitude / magnitude^3 else 0
	return position, direction, curvature
end
function Trajectory.Sample(a: Vector3, b: Vector3, c: Vector3, d: Vector3, spacing: number, limit: number): ({Types.Sample}, number, number)
	local polygonLength = (b-a).Magnitude + (c-b).Magnitude + (d-c).Magnitude
	local count = math.ceil(polygonLength / spacing)
	assert(count >= 1 and count <= limit, "Curve exceeds sample budget")
	local samples: {Types.Sample} = {}
	local distance, maxCurvature = 0, 0
	for i=0,count do
		local p, direction, curvature = Trajectory.Evaluate(a,b,c,d,i/count)
		if i>0 then distance += (p-samples[i].position).Magnitude end
		maxCurvature = math.max(maxCurvature, curvature)
		table.insert(samples,{position=p,direction=direction,curvature=curvature,distance=distance})
	end
	return samples,distance,maxCurvature
end
function Trajectory.At(path: Types.Path, distance: number): Types.Sample
	local samples = path.samples
	local lo, hi = 1, #samples
	while lo < hi do
		local mid = math.floor((lo+hi)/2)
		if samples[mid].distance < distance then lo=mid+1 else hi=mid end
	end
	if lo == 1 then return samples[1] end
	local a,b = samples[lo-1],samples[lo]
	local t = math.clamp((distance-a.distance)/math.max(0.0001,b.distance-a.distance),0,1)
	local direction = a.direction:Lerp(b.direction,t)
	return {position=a.position:Lerp(b.position,t), direction=direction.Unit,
		curvature=a.curvature+(b.curvature-a.curvature)*t,distance=distance}
end
function Trajectory.Approach(value: number, target: number, rate: number, dt: number): number
	return value + math.clamp(target-value,-rate*dt,rate*dt)
end
function Trajectory.SafeSpeed(distance: number, gap: number, braking: number): number
	return math.sqrt(2*braking*math.max(0,distance-gap))
end
return Trajectory
