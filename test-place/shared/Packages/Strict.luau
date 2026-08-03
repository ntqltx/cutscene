--[=[
	Strict module re-written by avlex (@uid3v)
	-- :: original made by @fl0mDev (StrictGetter)
]=]

--!native
--!nocheck

type Getter<T> = (input: Instance?) -> T?

type Instances = {
	Humanoid: Getter<Humanoid>,
	Animator: Getter<Animator>,
	Animation: Getter<Animation>,
	Shirt: Getter<Shirt>,
	TextButton: Getter<TextButton>,
	TextLabel: Getter<TextLabel>,
	TextBox: Getter<TextBox>,
	ImageLabel: Getter<ImageLabel>,
	GuiObject: Getter<GuiObject>,
	Model: Getter<Model>,
	Folder: Getter<Folder>,
	Frame: Getter<Frame>,
	ScrollingFrame: Getter<ScrollingFrame>,
	CanvasGroup: Getter<CanvasGroup>,
	ViewportFrame: Getter<ViewportFrame>,
	PlayerGui: Getter<PlayerGui>,
	ScreenGui: Getter<ScreenGui>,
	SurfaceGui: Getter<SurfaceGui>,
	UIStroke: Getter<UIStroke>,
	UIListLayout: Getter<UIListLayout>,
	UIScale: Getter<UIScale>,
	UIShadow: Getter<UIShadow>,
	Sound: Getter<Sound>,
	Part: Getter<Part>,
	BasePart: Getter<BasePart>,
	MeshPart: Getter<MeshPart>,
	Motor6D: Getter<Motor6D>,
	Weld: Getter<Weld>,
	VectorForce: Getter<VectorForce>,
	LinearVelocity: Getter<LinearVelocity>,
	BodyAngularVelocity: Getter<BodyAngularVelocity>,
	Decal: Getter<Decal>,
	ParticleEmitter: Getter<ParticleEmitter>,
	Atmosphere: Getter<Atmosphere>,
	Attachment: Getter<Attachment>,
	ModuleScript: Getter<ModuleScript>,
}

local function resolve<T>(className: string): Getter<T>
	return function(input: Instance?): T?
		if (input) and (input:IsA(className)) then
			return input :: T
		end

		return nil
	end
end

const Strict = {}

setmetatable(Strict, {
	__index = function(_, className: string)
		local getter = resolve(className)
		rawset(Strict, className, getter)
		return getter
	end,
})

return Strict :: Instances