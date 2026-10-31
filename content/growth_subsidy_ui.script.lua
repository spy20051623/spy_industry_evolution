local core=ug_require("spy_industry_evolution::/growth_core.lua")
local subventions=ug_require("::/game_mechanics/subventions/subvention_util.tl")
local industryUtil=ug_require("::/gui/main/industry_util.tl")
local CT=api.type.ComponentType
local installed=false

local function growthState()
  local e=api.engine.system.gameScriptSystem.getEntityForGameScript("spy_industry_evolution::/growth.gs")
  if not e or e<0 or not api.engine.entityExists(e) then return nil end
  local c=api.engine.getComponent(e,CT.GAME_SCRIPT)
  return c and (c.state_native and c.state_native:asTable() or c.state)
end

local function install()
  if installed then return end
  installed=true
  -- Bonus production adds output stocks, not new cargo types. The vanilla
  -- supplier enumerator reports every stock, and the town subsidy turns each
  -- report into another map icon. Deduplicate before its flow is constructed.
  local forEachTownSupplier=industryUtil.forEachTownSupplier
  industryUtil.forEachTownSupplier=function(town,callback)
    local seen={}
    return forEachTownSupplier(town,function(industry,cargo)
      local cargos=seen[industry]
      if not cargos then cargos={};seen[industry]=cargos end
      if not cargos[cargo] then
        cargos[cargo]=true
        callback(industry,cargo)
      end
    end)
  end
  local original=subventions.makeDefaultCardData
  subventions.makeDefaultCardData=function(task,...)
    local card=original(task,...)
    if not card or not (core.factorySubsidies[task.id] or core.townSubsidies[task.id]) then return card end
    local state=growthState()
    -- Seeded pre-enable tasks remain vanilla; unseen tasks are eligible only
    -- after initialization, matching the engine's new-task classification.
    if not state or not state.initialized or state.uninstall then return card end
    local mark=(state.subsidySeen or {})[core.subsidyKey(task)]
    if mark=="old" then return card end
    local target
    if core.factorySubsidies[task.id] then
      target=core.subsidyTarget(task)
      if not target or not api.engine.entityExists(target) or
        not api.engine.getComponent(target,CT.INDUSTRY) then return card end
    end
    card=core.copy(card)
    if core.townSubsidies[task.id] then
      card.complete[#card.complete+1]={text=string.format(_("growth_town_subsidy_reward"),core.townSubsidyReward)}
    else
      local name=api.engine.util.getEntityName(target) or _("Unnamed Industry")
      card.complete[#card.complete+1]={text=string.format(_("growth_subsidy_reward"),name,core.subsidyReward)}
    end
    return card
  end
end

-- React plugins execute in the same Lua context as the vanilla card recipes.
-- Game-script guiUpdate runs in a separate context and cannot install this hook.
local react=ug_require("::/gui/main/react.lua")
local builtin=ug_require("::/gui/main/builtin.lua")
local widgets=ug_require("::/gui/game_bar/game_bar_widgets.tl")
local Hook=react.RegisterPluginRecipe(widgets.GameBarInfoDisplayExtension,"SpyGrowthSubsidyRewardHook",function()
  install()
  react.onStep(function()
    ug_require("spy_industry_evolution::/growth_ui.script.lua").pollFailures()
  end)
  return builtin.BoxLayout{children={}}
end)
function data() return {SubsidyRewardHook=Hook} end
