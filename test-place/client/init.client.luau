--!strict

const Players = game:GetService("Players")
const PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const CutsceneController = require(ReplicatedStorage.Shared.CutsceneController)
const Promise = require(ReplicatedStorage.Shared.Packages.Promise)

const CUTSCENE_SCREEN = script:WaitForChild("CutsceneScreen") :: ScreenGui
const CUTSCENE_CANVAS = CUTSCENE_SCREEN:WaitForChild("Canvas") :: CanvasGroup

const RunService = game:GetService("RunService")
const ENABLED_IN_STUDIO: boolean = true

task.delay(2, function() -- starts after 2 seconds in the game
    -- if it ran in studio and "ENABLED_IN_STUDIO" constant boolean is false
	if (RunService:IsStudio()) and (not ENABLED_IN_STUDIO) then
		return -- then return and cancel it
	end

    CUTSCENE_SCREEN.Enabled = true -- set cutscene screen gui enabled to true
    CUTSCENE_SCREEN.Parent = PlayerGui -- move it to LocalPlayer.PlayerGui

    -- new promise for calling cutscene controller and starting the cutscene
	Promise.new(function(resolve: () -> (), reject)
		local ok, err = pcall(function()
			CutsceneController:Start(CUTSCENE_CANVAS)
		end)
		
		if (not ok) and (err) then
			warn("[CutsceneClient] initialization failed: "..tostring(err))
			return reject()
		end
		
		return resolve()
	end)
		:andThen(function()
			CutsceneController:Play()
		end)
		:catch(warn)
end)