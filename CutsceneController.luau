--!strict

--[[ 

	cutscene system/controller written by avlex (@uid3v) (all of my code is strict btw)
	!!! WARNING – THIS IS MADE ONLY FOR START CUTSCENE AT THE JOIN, NOT FOR MULTIPLE CUTSCENES !!!

	! tips for animator on how to correctly make awesome cutscenes:
	1. the cutscene model (“MainCutscene”) is located in ReplicatedStorage.Assets.

	2. inside the model, there’s a “Rigs” folder. 
	   that’s where you add the elements that will be animated (not the map/scene!)
	   but only characters and various rigged objects.

	3. in the Moon Animator, when adding rigs, make sure to check the “Animation Events” box to add markers for things like: 
	   1) changing camera’s FOV;
	   2) adding various sound effects;
	   3) changing faces of rigs that have a head and face;
	   4) and also to add skipping segment markers.

	4. animate everything with each rig in a single animation file, 
	   not in several separate ones but as one complete sequence.
	   keep in mind that each rig must end at the exact same keyframe to avoid any teleportation or further issues.

	5. to change the camera’s FOV:
	   1) add a marker to the “CameraRig”;
	   2) name the marker “FOV” and enter the value in this format: “Value, Speed, Damping.” 
	      that's basically: Value -> FOV value; Speed -> speed of change; Damping → amplitude, i.e., the damping of the change.

	6. to change a character’s face: 
	   you need to make sure the rig has a boolean attribute named “CharacterRig” (the existing “PlayerRig” model already has this).
	   then in the events of the rig you need to create a marker named “FACE”, and then enter the face ID with or without “rbxassetid://”.

	7. to add a sound effect to an animation:
	   you can create a “SOUND” marker in any rig and enter the full, correct name of your sound effect
	   which must be located in SoundService.SoundEffects.

	8. to add skip points where the animation continues after the skip button is pressed:
	   1) create a marker named “SKIP_POINT” in “CameraRig” (make sure it’s in the camera);
	   2) and place it where you need it.

	9. after you’ve done everything, click File -> Export Rigs. 
	   it'll show you every saved animation for each rig. 
	   you need to export it to Roblox, copy the animation,
	   and then create an Animation in the rig named “Track” and simply paste the rig’s animation ID there.
	   do this for every rig that has an animation.

]]

-- [[ services, folders and "SoundEffects" sound group
const Players = game:GetService("Players")
const AnimationClipProvider = game:GetService("AnimationClipProvider")
const StarterGui = game:GetService("StarterGui")

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const Assets = ReplicatedStorage:WaitForChild("Assets")

const SoundService = game:GetService("SoundService")
const SoundEffects = SoundService:WaitForChild("SoundEffects")
-- ]]

-- [[ modules that I'm using in the system
const Fusion = require(ReplicatedStorage.Shared.Packages.Fusion) -- the GOAT???
const Promise = require(ReplicatedStorage.Shared.Packages.Promise) -- typed version of promises, nothing special
const Janitor = require(ReplicatedStorage.Shared.Packages.Janitor) -- one of the best cleanup modules
const Signal = require(ReplicatedStorage.Shared.Packages.LemonSignal) -- fastest signal module
const Strict = require(ReplicatedStorage.Shared.Packages.Strict) -- my runtime-checked typed safe instance caster
-- ]]

-- [[ file constants
const FOV_DEFAULT: number = 70
const FOV_SPEED_DEFAULT: number = 20
const FOV_DAMPING_DEFAULT: number = 1

const FOV_MARKER: string = "FOV"
const FACE_MARKER: string = "FACE"
const SOUND_MARKER: string = "SOUND"
const SKIP_MARKER: string = "SKIP_POINT"

const LOAD_TIMEOUT: number = 5
const WAIT_TIME_SKIP: number = 2
-- ]]

const scope: Fusion.Scope = Fusion.scoped(Fusion) -- file main fusion scope
type NumValue = Fusion.Value<number> -- made for better readability

