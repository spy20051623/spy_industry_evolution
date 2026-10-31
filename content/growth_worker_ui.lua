-- Keep the vanilla worker row's displayed threshold consistent with the
-- unchanged simulation threshold after adding jobs.
local M={}
local core=ug_require("spy_industry_evolution::/growth_core.lua")
function M.install()
  local industry=ug_require("::/gui/entity_window/industry_react_util.tl")
  if industry.spyGrowthWorkerRowInstalled then return end
  industry.spyGrowthWorkerRowInstalled=true
  local react=ug_require("::/gui/main/react.lua")
  local builtin=ug_require("::/gui/main/builtin.lua")
  local engine=ug_require("::/gui/main/engine_react_util.tl")
  local workers=ug_require("::/industries/industry_productivity_util.tl")
  local CT=api.type.ComponentType
  -- Same widget trees as Urban Games' ProgressDisplay and IconLabelIndicator,
  -- restricted to the worker row's tooltip/value and icon/label arguments.
  -- Use these on every platform: some console builds do not export those
  -- helpers. Recipe-specific styles mirror the native rules in growth.css.lua.
  local progressCompat=react.RegisterRecipe("SpyGrowthWorkerProgressDisplay",function(p)
    return builtin.BoxLayout{orientation=builtin.type.Orientation.Horizontal,children={
      builtin.FloatingLayout{children={
        builtin.FloatingLayoutChild{h=-1,v=-1,item=builtin.ProgressBar{
          meta={class="extra-progress, font-scale-annotation",tooltip=p.tooltip},value=0}},
        builtin.FloatingLayoutChild{h=-1,v=-1,item=builtin.ProgressBar{
          meta={class="font-scale-annotation",tooltip=p.tooltip},value=p.value}},
      }},
    }}
  end)
  local indicatorCompat=react.RegisterRecipe("SpyGrowthWorkerIndicator",function(p)
    react.setStyleClasses("hud-icon-layer")
    return builtin.BoxLayout{orientation=builtin.type.Orientation.Vertical,children={
      builtin.Component{meta={class="icon-label-indicator"},layout=builtin.FloatingLayout{children={
        builtin.FloatingLayoutChild{h=1,v=1,item=builtin.Component{meta={class="iconlabelindicator-size"}}},
        builtin.FloatingLayoutChild{h=0.5,v=0.1,item=builtin.ImageView{
          meta={class="iconlabelindicator-icon-size"},path=p.iconPath,scaling=builtin.type.ImageViewScaling.AutoFit}},
        builtin.FloatingLayoutChild{h=0.5,v=1,item=builtin.TextView{
          meta={class="iconlabelindicator-label, font-scale-annotation"},text=p.label}},
      }}},
    }}
  end)
  local progressCell=react.RegisterRecipe("SpyGrowthWorkplacesBoosterProgressBar",function(p)
    return builtin.BoxLayout{orientation=builtin.type.Orientation.Vertical,children={
      progressCompat{tooltip=p.tooltip,value=p.value},
    }}
  end)
  local function parameters(e)
    local ind=api.engine.getComponent(e,CT.INDUSTRY)
    local con=ind and api.engine.getComponent(ind.construction,CT.CONSTRUCTION)
    return con and (con.params_native and con.params_native:asTable() or con.params)
  end
  local function visitorCount(e,par,pc)
    local nativeCount=#workers.getVisitors(e)
    if not par or not par.spy_growth_id or
        ((par.spy_growth_levels or {}).jobs or 0)==0 then return nativeCount end
    local id=api.engine.system.gameScriptSystem.getEntityForGameScript("spy_industry_evolution::/growth.gs")
    local script=id and id>=0 and api.engine.getComponent(id,CT.GAME_SCRIPT)
    local state=script and (script.state_native and script.state_native:asTable() or script.state)
    local factory=state and state.factories and state.factories[par.spy_growth_id]
    local time=api.engine.getComponent(api.engine.util.getWorld(),CT.GAME_TIME)
    local tracked=time and core.workerVisitCount(factory,time.gameTime,workers.workersTimeIntervalMax,pc.capacity)
    return tracked or nativeCount
  end
  local row=react.RegisterWrapperRecipe("SpyGrowthWorkerRow",builtin.Row,function(p)
    local state=engine.useStepState(function()
      local par=parameters(p.entity)
      local pc=api.engine.getComponent(p.entity,CT.PERSON_CAPACITY)
      return {count=visitorCount(p.entity,par,pc),
        needed=math.ceil((par and par.spy_growth_jobs_base or pc.capacity)*workers.RequiredWorkersFractionForBoost),
        boost=workers.getPersonCapacityPotentialBoost(p.entity)}
    end):old()
    local count=state.count.."/"..state.needed
    local fraction=state.needed>0 and math.min(1,state.count/state.needed) or 0
    local function cell(node)
      return builtin.Component{meta={class=p.boosted and "boosted" or ""},layout=builtin.BoxLayout{
        orientation=builtin.type.Orientation.Horizontal,children={node}}}
    end
    local progress=progressCell{tooltip=count,value=fraction}
    local boostLabel="+"..api.util.toStringPercentPrecision(state.boost-1,0)
    local boostIcon="::/gui/entity_window/icons/building_industry.tga"
    local indicator=indicatorCompat{
      meta={class="boost-factor-indicator"},iconPath=boostIcon,label=boostLabel}
    return builtin.Row{cells={
      cell(builtin.BoxLayout{orientation=builtin.type.Orientation.Horizontal,children={
        industry.IconAndLabelWidget{icon="::/gui/entity_window/icons/symbol_person.tga",iconTooltip=_("Workers"),count=count,countTooltip=count}}}),
      cell(progress),
      cell(builtin.BoxLayout{orientation=builtin.type.Orientation.Horizontal,children={indicator}}),
      cell(builtin.ImageView{meta={class="boost-tick-icon"},path="::/gui/entity_window/icons/circle_check.tga"}),
    }}
  end)
  local original=industry.WorkplacesBoosterRow
  industry.WorkplacesBoosterRow=function(p)
    local par=parameters(p.entity)
    if par and par.spy_growth_jobs_base then return row(p) end
    return original(p)
  end
end
return M
