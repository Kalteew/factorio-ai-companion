local u = require("commands.init")

local function is_target(entity)
  return entity.valid and entity.type ~= "character" and entity.type ~= "resource" and entity.type ~= "item-entity"
end

u.register("maintenance_order", function(args)
  u.safe_command(function()
    local id, companion = u.find_companion(args.companionId)
    if not id then u.not_found(); return end
    local x1, y1 = tonumber(args.x1), tonumber(args.y1)
    local x2, y2 = tonumber(args.x2), tonumber(args.y2)
    local left, right = math.min(x1, x2), math.max(x1, x2)
    local top, bottom = math.min(y1, y2), math.max(y1, y2)
    if right - left > 64 or bottom - top > 64 then u.reject("Maintenance area is limited to 64 tiles") end
    if args.action == "upgrade" and not args.target then u.reject("Upgrade target is required") end
    local center = {x = (left + right) / 2, y = (top + bottom) / 2}
    if u.distance(companion.entity.position, center) > 128 then u.json_response({id = id, error = "Too far"}); return end
    local action = args.action
    local changed, skipped = 0, 0
    for _, entity in ipairs(companion.entity.surface.find_entities_filtered{area = {{left, top}, {right, bottom}}, force = companion.entity.force}) do
      if is_target(entity) then
        local ok, result = pcall(function()
          if action == "deconstruct" then return entity.order_deconstruction(companion.entity.force)
          elseif action == "cancel_deconstruct" then return entity.cancel_deconstruction(companion.entity.force) or true
          elseif action == "upgrade" then
            return entity.order_upgrade{target = args.target, force = companion.entity.force}
          elseif action == "cancel_upgrade" then return entity.cancel_upgrade(companion.entity.force) or true
          end
          return false
        end)
        if ok and result then changed = changed + 1 else skipped = skipped + 1 end
      end
    end
    u.json_response({id = id, action = action, changed = changed, skipped = skipped,
      area = {left = left, top = top, right = right, bottom = bottom}})
  end)
end)

return {}