-- controller module table that handles all public/private variables and functions
local CutsceneController = {
	IsPlaying = false :: boolean,
	Started = Signal.new() :: Signal.Signal<()>,
	Ended = Signal.new() :: Signal.Signal<()>,
	
	_player = Players.LocalPlayer :: Player,
	_camera = workspace.CurrentCamera :: Camera,
	
	_scene = nil :: Model?,
	_cameraRig = nil :: Model?,
	_playingSounds = nil :: Folder?,
	
	_tracks = {} :: {AnimationTrack},
	_skipPoints = {} :: {number},
	_cameraTrack = nil :: AnimationTrack?,
	
	_canvas = nil :: CanvasGroup?,
	_canvasVisible = Fusion.Value(scope, 1) :: NumValue,

	_skipEnabled = false :: boolean,
	_skipVisible = Fusion.Value(scope, 1) :: NumValue,
	_skipLabel = Fusion.Value(scope, "SKIP 0/0") :: Fusion.Value<string>,
	
	_currentFov = Fusion.Value(scope, FOV_DEFAULT) :: NumValue,
	_speed = Fusion.Value(scope, FOV_SPEED_DEFAULT) :: NumValue,
	_damping = Fusion.Value(scope, FOV_DAMPING_DEFAULT) :: NumValue,

	_cleanupScope = Fusion.scoped(Fusion) :: Fusion.Scope,
	_janitor = Janitor.new() :: Janitor.Janitor,
	_resolve = nil :: (() -> ())?,
}

-- public start function that is setting up controller for cutscenes
function CutsceneController.Start(self: Controller, canvas: CanvasGroup)
	-- checks if there is player, if not, returns
	if not self._player then
		return
	end
	
	-- looks for cutscene scene model
	local cutscene: Model? = Strict.Model(Assets:WaitForChild("MainCutscene"))
	if not cutscene then
		return warn("[CutsceneController]: no start cutscene was found")
	end
	
	-- warns if no canvas group was given in the function argument that we're requiring
	if not canvas then
		return warn("[CutsceneController]: no canvas was given")
	end
	-- binds canvas with fusion and sets it as variable
	self:_bindCanvas(canvas)
	
	task.spawn(function()
		-- creating folder for sounds that are played in the animation
		local playingSounds: Folder = Instance.new("Folder") -- no second argument in folder!!! I swear if you reject my application...
		playingSounds.Name = "PlayingSounds"
		playingSounds.Parent = SoundService -- setting parent hererere
		
		-- set variable and adding it to janitor for it to clean after cutscene stops
		self._playingSounds = playingSounds
		self._janitor:Add(self._playingSounds)
	end)
	
	self._scene = cutscene -- set self variable
	self._scene.Parent = workspace -- move scene to workspace
	self._janitor:Add(self._scene) -- adding scene to janitor
end

