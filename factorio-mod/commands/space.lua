local u = require("commands.init")

local function safe_field(object, field)
  local ok, value = pcall(function() return object[field] end)
  return ok and value or nil
end

local function location_name(value)
  return value and (safe_field(value, "name") or tostring(value)) or nil
end

local function surface_snapshot(surface)
  local planet, platform = safe_field(surface, "planet"), safe_field(surface, "platform")
  return {
    name = surface.name,
    index = surface.index,
    planet = planet and location_name(planet) or nil,
    platform = platform and {index = safe_field(platform, "index"), name = safe_field(platform, "name"),
      state = safe_field(platform, "state"), paused = safe_field(platform, "paused")} or nil,
  }
end

u.register("space_snapshot", function(args)
  u.safe_command(function()
    local id, companion = u.find_companion(args.companionId)
    if not id then u.not_found(); return end
    local force = companion.entity.force
    local surfaces, platforms = {}, {}
    for _, surface in pairs(game.surfaces) do surfaces[#surfaces + 1] = surface_snapshot(surface) end
    table.sort(surfaces, function(a, b) return a.index < b.index end)
    local force_platforms = safe_field(force, "platforms")
    if force_platforms then
      for index, platform in pairs(force_platforms) do
        platforms[#platforms + 1] = {
          index = tonumber(index), name = safe_field(platform, "name"), state = safe_field(platform, "state"),
          paused = safe_field(platform, "paused"), completed_trips = safe_field(platform, "completed_trips"),
          space_location = location_name(safe_field(platform, "space_location")),
          last_visited_space_location = location_name(safe_field(platform, "last_visited_space_location")),
        }
      end
    end
    table.sort(platforms, function(a, b) return (a.index or 0) < (b.index or 0) end)
    u.json_response({id = id, surfaces = surfaces, platforms = platforms,
      space_age_available = game.planets ~= nil, force = force.name})
  end)
end)

return {}
