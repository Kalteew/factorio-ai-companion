local u = require("commands.init")

local function nearest_logistic_entity(surface, position, radius)
  local closest, distance = nil, math.huge
  for _, entity in ipairs(surface.find_entities_filtered{position = position, radius = radius}) do
    if entity.valid and entity.type ~= "character" and entity.get_logistic_point then
      local dx = entity.position.x - position.x
      local dy = entity.position.y - position.y
      local d = dx * dx + dy * dy
      if d < distance then closest, distance = entity, d end
    end
  end
  return closest
end

local function point_for(entity)
  local ok, points = pcall(function() return entity.get_logistic_point() end)
  if not ok or not points then return nil end
  if points.owner then return points end
  return points[1]
end

u.register("logistics_set_requests", function(args)
  u.safe_command(function()
    local id, companion = u.find_companion(args.companionId)
    if not id then u.not_found(); return end
    local x, y = tonumber(args.x), tonumber(args.y)
    if not x or not y then u.reject("Invalid coordinates") end
    local target = nearest_logistic_entity(companion.entity.surface, {x = x, y = y}, tonumber(args.radius) or 2)
    if not target then u.json_response({id = id, error = "No logistic entity"}); return end
    local point = point_for(target)
    if not point then u.json_response({id = id, error = "Entity has no logistic point"}); return end
    local sections = point.sections or {}
    local section = sections[tonumber(args.section) or 1]
    if not section then
      local ok_add, added = pcall(function() return point.add_section() end)
      if ok_add then section = added end
    end
    if not section then u.json_response({id = id, error = "No editable logistic section"}); return end
    if not section.is_manual then u.json_response({id = id, error = "Logistic section is not manual"}); return end
    if args.clearAll then
      for slot = section.filters_count or 0, 1, -1 do section.clear_slot(slot) end
    end
    local changed = 0
    for slot, request in ipairs(args.requests or {}) do
      local filter = {
        -- Factorio 2.0 requires an explicit quality when min is non-zero. Normal
        -- is the least surprising base-game default; Space Age callers can pass
        -- another quality explicitly.
        value = {type = "item", name = request.item, quality = request.quality or "normal"},
        min = tonumber(request.min) or tonumber(request.count) or 0,
        max = tonumber(request.max) or tonumber(request.count) or nil,
      }
      local ok_set, existing = pcall(function() return section.set_slot(slot, filter) end)
      if not ok_set then u.json_response({id = id, error = "Could not set logistic request: " .. tostring(existing)}); return end
      changed = changed + 1
    end
    u.json_response({id = id, entity = target.name, section = section.index, changed = changed})
  end)
end)

return {}
