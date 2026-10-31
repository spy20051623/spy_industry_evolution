local react=ug_require("::/gui/main/react.lua")
local builtin=ug_require("::/gui/main/builtin.lua")
local windowUtil=ug_require("::/gui/entity_window/entity_window_util.tl")
local windows=ug_require("::/gui/entity_window/make_entity_window.tl")
local util=ug_require("::/scripts/util.tl")
local ui=ug_require("spy_industry_evolution::/growth_ui.script.lua")

local GrowthTab=react.RegisterRecipe("SpyIndustryGrowthTab",function(param)
  local con=api.engine.getComponent(param.keyEntity,api.type.ComponentType.CONSTRUCTION)
  local industry
  for _,entity in ipairs(con and con.subconstructions or {}) do
    if api.engine.getComponent(entity,api.type.ComponentType.INDUSTRY) then industry=entity;break end
  end
  local children={}
  if industry then children[1]=ui.Panel{entityId=industry,gameCtx=param.gameCtx,showCalloutOnRightSide=false} end
  -- This is the top content in a tab, matching industry/station-group pages.
  -- The native first flag selects the straight corner below the tab header.
  return builtin.BoxLayout{children={windowUtil.ContentWidgetScrollContainer(children,true)}}
end)

local function entityWindowFn(capture,entity,tag,gameCtx,isMapEditor,isSandboxMode,setActionFnAndProxy,closeConditionAndProxy)
  local result
  if capture and capture.original then
    result=util.useFn(capture.original)(capture.originalParams,entity,tag,gameCtx,isMapEditor,isSandboxMode,
      setActionFnAndProxy,closeConditionAndProxy)
    -- Preserve custom windows that do not use the game's construction tabs.
    if result.recipe~=windows.ConstructionWindow then return result end
  else
    local action=windows.makeSetActionFnWithCombinedKey(windows.ConstructionWindow,setActionFnAndProxy)
    result={recipe=windows.ConstructionWindow,param={meta={tag=tag.."con"},keyEntity=entity,gameCtx=gameCtx,
      isMapEditor=isMapEditor,isSandboxMode=isSandboxMode,setActionFn=action.fn,setActionFn_compareProxy=action.proxy},
      fallbackTitle=_("growth_title"),replacedEntity=entity}
  end
  closeConditionAndProxy=closeConditionAndProxy or {nil,nil}
  local tabs=result.param.customTabs or {};result.param.customTabs=tabs
  tabs[#tabs+1]={entity=entity,name=_("growth_tab_title"),description=_("growth_tab_title"),subconstructionIndex=-1,sortKey=6001,
    customTabData={recipe=GrowthTab,param={meta={tag=tag.."growth"},keyEntity=entity,gameCtx=gameCtx},
      fallbackTitle=_("growth_title"),autoCloseCondition=closeConditionAndProxy[1],autoCloseCondition_compareProxy=closeConditionAndProxy[2]}}
  result.autoCloseCondition=closeConditionAndProxy[1]
  result.autoCloseCondition_compareProxy=closeConditionAndProxy[2]
  return result
end
function data() return {entityWindowFn=entityWindowFn} end
