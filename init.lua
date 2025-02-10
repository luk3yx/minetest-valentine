-- Valentine mod

local S = core.get_translator("valentine")
local gui = flow.widgets
local line_lengths = {25, 25, 25, 20, 15}
local tconcat = table.concat
local utf8 = core.global_exists("utf8") and utf8 or string
local utf8_gmatch, utf8_len, utf8_match, utf8_sub = utf8.gmatch, utf8.len, utf8.match, utf8.sub

local function trim_trailing_space(str)
	return utf8_match(str, "^(.-)%s?$")
end

local newline = ("\n"):byte()
local function wrap_text(str)
	local lines, line = {}, {}

	-- word may be "Hello " or "world!" for example
	for word in utf8_gmatch(str, "[%w'\"%(%)`]*.") do
		-- Stop if the line overflowed
		local length = line_lengths[#lines + 1]
		if not length then
			return lines, true
		end

		-- Handle really long words
		local word_length = utf8_len(trim_trailing_space(word))
		if word_length > length then
			-- Add the current line
			if #line > 0 then
				lines[#lines + 1] = tconcat(line)
				length = line_lengths[#lines + 1] or math.huge
				line = {}
			end

			-- Continue to add new lines with the word until it's short enough
			-- to be handled normally
			while word_length > length do
				lines[#lines + 1] = utf8_sub(word, 1, length)
				word = utf8_sub(word, length + 1)
				word_length = utf8_len(trim_trailing_space(word))
				length = line_lengths[#lines + 1] or math.huge
			end
		end

		-- Create a new line if necessary
		if utf8_len(tconcat(line)) + word_length > length then
			lines[#lines + 1] = trim_trailing_space(tconcat(line))
			line = {}
		end

		-- Handle newlines
		if word:byte(-1) == newline then
			line[#line + 1] = word
			-- This doesn't use utf8_sub since \n is guaranteed to be one byte
			lines[#lines + 1] = tconcat(line):sub(1, -2)
			line = {}
		else
			line[#line + 1] = word
		end
	end

	-- Add the last line
	if #line > 0 then
		lines[#lines + 1] = tconcat(line)
	end

	return lines, #lines > #line_lengths
end

-- Card GUI
local function Card(elem)
	-- At this size, 50px in the texture = 0.4
	-- px / 125 = coords
	elem.padding = 0.3
	elem.min_w = elem.min_w or 13.8 - 0.6
	elem.min_h = 6.36 - 0.6
	elem.spacing = 0.6
	elem.bgimg = elem.bgimg or "valentine_bg.png"

	local editing = flow.get_context().editing
	return gui.Stack{
		padding = 0, no_prepend = true, fbgcolor = "#08080880",

		-- Make clicking outside of the card close it
		gui.Container{
			w = 0, h = 0, align_h = "centre", align_v = "centre",
			{
				type = "image_button_exit", name = "close",
				x = -100, y = -100, w = 200, h = 200,
				noclip = true, drawborder = false,
			}
		},

		editing and gui.ImageButton{w = 1, h = 1, drawborder = false} or
			gui.HBox(elem),

		-- Make clicking on the card open/close it
		editing and gui.HBox(elem) or gui.ImageButton{
			w = 1, h = 1, drawborder = false,
			on_event = function(_, ctx)
				ctx.open = not ctx.open
				return true
			end,
		},
	}
end

local function can_edit_card(name, stack)
	local stack_name = stack:get_name()
	if stack_name == "valentine:card_blank" then
		return true
	elseif stack_name == "valentine:card" then
		local from = stack:get_meta():get_string("from")
		return from == "" or from == name
	end
end

local valentine_gui
valentine_gui = flow.make_gui(function(player, ctx)
	local name = player:get_player_name()
	local is_admin = core.check_player_privs(name, "server")

	-- Just show the outside if it isn't open
	if not ctx.open and not ctx.editing then
		return Card{
			min_w = 6.92 - 0.6,
			bgimg = "valentine_bg_closed.png",
		}
	end

	-- The left side of the card
	local left_side = {
		w = 5, expand = true, align_v = "centre",

		-- Flow currently replaces centred labels with image_button internally
		gui.Label{
			label = S("Valentine card"), align_h = "centre", h = 1,
			style = {font_size = "*2"}
		},

		-- The "To:" label
		ctx.editing and gui.HBox{
			align_h = "centre", h = 1,
			gui.Label{label = S("To:")},
			gui.Field{name = "to", align_v = "centre"},
		} or gui.Label{label = S("To: @1", ctx.to), align_h = "centre", h = 1},

		-- Shown when editing and moves the above two labels further up to
		-- make them look better
		gui.Label{
			label = S("Player not found!"), align_h = "centre",
			visible = ctx.err_no_player or false
		},
	}

	-- The inside of the card
	local inside = {
		w = 5, expand = true, spacing = 0.04,
		gui.Spacer{h = 0.988, expand = false},
		gui.Label{label = S("Message:"), align_h = "centre"}
	}

	if ctx.editing then
		inside[#inside + 1] = gui.Textarea{
			h = 3 * 0.44 - 0.04, padding = 0.44, name = "msg",
		}
		inside[#inside + 1] = gui.Label{
			label = ctx.err or "", align_h = "centre",
		}
		inside[#inside + 1] = gui.Spacer{h = 0.1, expand = false}
		inside[#inside + 1] = gui.Button{
			name = "done", label = S("Done"),
			align_h = "centre",
			on_event = function(p)
				-- Close the form if the player is no longer holding a card
				local stack = p:get_wielded_item()
				if not can_edit_card(name, stack) then
					valentine_gui:close(p)
					return
				end

				-- Make sure the "to" field is valid and the "message" field
				-- can fit in the form
				ctx.err_no_player = not core.player_exists(ctx.form.to)
				if ctx.form.msg == "" then
					ctx.err = S("No message specified!")
				else
					local _, overflowed = wrap_text(ctx.form.msg)
					if overflowed then
						ctx.err = S("Message too long!")
					else
						ctx.err = nil
					end
				end

				-- Redraw the form if something went wrong
				if ctx.err_no_player or ctx.err then
					return true
				end

				-- Otherwise update the card that the player is holding
				stack:set_name("valentine:card")
				local meta = stack:get_meta()
				meta:set_string("to", ctx.form.to)
				meta:set_string("msg", ctx.form.msg)
				meta:set_string("from", name)
				meta:set_string("description", S("Valentine card (to \"@1\")", ctx.form.to))
				p:set_wielded_item(stack)
				valentine_gui:close(p)
			end,
		}
	else
		-- Add the message with separate labels for each line so that the
		-- spacing is correct
		local lines = ctx.lines
		for i = 1, 5 do
			inside[#inside + 1] = gui.Label{label = lines[i] or "", align_h = "centre", w = 5}
		end

		-- Add an empty space between the message and from label
		inside[#inside + 1] = gui.Label{label = "", visible = false}

		if is_admin then
			inside[#inside + 1] = gui.Label{
				label = S("From: @1", ctx.from),
				align_h = "centre"
			}
		end
	end

	return Card{gui.VBox(left_side), gui.VBox(inside)}
end)

-- Written cards
core.register_craftitem("valentine:card", {
	description = S("Valentine card"),
	inventory_image = "valentine_inv.png",
	groups = {flammable = 3, not_in_creative_inventory = 1},
	stack_max = 1,
	on_use = function(itemstack, user, pointed_thing)
		local meta = itemstack:get_meta()
		local node = pointed_thing.type == "node" and core.get_node(pointed_thing.under)
		-- If the player is punching a box, put the card in if possible
		if node and node.name == "valentine:box" and meta:get_string("from") ~= "" then
			local inv = core.get_meta(pointed_thing.under):get_inventory()
			itemstack = inv:add_item("main", itemstack)
			if itemstack:is_empty() then
				core.chat_send_player(user:get_player_name(),
					S("Your card has been put into the box."))
			else
				core.chat_send_player(user:get_player_name(),
					S("The valentine box is full!"))
			end
			return itemstack
		end

		-- Otherwise open the GUI
		local from = meta:get_string("from")
		local name = user:get_player_name()
		if from == name or from == "" then
			-- Edit the card if the player owns it
			valentine_gui:show(user, {
				editing = true,
				form = {
					to = meta:get_string("to"),
					msg = meta:get_string("msg"),
				}
			})
		else
			-- Otherwise show the card
			valentine_gui:show(user, {
				from = meta:get_string("from"),
				to = meta:get_string("to"),
				lines = wrap_text(meta:get_string("msg")),
			})
		end
	end,
})

-- Blank cards
core.register_craftitem("valentine:card_blank", {
	description = S("Blank valentine card"),
	inventory_image = "valentine_inv.png",
	groups = {flammable = 3},
	stack_max = 1,
	on_use = function(_, user)
		valentine_gui:show(user, {editing = true})
	end,
})

-- Crafting
core.register_craft({
	output = "valentine:card_blank",
	recipe = {
		{"default:paper", "default:paper"},
		{"dye:yellow", "dye:red"},
	}
})

core.register_craft({
	output = "valentine:box",
	type = "shapeless",
	recipe =  {"default:chest", "default:paper", "default:paper", "dye:yellow"}
})

-- Let players burn cards
core.register_craft({
	type = "fuel",
	recipe = "valentine:card",
	burntime = 1
})

core.register_craft({
	type = "fuel",
	recipe = "valentine:card_blank",
	burntime = 1
})

--
-- Valentine boxes
--

-- A quick and probably ugly GUI
local valentine_box_gui = flow.make_gui(function(player, ctx)
	local pinv = player:get_inventory()
	local pinv_w = math.ceil(pinv:get_size("main") / 4)
	return gui.VBox{
		spacing = 0.5,
		gui.HBox{
			gui.ItemImage{w = 1, h = 1, item_name = "valentine:box"},
			gui.Label{label = S("Valentine Box")},
		},
		gui.List{
			inventory_location = ("nodemeta:%d,%d,%d"):format(ctx.pos.x, ctx.pos.y, ctx.pos.z),
			list_name = "main",
			w = 9, h = 4,
		},
		gui.Label{label = core.translate("default", "Inventory")},
		gui.List{
			inventory_location = "current_player",
			list_name = "main",
			w = pinv_w, h = 3, starting_item_index = pinv_w,
		},
		gui.Listring{},
		gui.List{
			inventory_location = "current_player",
			list_name = "main",
			w = pinv_w, h = 1,
		},
	}
end)

local function allow_take_put(pos, count, player)
	if core.is_protected(pos, player and player:get_player_name() or "") then
		return 0
	end
	return count
end

core.register_node("valentine:box", {
	description = S("Valentine Box"),
	tiles = {"valentine_box_top.png", "valentine_box_side.png"},
	groups = {choppy = 2, oddly_breakable_by_hand = 2},
	sounds = core.global_exists("default") and default.node_sound_wood_defaults() or nil,
	on_construct = function(pos)
		local meta = core.get_meta(pos)
		meta:set_string("infotext", S("Valentine Box"))
		meta:get_inventory():set_size("main", 9 * 4)
	end,

	on_rightclick = function(pos, _, clicker)
		if not core.is_protected(pos, clicker:get_player_name()) then
			valentine_box_gui:show(clicker, {pos = pos})
		end
	end,

	allow_metadata_inventory_move = function(pos, _, _, _, _, count, player)
		return allow_take_put(pos, count, player)
	end,
	allow_metadata_inventory_put = function(pos, _, _, stack, player)
		if stack:get_name() == "valentine:card" then
			return allow_take_put(pos, stack:get_count(), player)
		end
		return 0
	end,
	allow_metadata_inventory_take = function(pos, _, _, stack, player)
		return allow_take_put(pos, stack:get_count(), player)
	end,
	after_dig_node = function(pos, _, oldmetadata)
		if not oldmetadata.inventory.main then return end
		for _, stack in ipairs(oldmetadata.inventory.main) do
			if not stack:is_empty() then
				core.item_drop(stack, nil, pos)
			end
		end
	end
})