-- public play function to play cutscenes, no shit
-- returns typed promise btw
function CutsceneController.Play(self: Controller): (Promise.Promise)
	-- checks if cutscene is playing, if yes, then rejecting promise
	if self.IsPlaying then
		return Promise.reject("Cutscene is already playing")
	end
	
	-- if no scene loaded then rejecting it too
	if not self._scene then
		return Promise.reject("Scene is not loaded")
	end

	-- set all core guis enabled to false
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	
	-- creating new promise for play function that we're returning
	return Promise.new(function(resolve: () -> (), reject: (...any) -> ())
		self.IsPlaying = true -- set IsPlaying to true because we've started cutscene
		self._resolve = resolve -- adding private resolve promise function for stop function
		
		-- loading all tracks from the scene
		self._tracks = self:_loadTracks(self._scene) -- it's returning table of the tracks so we're also setting _tracks
		self:_bindCamera() -- binds camera after loading all tracks and the camera one too

		self._canvasVisible:set(0) -- set fusion canvas visibility value to 0
		self:_updateSkipLabel() -- run function that would watch all skip points in the animation
		
		-- iterating through all tracks in self._tracks
		for _, track: AnimationTrack in self._tracks do -- only generalized iteration btw
			track:Play() -- starting all tracks
		end
		
		-- this is added so player would start watching cutscene and after wait time he would unlock ability to skip scene
		task.delay(WAIT_TIME_SKIP, function() -- waits with task.delay, right.
			self._skipVisible:set(0) -- set skip visibility button GroupTransparency to 0
			self._skipEnabled = true -- making sure that skipping is enabled
		end)

		-- adding all tracks into janitor for cleanup
		self._janitor:Add(function()
			table.clear(self._tracks) -- this clears all tracks from the table
			self._cameraTrack = nil -- removing current camera track after cutscene stops
		end)
		
		-- this checks if AnimationTrack for camera actually exists
		if self._cameraTrack then
			-- if it is exists, run janitor that would stop cutscene after camera track stops
			-- yes yes yes, this is how my cutscene controller works. this is because camera handles most of the animation points, go read down more
			self._janitor:Connect(self._cameraTrack.Stopped, function()
				self:Stop() -- stop current playing cutscene
			end)
		else -- else keyword if you didn't know, it's rejecting promise if no camera track found in self._tracks
			return reject("No camera track, cutscene won't auto-end")
		end
		
		-- firing public Started signal for other source files to know that cutscene is started
		self.Started:Fire()
	end)
end

-- public stop function that stops current playing cutscene and everything that we bind
-- also returns typed promise btw
function CutsceneController.Stop(self: Controller): (Promise.Promise)
	-- checks if cutscene is playing, if not, why...? rejects.
	if not self.IsPlaying then
		return Promise.reject("Cutscene isn't playing")
	end
	
	-- now we're creating new promise for stop function that we're returning too
	return Promise.new(function()
		self.IsPlaying = false -- cutscene isn't playing anymore.
		
		self._skipVisible:set(1) -- set skip visiblity button GroupTransparency to 1
		self._skipEnabled = false -- skip is now banned from being ran
		
		-- checks if janitor is even existing??
		if self._janitor then -- funny word
			self._janitor:Cleanup() -- cleanup everything that we've added to that janitor
		end
		
		-- checks if there is resolve function from the play function
		if self._resolve then
			local resolve = self._resolve -- we're duplicating resolve function into that variable
			self._resolve = nil -- then throwing the original one to trash so that, no one would run it again
			(resolve :: any)() -- actually running the resolve now and telling promise that the cutscene fully stopped
		end

		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true) -- returning our core gui enabled back to true!!!
		self._canvasVisible:set(1) -- set canvas group visibility GroupTransparency to 1
		
		-- self._cleanupScope is a fusion scope, that is created to being actually cleaned up
		-- for example, removing that spring for camera FOV so no other camera controllers would fight
		self._cleanupScope:doCleanup() -- cleaning up that specifically added scope
		self.Ended:Fire() -- firing public Ended signal that tells that current cutscene was finished
	end)
end

