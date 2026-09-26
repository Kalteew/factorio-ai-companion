local u = require("commands.init")

local function nearest(surface, position, radius)
  local closest, distance = nil, math.huge
  for _, entity in ipairs(surface.find_entities_filtered{position = position, radius = radius}) do
    if entity.valid and entity.type ~= "character" and entity.type ~= "resource"
      and entity.type ~= "tree" and entity.type ~= "corpse" then
      local dx = entity.position.x - position.x
      local dy = entity.position.y - position.y
      local d = dx * dx + dy * dy
      if d < distance then closest, distance = entity, d end
    end
  end
  return closest
end

local function connector(entity, wire)
  local ids = defines.wire_connector_id or {}
  local id = wire == "green" and ids.circuit_green or ids.circuit_red
  if id == nil then return nil end
  local ok, result = pcall(function() return entity.get_wire_connector(id, true) end)
  return ok and result or nil
end

u.register("circuit_connect", function(args)
  u.safe_command(function()
    local id, companion = u.find_companion(args.companionId)
    if not id then u.not_found(); return end
    local a_pos = {x = tonumber(args.x1), y = tonumber(args.y1)}
    local b_pos = {x = tonumber(args.x2), y = tonumber(args.y2)}
    if not a_pos.x or not a_pos.y or not b_pos.x or not b_pos.y then u.reject("Invalid coordinates") end
    local radius = tonumber(args.radius) or 2
    local first, second = nearest(companion.entity.surface, a_pos, radius), nearest(companion.entity.surface, b_pos, radius)
    if not first or not second then u.json_response({id = id, error = "Circuit endpoint not found"}); return end
    local reach = companion.entity.reach_distance or 10
    if u.distance(companion.entity.position, first.position) > reach
      or u.distance(companion.entity.position, second.position) > reach then
      u.json_response({id = id, error = "Too far"}); return
    end
    local wire = args.wire or "red"
    if wire ~= "red" and wire ~= "green" then u.reject("Wire must be red or green") end
    local left, right = connector(first, wire), connector(second, wire)
    if not left or not right then u.json_response({id = id, error = "Entities have no " .. wire .. " circuit connector"}); return end
    local ok, changed = pcall(function()
      if args.disconnect then return left.disconnect_from(right) end
      return left.connect_to(right, true)
    end)
    if not ok then u.json_response({id = id, error = "Circuit operation failed: " .. tostring(changed)}); return end
    u.json_response({id = id, wire = wire, disconnect = args.disconnect == true, changed = changed,
      first = first.name, second = second.name})
  end)
end)

return {}
