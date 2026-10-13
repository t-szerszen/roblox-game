local Test = {}

function Test.Run(paint, source, legacy)
	local model = source:Clone()
	local count = 0
	local ok, problem = xpcall(function()
		local targets = paint.Targets(model)
		local colors = {}
		for index, id in {"Deck","Stem","Suspension","Grips","Handlebar","BrakeLevers","Calipers","BrakeDiscs"} do
			assert(targets[id] and #targets[id]>0, "Missing G4 paint group: "..id)
			count += 1
			colors[id] = Color3.fromRGB(index*20,80,140)
		end
		paint.Apply(model,colors)
		for id, list in targets do
			for _, part in list do assert(part.Color==colors[id],"Tagged compound part did not change color") end
			count += 1
		end
		local before = paint.Read(legacy)
		assert(before.Deck==legacy.ScooterBody:FindFirstChildOfClass("SurfaceAppearance").Color,
			"Legacy primary deck color remains stable")
		count += 1
	end,debug.traceback)
	model:Destroy()
	if not ok then error(problem,2) end
	return count
end

return Test
