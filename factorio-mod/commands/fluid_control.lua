local u = require("commands.init")

local function nearest(surface, position, radius)
  local closest, distance = nil, math.huge
  for _, entity in ipairs(surface.find_entities_filtered{position = position, radius = radius}) do
    local ok_count, count = pcall(function() return entity.fluids_count end)
    if entity.valid and ok_count and (tonumber(count) or 0) > 0 then
      local dx = entity.position.x - position.x
      local dy = entity.position.y - position.y
      local d = dx * dx + dy * dy
      if d < distance then closest, distance = entity, d end
    end
  end
  return closest
end

local function extract(entity, name, amount, temperature)
  local ok, removed = pcall(function()
    local fluid = {name = name, amount = amount}
    if temperature then fluid.temperature = temperature end
    return entity.extract_fluid(fluid)
  end)
  if ok and type(removed) == "number" then
    return removed, {name = name, amount = removed, temperature = temperature}
  end
  local count = tonumber(entity.fluids_count) or 0
  for index = 1, count do
    local ok_fluid, fluid = pcall(function() return entity.get_fluid(index) end)
    if ok_fluid and fluid and fluid.name == name then
      local ok_removed, value = pcall(function() return entity.remove_fluid(index, amount) end)
      if ok_removed and type(value) == "table" then return tonumber(value.amount) or 0, value end
      if ok_removed and type(value) == "number" then
        return value, {name = name, amount = value, temperature = temperature}
      end
      local ok_box, current = pcall(function() return entity.fluidbox[index] end)
      if ok_box and current and current.name == name then
        local removed = math.min(tonumber(current.amount) or 0, amount)
        if removed > 0 then
          local remaining = (tonumber(current.amount) or 0) - removed
          local replacement = remaining > 0 and {name = name, amount = remaining, temperature = current.temperature} or nil
          local ok_write = pcall(function() entity.fluidbox[index] = replacement end)
          if ok_write then return removed, {name = name, amount = removed, temperature = current.temperature} end
        end
      end
    end
  end
  return 0, nil
end

u.register("fluid_transfer", function(args)
  u.safe_command(function()
    local id, companion = u.find_companion(args.companionId)
    if not id then u.not_found(); return end
    local source = nearest(companion.entity.surface, {x = tonumber(args.fromX), y = tonumber(args.fromY)}, tonumber(args.radius) or 2)
    local target = nearest(companion.entity.surface, {x = tonumber(args.toX), y = tonumber(args.toY)}, tonumber(args.radius) or 2)
    if not source or not target then u.json_response({id = id, error = "Fluid endpoint not found"}); return end
    local reach = companion.entity.reach_distance or 10
    if u.distance(companion.entity.position, source.position) > reach or u.distance(companion.entity.position, target.position) > reach then
      u.json_response({id = id, error = "Too far"}); return
    end
    local amount = math.max(0, tonumber(args.amount) or 0)
    if amount <= 0 then u.reject("Amount must be positive") end
    local extracted, fluid = extract(source, args.fluid, amount, args.temperature)
    if extracted <= 0 or not fluid then u.json_response({id = id, error = "No fluid available"}); return end
    local ok_insert, inserted = pcall(function() return target.insert_fluid(fluid) end)
    if not ok_insert then
      source.insert_fluid(fluid)
      u.json_response({id = id, error = "Target cannot accept fluid: " .. tostring(inserted)}); return
    end
    inserted = tonumber(inserted) or 0
    if inserted < extracted then
      local rollback = {name = args.fluid, amount = extracted - inserted}
      if fluid.temperature then rollback.temperature = fluid.temperature end
      pcall(function() source.insert_fluid(rollback) end)
    end
    u.json_response({id = id, fluid = args.fluid, requested = amount, extracted = extracted, inserted = inserted,
      source = source.name, target = target.name})
  end)
end)

return {}