-- public skip function to skip cutscene parts using SkipPoints (no reason why it's public)
function CutsceneController.Skip(self: Controller)
	-- checks if cutscene is playing and if there is existing camera AnimationTrack
	if (not self.IsPlaying) or (not self._cameraTrack) then
		return -- returns if one of them does not exist or has "false" boolean
	end

	local now: number = self._cameraTrack.TimePosition -- gets current playing camera's track time position
	local target: number? -- nil value for holding next skip point after the current one
	
	-- find next skip point that is taken from camera track
	-- (camera track in my cutscene controller is the main character if you didn't understand)
	for _, point in self._skipPoints do -- iterates through all self._skipPoints that we have
		if point > (now + 0.1) then -- looks for the next skip point by checking current time position with a small 0.1 buffer
			target = point -- set target point to next point that we've found
			break -- stop iteration
		end
	end

	-- checks if there is current target and if there is, check if it's not past end
	if (not target) or (target >= self._cameraTrack.Length) then
		self:Stop() -- after pressing skip button it stops cutscene, because no next skip point found
		return -- returns and nothing more
	end

	-- this iteration is made for every track to jump forward to the target skip point
	for _, track in self._tracks do -- iterating through all self._tracks
		-- if current track isn't playing, then continue to next track from the iteration
		if not track.IsPlaying then
			continue
		end

		-- if track's length is smaller, then stop the current track
		if track.Length <= target then -- I love you then keyword...
			track:Stop() -- stop current track, we don't need it anymore (depends, you know what I am talking about)
			continue
		end

		-- changes track time position to the skip point time position
		track.TimePosition = target
	end
	
	-- refresh skip label that shows the number of skip points and where the player is right now
	self:_updateSkipLabel()
end

-- private function that loads all animation tracks from the scene model that is required in the arguments
-- returns either of these two: table of AnimationTracks or rejected promise
function CutsceneController._loadTracks(self: Controller, scene: Model): ({AnimationTrack} | Promise.Promise)
	local tracks: {AnimationTrack} = {} -- table of tracks that we would return after function collects all of them
	local rigs: Folder? = Strict.Folder(scene:WaitForChild("Rigs")) -- looking for "Rigs" folder that includes all animated models
	
	-- if no rigs folder found, return promise rejection
	if not rigs then
		return Promise.reject("No rigs folder found") -- no rigs found lmao :joy:
	end
	
	-- gets all rig models from folder, then binds the necessary ones and adds to the table
	for _, child in rigs:GetChildren() do -- iterates through rigs folder, only generalized iteration remember that
		if not child:IsA("Model") then -- checks if child is actually a model
			continue -- if not, continue to the other child
		end -- end keyword.
		
		-- looks for the Animation instance in the model with one second timeout
		local animation: Animation? = Strict.Animation(child:WaitForChild("Track", 1))
		if not animation then -- if no animation found then continue
			continue
		end

		-- variable for current animator
		local currentAnimator: Animator? | Humanoid? -- this is made because humanoid.animator no more idiomatic variant to load animations
		local isCamera: boolean = child:GetAttribute("Camera") == true -- looks for the Camera attribute in the rig, I should've add guard to check if camera is already here
		
		if isCamera then -- if rig is a camera then...
			if not self._cameraRig then -- if there is no self._cameraRig at the moment... wait, isn't that a guard that I was talking about a minute ago?
				local controller = child:WaitForChild("AnimationController") -- looks for the AnimationController in the camera rig
				local animator: Animator? = controller and Strict.Animator(controller:WaitForChild("Animator")) -- and then looks for the animator
				
				-- btw I just realized that I forgot to add support for custom rigs that aren't humanoid.
				-- please do not reject my application because of my stupidity, please mod I need this my mom is kinda homeless :sob::sob:

				if not animator then -- if no animator found, then rejecting promise
					return Promise.reject("No Animator found in camera rig")
				end
				
				currentAnimator = animator -- set currentAnimator as camera animator
				self._cameraRig = child -- set self._cameraRig as camera rig model
				
				-- loads skip points from camera AnimationTrack because he's the BOSS
				self:_loadSkipPoints(animation)
			end
		else -- if rig isn't a camera then it's a humanoid MAYBE??
			-- I actually forgot to add support for custom rigs, please mod, PLEASSEEEEE, DO NOT REJECT IT, I'M TOO LAZY, IT'S 4 AM IN A MORNING I NEED TO SLEEEP
			currentAnimator = Strict.Humanoid(child:WaitForChild("Humanoid")) -- looks for the humanoid and then set it as a currentAnimator variable
		end
		
		if currentAnimator then -- if there is animator found in a rig then...
			local track: AnimationTrack = (currentAnimator :: any):LoadAnimation(animation) -- load animation from the animator.
			self._janitor:Add(function() -- add track to the janitor so it would stop and destroy it 
				track:Stop() -- stops animation track
				track:Destroy() -- destroys animation track, wow
			end)
			
			if isCamera then -- if child is a camera
				self:_watchFov(track) -- watch for FOV animation marker points
				self:_watchSkip(track) -- and also watch for skip points in the same track
				self._cameraTrack = track -- set the current track to self._cameraTrack
			
			elseif child:GetAttribute("CharacterRig") then -- else if child is a character, checking it by looking for the attribute
				self:_watchFace(track, child) -- watch rig track for face animation marker pointsssss
			end
			
			self:_watchSound(track) -- watch sound markers from all tracks because why not
			table.insert(tracks, track) -- insert to the tracks table the current track
		end
	end
	
	local deadline: number = os.clock() + LOAD_TIMEOUT -- this variable gives 5 seconds timeout for all tracks
	-- wait for the animations to actually load, if track is still not loaded then remove it
	for index = #tracks, 1, -1 do -- iterate through index number backwards from last to first
		-- it iterates like that because of the table.remove ->>> it's a lot safer because it's not skipping any of the existing tracks
		-- because if we're going to do the same thing with "for index, child in tracks do ... `removing track here` end"
		-- it would just start skip the next animation tracks that were "index + 1", because it would shift it back to the current index without proprely checking it, that's why
		local track = tracks[index] -- getting a track from the current index
		while (track.Length == 0) and (os.clock() < deadline) do -- waits until all track is loaded and until the deadline passes
			task.wait() -- infinite wait.
			-- LEBRON JAMES REPORTEDLY USED wait() INSTEAD OF task.wait()
		end
		
		if track.Length == 0 then -- if time passed and loaded track still shows 0 length then...
			warn("[CutsceneController]: animation track has no length") -- warn about it to the client
			table.remove(tracks, index) -- remove track using index from the tracks table that we're returning
		end
	end
	
	-- return all tracks from the function
	return tracks
end

-- private function that loads all skip points from the animation that we're pushed into the function argument
function CutsceneController._loadSkipPoints(self: Controller, animation: Animation)
	table.clear(self._skipPoints) -- each time clear self._skipPoints table if there was already some
	
	local ok, clip = pcall(function() -- use pcall as a guard for getting AnimationClip
		return AnimationClipProvider:GetAnimationClipAsync(animation.AnimationId) -- this should return AnimationClip or KeyframeSequence from it
	end)
	
	-- checks if everything is okay or no. we are as usual just praying for the best
	if (not ok) or (not clip:IsA("KeyframeSequence")) then -- if pcall returned an error or if clip is NOT KeyframeSequence then...
		return warn("[CutsceneController]: camera clip isn't sequence") -- warn about it that camera clip is not a sequence for some reason??
	end
	
	local keyframes = clip:GetKeyframes() :: {Keyframe} -- this gets all keyframes from the clip, no shit
	local points = table.create(#keyframes) -- we're preallocating memory for the skip points time positions so no reallocation would be after
	
	-- this loop is going through all skip point markers and collecting them
	for _, frame in keyframes do -- iterating through keyframes table that we got from the clip
		if not frame:IsA("Keyframe") then -- checks if frame is a keyframe
			continue -- if not, then continue to the next keyframe
		end
		
		for _, marker in frame:GetMarkers() do -- iterating through markers from the current keyframe
			if marker.Name == SKIP_MARKER then -- if marker's name is a skip point constant name, then...
				table.insert(points, frame.Time) -- insert time current frame time position to the points table
				break -- and then breaking the loop so it would iterate through the next keyframe
			end
		end -- there is nothing better than the end between two ends. I'm sorry it's already late for me.
	end
	
	table.sort(points) -- sorting all time positions...
	self._skipPoints = points :: any -- set self._skipPoints as a points table, strict is hell am I right?
end

-- private function that binds camera FOV and camera CFrame to its rig
function CutsceneController._bindCamera(self: Controller)
	if not self._camera then -- if there is no camera then RETURN
		return warn("[CutsceneController]: no camera found") -- WARN IT!!! OR EVEN BETTTER THROW AN ERROR!!!!
	end
	
	do -- what
		-- oh my god how I love fusion, elttob thank you so much for blessing me wih that awesome framework
		-- hydrating the player's camera for smooth FOV changing with spring
		scope:Hydrate(self._camera) { -- hydration begins with a initialized fusion scope
			FieldOfView = self._cleanupScope:Spring( -- oh, that uses self._cleanupScope that I was talking about
				self._currentFov, -- this set the current FOV that was taken from the marker
				self._speed, self._damping -- speed and damping variables are being used here, uhm
			)
		}
		
		self._janitor:Add(function() -- hello janitor, yes yes, do that when I ask you to
			self._camera.FieldOfView = FOV_DEFAULT -- set camera's FOV to default using constant that I've written
			self._camera.CameraType = Enum.CameraType.Custom -- and also set the camera type to custom
		end)
		
		-- when the cutscene starts, camera MUST be scriptable, so it would follow the camera rig, right
		self._camera.CameraType = Enum.CameraType.Scriptable
	end
	
	task.spawn(function() -- spawn new task
		local camera: BasePart? = Strict.BasePart(self._cameraRig:WaitForChild("CameraPart")) -- checks for the main camera part in a rig
		if not camera then -- if no camera part that would be followed was found, then return
			return warn("[CutsceneController]: no camera part found") -- and warn!!
		end
		
		-- we're binding to render step a camera, so it would run a function every render frame
		-- this is made so there wouldn't be any fighting between the main CameraModule and with our cutscene camera
		self._janitor:BindToRenderStep("CutsceneCamera", -- label for bind.
			Enum.RenderPriority.Camera.Value + 2, -- as I know, with this render priority, the function runs after roblox's own camera initialization or whatever it called
			function() -- function that runs each frame after the existing CameraModule, yes.
				self._camera.CFrame = camera.CFrame -- set player's camera CFrame to the camera part that we have in a cutscene, yayayay!!!
			end
		)
	end)
end

-- private function that binds canvas group to Fusion
function CutsceneController._bindCanvas(self: Controller, canvas: CanvasGroup)
	if not canvas then -- checks if canvas is given (it's actually so stupid because canvas isn't optional and of course it would throw an error at runtime)
		return warn("[CutsceneController]: no canvas given") -- warn if no canvas was given
	end

	-- this hydrates canvas group to smoothly change it GroupTransparency
	scope:Hydrate(canvas) { -- we're using basic scope here that is at the top of the file
		GroupTransparency = scope:Spring(self._canvasVisible :: any, 25, 1) -- for some reason new luau type solver throws an error here, so, I've cast value to any
	} -- nothing more to do here

	self._canvas = canvas -- set canvas to the self._canvas variable
	self:_bindSkipButton() -- and then bind skip button after we've initialized the canvas group itself
end

-- private function that binds skip button that located in canvas group that we've already binded
-- it's basically binds button activation, transparency smooth animation and changable text label
function CutsceneController._bindSkipButton(self: Controller)
	if not self._canvas then -- checks if self._canvas exists and set up in table
		return warn("[CutsceneController]: no canvas found") -- warn if nothing was found
	end
	
	-- look for the skip button frame (canvas group) and the invisible button in it
	local skip: CanvasGroup? = Strict.CanvasGroup(self._canvas:WaitForChild("Skip"))
	local button: TextButton? = skip and Strict.TextButton(skip:WaitForChild("Button"))
	
	if not button then -- if no button was found then...
		return warn("[CutsceneController]: no skip button found") -- warn about it
	end
	
	-- we're binding the button here to that Activated signal (I rarely using MouseButton1Down or whatever it called)
	button.Activated:Connect(function() -- if button is activated then...
		if not self._skipEnabled then -- checks if skip enabled boolean is actually true
			return -- if not then return nothing at activation
		end
		
		-- try skipping the cutscene to the next skip point
		self:Skip() -- why is it public, can someone tell me please??
	end)
	
	if skip then -- if skip button main frame exists, then...
		-- look for the TextLabel in it using my Strict module
		local label: TextLabel? = Strict.TextLabel(skip:WaitForChild("Label"))
		if label then -- if label found then run what is in that if statement, if no then continue
			-- I've made so it would change text label's text using fusion, so no fighting between different assignments would happen
			-- (and it's also a lot easier to manipulate and easy to change with one line, than each time look for the label in skip button)
			scope:Hydrate(label) { Text = self._skipLabel } -- hydrating label's text to self._skipLabel value
		end
		
		-- skip button frame smooth transparency animation
		scope:Hydrate(skip) { -- hydrate the main frame!!!! we'll use basic speed and damping for it
			GroupTransparency = scope:Spring(self._skipVisible, 25, 1) -- make so it would watch self._skipVisible value
		}
	end
end

-- private function that updates skip label with "current/total" skip points
-- this is made as a seperate function for multiple usage in code (idk how to explain it properly but you get the idea)
function CutsceneController._updateSkipLabel(self: Controller)
	if not self._cameraTrack then -- checks for the camera animation track
		return -- if it's not found, then return the function
	end

	-- this is guard that checks if there is no skip points markers in the camera track
	if #self._skipPoints == 0 then -- if there is none, then...
		self._skipLabel:set("SKIP") -- set text label to "SKIP"
		return -- and return the function because how are we going to count something that doesn't exist, right?
	end

	local total: number = #self._skipPoints -- local variable for holding count of existing skip points
	local current: number = 0 -- local variable that increases counter and show how many skip points already behind

	local now: number = self._cameraTrack.TimePosition -- gets current time position from the camera track
	-- this iteration made so that it would go through all skip points in the table...
	-- and increase "current" number value if we've passed skip points. it actually rescan all points every call, but whatever, not a problem for us
	for _, point in self._skipPoints do -- iterate through all existing skip points
		-- looks for the skip points that already got passed by camera track's current time position
		if now >= (point - 0.05) then -- (small 0.05 second buffer so a point counts as passed a frame early)
			current += 1 -- increase skip point counter number variable
		end
	end

	-- set skip text label to the "SKIP current/total" with fusion value
	self._skipLabel:set(`SKIP {current}/{total}`) -- so it show skip point that we've passed and total amount of skip points in the cutscene
end

-- private function that watches for all FOV markers in the given track that we gave in argument
-- this is made so animators would freely change camera's fov in the animation editor (moon animator) itself
function CutsceneController._watchFov(self: Controller, track: AnimationTrack)
	-- connect janitor so it would watch if FOV_MARKER got reached in the track; returns value string that in marker is written
	self._janitor:Connect(track:GetMarkerReachedSignal(FOV_MARKER), function(value: string)
		-- value for FOV should be written like this: "Value, Speed, Damping" -> "90, 25, 1"
		-- this built-in "string.split" function splits string to three segments that animator wrote in the marker value
		local segments = string.split(value, ",") -- so, this returns basically table: {90, 25, 1} :: {string}
		local fov: number? = tonumber(segments[1]) -- get FOV value that was written in marker string value, and return it as number
		
		if #segments > 3 then -- if there is more than 3 segments in marker value, then...
			return warn("[CutsceneController]: too many fov marker segments") -- warn about it and return function, because only "<= 3" segments are appliable
		end
	
		-- this is basically sets both speed and damping to what we have in marker value
		self._speed:set(tonumber(segments[2]) or FOV_SPEED_DEFAULT) -- set speed to segment or if there is no speed second segment, use fallback default value
		self._damping:set(tonumber(segments[3]) or FOV_DAMPING_DEFAULT) -- set damping to segment or if there is no damping third segment, use fallback default value
		
		if fov then -- if there is FOV number found in segment
			self._currentFov:set(fov) -- then set it in fusion value that got binded in private bindCamera function
		end
	end)
end

-- private function that watches for all FACE markers in the given track that we gave in argument
-- this is ALSO made so animators would easily change rig's face that we gave in second argument
function CutsceneController._watchFace(self: Controller, track: AnimationTrack, rig: Model)
	local head: MeshPart? = Strict.MeshPart(rig:WaitForChild("Head")) -- looks for the head mesh part in the humanoid rig
	local face: Decal? = head and Strict.Decal(head:WaitForChild("face")) -- and then looks for the "face" decal in head
	
	if (not face) or (not face:IsA("Decal")) then -- guard that checks if face exists and if it's a decal
		return warn("[CutsceneController]: no face decal found") -- throw a warn about it if neither
	end
	
	local original: Content = face.ColorMapContent -- set this local varialbe to default rig face texture that was already initialized
	self._janitor:Add(function() -- say janitor to set rig's face to original decal content
		face.ColorMapContent = original -- set it back to original face
	end)
	
	-- connect janitor so it would watch if FACE_MARKER got reached and then change it to the face that we need
	self._janitor:Connect(track:GetMarkerReachedSignal(FACE_MARKER), function(value: string) -- gives us a marker value
		if string.lower(value) == "original" then -- decal can be also set to original face without writing it's id
			face.ColorMapContent = original -- so, if value is "original" no matter the casing, it would set it back to original content
			return -- and then return it
		end

		-- try to get id with and without the "rbxassetid://" prefix
		-- this is made because Content.fromAssetId requires raw number, so that's why all this stripping and converts to number
		local id = tonumber(string.match(value, "^rbxassetid://(%d+)") or value) -- we're using string.match to try get just numbers or fallback to value
		if not id then -- if no id was found or tonumber failed, then...
			return warn("[CutsceneController]: invalid face id") -- warn about it and return
		end
		
		-- set decal's ColorMapContent to raw asset id number that we already got
		face.ColorMapContent = Content.fromAssetId(id)
	end)
end

-- private function that watches for all SOUND markers in the given track that we game in argument
-- this is ALSO ALSO made so animators would easily add sound effects to cutscenes in the animation editor
function CutsceneController._watchSound(self: Controller, track: AnimationTrack)
	-- connect janitor so it would watch if SOUND_MAKRER got reached and play the given sound effect
	self._janitor:Connect(track:GetMarkerReachedSignal(SOUND_MARKER), function(value: string)
		-- so this is basic string.gsub find pattern that can remove any trailing spaces
		local name = string.gsub(value, "^%s*(.-)%s*$", "%1") -- it removes whitespaces at start/end, captures the content and return only it
		local template = SoundEffects:FindFirstChild(name, true) -- it recusively looks for the given sound in "SoundEffects" sound group using the given name
		
		if (not template) or (not template:IsA("Sound")) then -- if template wasn't found or if it's not a "Sound" instance then return
			return warn(`[CutsceneController]: "{value}" sound effect wasn't found`) -- and also warn about it
		end
		
		local sound: Sound = template:Clone() -- after that, we need to clone the sound effect that we found
		sound.Parent = self._playingSounds -- set it's parent to self._playingSounds SoundGroup instance
		sound:Play() -- and then finally play that sound!!!
		
		self._janitor:Add(sound) -- add sound to the janitor so if for example sound started playing at the end, it would destroy itself after cutscene ends
		sound.Ended:Once(function() -- and also make so that sound.Ended signal connects once so it would destroy the sound after it ends
			sound:Destroy() -- cloned sound got destroyed in self._playingSounds
		end)
	end)
end

-- private function that watches for all skip points in the track (specifically in camera animation track)
function CutsceneController._watchSkip(self: Controller, track: AnimationTrack)
	-- connect janitor so it would watch if SKIP_MARKER got reached
	self._janitor:Connect(track:GetMarkerReachedSignal(SKIP_MARKER), function()
		self:_updateSkipLabel() -- calls private updateSkipLabel function so it would update current skip point
	end)
end

export type Controller = typeof(CutsceneController)
return CutsceneController