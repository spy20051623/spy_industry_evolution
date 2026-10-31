-- Adapted from native subventions.css.lua; only recipe selectors renamed.
local color_util = require "::/gui/main/color_util.tl"
local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
	local result = { }

	local a = ssu.makeAdder(result)

	local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data
	local transparency = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/transparency.gres")).data

	a("R::SpyGrowthTaskCard", {
		gravity = { -1, -1 },
	})
	a("R::SpyGrowthTaskCard R::Component!card-area", {
		backgroundImage1 = {
			fileName = "::/gui/entity_window/design/tabless_container_surface.tga",
			horizontal = { 0, 8, 24, 32 },
			vertical = { 0, 8, 24, 32 }
		},
		padding = { 8, 8, 8, 8 },
		backgroundColor1 = colorDefault.BaseLight,
	})

	a("R::SpyGrowthTaskCard BoxLayout!task-box", {
		gravity = { -1, -1 },
		innerSpacing = { 8, 8 },
	})

	a("R::SpyGrowthTaskCard TextView!card", {
		size = { 410, -1 },
		textAutoWrap = true,
	})

	a("R::SpyGrowthTaskCard TextView!list-text", {
		textAutoWrap = true,
		size = { 372, -1 },
	})

	a([[R::SpyGrowthTaskCard ImageView!label,
		R::SpyGrowthTaskCard Button!label]], {
		size = { -1, 24 },
		padding = { 2, 2, 2, 2 },
		margin = { 0, 8, 0, 0 },
	})

	a([[R::SpyGrowthTaskCard ImageView!cargo-to-deliver,
		R::SpyGrowthTaskCard TextView!cargo-to-deliver-count]], {
		size = { -1, 24 },
		padding = { 2, 2, 2, 2 },
		margin = { 0, 0, 0, 0 },
	})

	a("R::SpyGrowthTaskCard ProgressBar", {
		margin = { 2, 8, 2, 8 },
	})

	a([[R::SpyGrowthTaskAction,
		R::SpyGrowthTaskAction > BoxLayout]], {
		gravity = { -1, -1 },
	})
	a("R::SpyGrowthTaskAction", {
		margin = { 8, 0, 0, 0 },
	})
	a("R::SpyGrowthTaskAction > BoxLayout", {
		innerSpacing = { 8, 8 },
	})

	a("R::SpyGrowthTaskAction Button", {
		gravity = { -1, -1 },
	})

	a([[R::SpyGrowthTaskAction ImageView!subsidy-completed,
		R::SpyGrowthTaskAction ImageView!subsidy-failed]], {
		gravity = { 0.5, 0.5 },
		size = { 48, 48 },
	})
	a("R::SpyGrowthTaskAction ImageView!subsidy-completed", {
		color = colorDefault.Positive,
	})
	a("R::SpyGrowthTaskAction ImageView!subsidy-failed", {
		color = colorDefault.Negative,
	})

	-- Copied from entity_window.css.lua: EntityWindowContent Button.
	a("R::SpyGrowthTaskEntityContent Button", {
		padding = { 3, 4, 3, 4 },
		backgroundImage1 = {
			fileName = "::/gui/entity_window/design/card_surface.tga",
			horizontal = { 0, 6, 26, 32 },
			vertical = { 0, 6, 26, 32 }
		},
		borderImage = {
			fileName = "::/gui/entity_window/design/card_contour.tga",
			horizontal = { 0, 6, 26, 32 },
			vertical = { 0, 6, 26, 32 }
		},
	})
	a("R::SpyGrowthTaskAction BoxLayout!task-action-buttons", {
		gravity = { -1, -1 },
		innerSpacing = { 8, 8 },
	})
	return result
end
