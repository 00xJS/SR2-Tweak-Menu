-- Browse SR2's wearables by slot, then item, variant and wear option.
return function(F, G)
  local clothing = F.data("clothing")
  local outfits = F.data("outfits")
  local playback = require("emote_playback")
  local barber = require("hair")
  local native_walk = require("native_walk")
  local body = require("face_body")
  local looks = require("looks")
  local rows, face, hair, clothes = {}, {}, {}, {}
  local hair_areas = {
    { "Head Hair", 0 }, { "Beard", 2 }, { "Mustache", 1 },
    { "Sideburns", 3 }, { "Eyebrows", 4 },
  }
  local native_slots = {}
  for _, slot in ipairs(hair_areas) do
    local label, area = slot[1], slot[2]
    native_slots[label] = true
    hair[#hair + 1] = { label = label, kind = "page", help = "Browse styles with live previews.",
      open = function(_, p) return barber.page(F, p, area, label) end }
  end
  F.after_updates[#F.after_updates + 1] = function(p)
    barber.update(p)
    body.enabled = F.enabled
    body.update(p)
    looks.update(p)
    if F.hair_preview then F.hair_preview() end
  end

  local function page(label, help, contents)
    return { label = label, kind = "page", help = help,
      open = function() return { title = label, rows = contents } end }
  end

  local preview, preview_row, preview_name, next_preview = nil, nil, nil, 0
  local function stop_preview(p)
    if not preview then return end
    local token = preview
    preview = nil
    playback.stop(p, token)
  end

  function F.update_style_preview(p, row)
    if p ~= 0 and (wml.read_u8(p + 0x595) ~= 0 or wml.read_u32(p + 0x18D4) ~= 0) then row = nil end
    local kind, name
    if row and row.preview_clip then kind, name = row.preview_clip(row) end
    if row ~= preview_row or name ~= preview_name then
      stop_preview(p)
      preview_row, preview_name, next_preview = row, name, F.tick
    end
    if not name then return end
    if preview then
      if playback.active(p, preview) then return end
      stop_preview(p)
    end
    if F.tick >= next_preview then
      preview = playback.play(p, kind, name, true, true)
      next_preview = F.tick + (preview and 0 or 30)
    end
  end

  for _, id in ipairs({ "stand_variant", "walk_variant", "run_variant" }) do
    local style = F.items[id]
    local default = id:match("^([^_]+)")
    style.help = function()
      local name = style.items[style.v][1]
      local safe = name == "" or (id == "run_variant" and (name:lower() == "run" or name:lower() == "sprint"))
        or (id == "stand_variant" and name:lower() == "stand")
      if not safe or (name ~= "" and not playback.has_state(G.player(), name)) then
        return "Preview only. This clip needs movement or prop context that this menu cannot apply safely."
      end
      return "Highlight or change the style to preview it in place. Accept applies it."
    end
    style.preview_clip = function(it)
      local name = it.items[it.v][1]
      return "State", name ~= "" and name or default
    end
    local apply_style = style.run
    style.run = function(ctx, p, v, it)
      local name = it.items[it.v][1]
      local safe = name == "" or (id == "run_variant" and (name:lower() == "run" or name:lower() == "sprint"))
        or (id == "stand_variant" and name:lower() == "stand")
      if not safe or (name ~= "" and not playback.has_state(p, name)) then
        return "Preview only. Context-dependent clips cannot be applied as movement overrides."
      end
      return apply_style(ctx, p, v, it)
    end
  end

  -- Keep inferred NPC states available for previews; genuine walk overrides use
  -- the native editor catalog with a verified state ID and normal input ownership.
  do
    local walk = F.items.walk_variant
    local previews = {}
    for key, value in pairs(walk) do previews[key] = value end
    previews.id, previews.label = nil, "Walk preview"
    previews.run = function() return "Preview only. Choose a stock Walk Style to change your movement." end
    previews.help = "Preview additional walking clips in place. These clips do not change movement."
    walk.kind, walk.label = "page", "Walk Style"
    walk.items, walk.run, walk.change, walk.preview_clip = nil, nil, nil, nil
    walk.help = "Choose a stock walking style, or browse additional clip previews."
    walk.open = function(_, p) return native_walk.page(p, previews) end
  end

  local function apply(p, command, ...)
    if G.player() ~= p or not G.playing(p) then return "Can't change clothes right now" end
    local _, applied = G.lua(command .. " tweak_out(true)", ...)
    if not applied then return "Couldn't apply the change" end
  end

  local function editor(title, fields, accept)
    local pg = { title = title, rows = fields, accept = accept,
      dirty = function() return true end }
    fields[#fields + 1] = { label = "Apply selection", kind = "action",
      help = "Apply the selection now. Back opens Save Changes.",
      run = function()
        local why = accept()
        if why then return why end
        pg.close_after = 1
        return "Changes saved"
      end }
    return pg
  end

  local function item_editor(item, p)
    local variants = {}
    for i, e in ipairs(item.variants) do
      variants[i] = e[2] ~= item.label and (e.v ~= "" and e.v or e[2]) or "Default"
    end
    local wear = { label = "Wear option", kind = "choice", options = {}, v = 1,
      help = "Choose how to wear the item. Back opens Save Changes." }
    local variant = { label = "Variant", kind = "choice", options = variants, v = 1,
      help = "Choose a color or material. Back opens Save Changes." }
    local function options()
      local e = item.variants[variant.v]
      wear.v, wear.options = 1, {}
      for i, name in ipairs(e.wl) do wear.options[i] = name .. " (" .. i .. "/" .. #e.w .. ")" end
    end
    variant.change = options
    options()
    return editor(item.label, { variant, wear }, function()
      local e = item.variants[variant.v]
      return apply(p, "customization_item_wear(%s, %s, %s, SYNC_LOCAL)", e[1], e.w[wear.v], e.v or "")
    end)
  end

  local function slot_page(slot)
    local by_id, contents = {}, {}
    for _, e in ipairs(slot.items) do
      if #e.w > 0 then
        local item = by_id[e[1]]
        if not item then
          local label = e[2]
          local suffix = " - " .. (e.v or "")
          if label:sub(-#suffix) == suffix then label = label:sub(1, -#suffix - 1) end
          item = { label = label, variants = {} }
          by_id[e[1]] = item
          contents[#contents + 1] = { label = label, kind = "page", help = "Choose a variant and wear option.",
            open = function(_, p) return item_editor(item, p) end }
        end
        item.variants[#item.variants + 1] = e
      end
    end
    return page(slot.name, #contents .. " items.", contents)
  end

  local regions = {}
  for _, region in ipairs({ "Crown", "Forehead", "Brow", "Eyes", "Nose", "Cheekbones", "Ears", "Chin", "Mouth", "Jaw" }) do
    regions[#regions + 1] = { label = region, kind = "page", help = "Adjust the shape of this part of the face.",
      open = function(_, p) return body.morph_page(p, region:lower(), region) end }
  end
  face[1] = page("Face Shape", "Adjust the shape of each part of the face.", regions)
  face[2] = { label = "Body Type", kind = "page", help = "Adjust gender, fat, muscle, age and skin color.",
    open = function(_, p) return body.type_page(p) end }
  face[3] = { label = "Voice", kind = "page", help = "Preview and choose from the six stock voices.",
    open = function(_, p) return body.voice_page(F, p) end }
  for _, group in ipairs(clothing.GROUPS or {}) do
    local slots = {}
    for _, slot in ipairs(group.slots) do
      if not (group.name == "Hair & Face" and native_slots[slot.name]) then
        local dest = group.name == "Hair & Face" and face or slots
        dest[#dest + 1] = slot_page(slot)
      end
    end
    if #slots > 0 then
      local dest = (group.name == "Jewelry" or group.name == "Tattoos") and rows or clothes
      dest[#dest + 1] = page(group.name, "Browse by slot.", slots)
    end
  end
  table.insert(rows, 1, page("Clothing", "Browse tops, bottoms, shoes, hats and more.", clothes))
  table.insert(rows, 1, page("Hair", "Hair, facial hair, brows and lashes.", hair))
  table.insert(rows, 1, page("Face & Body", "Face and body sliders, eyes and makeup.", face))
  if #outfits > 0 then
    local contents = {}
    for _, outfit in ipairs(outfits) do
      contents[#contents + 1] = { label = outfit[2], kind = "page", help = "Select the outfit, then confirm with Save Changes.",
        open = function(_, p)
          return editor(outfit[2], {}, function()
            return apply(p, "customization_outfit_wear(%s, 0, SYNC_LOCAL)", outfit[1])
          end)
        end }
    end
    rows[#rows + 1] = page("Mission Outfits", "Browse outfits worn in missions and activities.", contents)
  end
  rows[#rows + 1] = looks.row(F)
  for _, category in ipairs(F.categories) do
    if category.name == "Customize" then
      F.items.open_creator = nil
      category.items = rows
      F.register(rows)
      break
    end
  end
end
