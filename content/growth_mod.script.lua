function data()
  return {run=function()
    addModifier("loadConstruction",function(fileName,resource)
      if resource.isIndustry and resource.updateScript and resource.updateScript.fileName then
        local ref=resource.updateScript.fileName
        if not ref:find("::",1,true) and ref:sub(1,1)~="/" then
          ref=(fileName:match("^(.*[/])") or "")..ref
        elseif ref:sub(1,1)=="/" then
          ref=(fileName:match("^(.-)::") or "").."::"..ref
        end
        -- Vanilla postRun filters climate-specific stocks/rules at this exact
        -- top-level path. Keep it visible instead of nesting the capture table.
        local capture={}
        for k,v in pairs(resource.updateScript.params or {}) do capture[k]=v end
        capture.spy_growth_original=ref
        resource.updateScript={fileName="spy_industry_evolution::/growth_construction.script@update",params=capture}
        local window=resource.entityWindowScript
        local windowCapture={}
        if window and window.fileName and window.fileName~="" then
          local original=window.fileName
          if not original:find("::",1,true) and original:sub(1,1)~="/" then
            original=(fileName:match("^(.*[/])") or "")..original
          elseif original:sub(1,1)=="/" then
            original=(fileName:match("^(.-)::") or "").."::"..original
          end
          windowCapture.original=original;windowCapture.originalParams=window.params
        end
        resource.entityWindowScript={fileName="spy_industry_evolution::/growth_window.script@entityWindowFn",params=windowCapture}
      end
      return resource
    end)
  end}
end
