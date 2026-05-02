
nodeentity = {}

local core = core
local nodeentity = nodeentity

local fs_context = {
	-- index by formname, playername
}

local modname = core.get_current_modname()
local entityname = modname..":node"
local nodesetname = modname..":nodeset"
nodeentity.entityname = entityname
nodeentity.nodesetname = nodesetname

nodeentity.fs_context   = fs_context
nodeentity.name         = entityname

local veczero = vector.zero()

local create_detached_nodemeta = function(name, callbacks)
	local meta = ItemStack():get_meta()
	local inv = core.create_detached_inventory(name, callbacks)
	local detnmmt = table.copy(getmetatable(ItemStack():get_meta())) -- [det]ached [n]ode [m]etadata [m]eta[t]able

	detnmmt.set_tool_capabilities = nil
	detnmmt.set_wear_bar_params = nil
	for k, v in pairs(detnmmt) do
		if v then
			detnmmt[k] = function(self, ...)
				return v(self.meta, ...)
			end
		end
	end
	detnmmt.mark_as_private = function()end
	detnmmt.get_inventory = function() return inv end

	local oldtotable = detnmmt.to_table
	detnmmt.to_table = function(self)
		local t = oldtotable(self)
		local lists = self:get_inventory():get_lists()
		for k, l in pairs(lists) do
			for i, v in ipairs(l) do
				l[i] = v:to_string()
			end
		end
		t.inventory = lists
		return t
	end

	local oldfromtable = detnmmt.from_table
	detnmmt.from_table = function(self, t)
		if not t then return end
		oldfromtable(self, t)
		local inv = self:get_inventory()
		for k in pairs(inv:get_lists()) do
			inv:set_size(k, 0)
		end
		if t.inventory then
			for k, l in pairs(t.inventory) do
				for i, v in ipairs(l) do
					l[i] = ItemStack(v)
				end
				inv:set_size(k, #l)
			end
			inv:set_lists(t.inventory)
		end
	end

	detnmmt.meta = meta
	return detnmmt
end

local create_detached_nodetimer
do
	local metatable = {
		__index = {
			tick = function(self, dt)
				if self.timeout > 0 then
					self.elapsed = self.elapsed + dt
					if self.elapsed > self.timeout then
						self.prevtimeout = self.timeout
						self.timeout = 0
						return true
					end
				end
				return false
			end,
			set = function(self, timeout, elapsed)
				self.timeout = timeout
				self.elapsed = elapsed
			end,
			start = function(self, timeout)
				self.timeout = timeout
				self.elapsed = 0
			end,
			stop = function(self)
				self.timeout = 0
			end,
			get_timeout = function(self)
				return self.timeout
			end,
			get_elapsed = function(self)
				return self.elapsed
			end,
			is_started = function(self)
				return self.timeout > 0
			end,
		}
	}

	create_detached_nodetimer = function()
		return setmetatable({
			timeout = 0,
			elapsed = 0,
			abm = 0
		}, metatable)
	end
end

local convert_pos = function(pos)
	if not pos then return nil end
	if pos.relative then
		local object = core.objects_by_guid[pos.relative]
		if not object then return nil end
		if object:is_valid() then
			local drawscale = object:get_properties().visual_size
			return object:get_pos() + vector.new(pos.x * drawscale.x, pos.y * drawscale.y, pos.z * (drawscale.z or drawscale.x)):rotate(object:get_rotation())
		end
	else
		return pos
	end
end

local find_nodeentity = function(pos)
	if not pos.relative then return pos end
	local object = core.objects_by_guid[pos.relative]
	if not object then return pos end
	if not object:is_valid() then
		return nil
	end
	local entity = object:get_luaentity()
	if entity.name == nodesetname then
		local guid = entity._attachments[("%04x|%04x|%04x"):format(pos.x + 32768, pos.y + 32768, pos.z + 32768)]
		local object = core.objects_by_guid[guid]
		return object and object:is_valid() and object:get_luaentity() or {}, entity.object
	else
		if pos ~= veczero then return nil end
		return entity
	end
end

nodeentity.get = find_nodeentity

local construct_relpos = function(entity)
	local nodeset, _, pos = entity.object:get_attach()
	if nodeset then
		pos = pos / 10
		pos.relative = nodeset:get_guid()
	else
		pos = vector.zero()
		pos.relative = entity.object:get_guid()
	end
	return pos
end

nodeentity.relative_pos = construct_relpos

local oldgetmeta = core.get_meta
core.get_meta = function(pos)
	local nodeentitypos = find_nodeentity(pos)
	if nodeentitypos then
		if nodeentitypos.object then
			return nodeentitypos._metadata
		else
			return oldgetmeta(nodeentitypos)
		end
	end
end

local oldgetnode = core.get_node
core.get_node = function(pos)
	local nodeentitypos = find_nodeentity(pos)
	if nodeentitypos then
		if nodeentitypos.name == entityname then
			return nodeentitypos:get_node()
		elseif nodeentitypos.x then -- is a vector
			return oldgetnode(nodeentitypos)
		end
	end
	return {name = "air", param1 = 0, param2 = 0}
end

local oldgetnodeornil = core.get_node_or_nil
core.get_node_or_nil = function(pos)
	local nodeentitypos = find_nodeentity(pos)
	if nodeentitypos then
		if nodeentitypos.object then
			return nodeentitypos:get_node()
		elseif nodeentitypos.x then -- is a vector
			return oldgetnodeornil(nodeentitypos)
		end
	end
	return {name = "air", param1 = 0, param2 = 0}
end

local oldswapnode = core.swap_node
core.swap_node = function(pos, node)
	local nodeentitypos, nodeset = find_nodeentity(pos)
	if nodeentitypos then
		if nodeentitypos.object then
			nodeentitypos:set_node(node, true)
		elseif nodeset then
			local newnode = nodeentity.add(nodeset:get_pos():offset(pos.x, pos.y, pos.z), node)
			newnode:set_attach(nodeset, "", vector.multiply(pos, 10))
		else
			oldswapnode(nodeentitypos, node)
		end
	end
end

local oldsetnode = core.set_node
core.set_node = function(pos, node)
	local nodeentitypos, nodeset = find_nodeentity(pos)
	if nodeentitypos then
		if nodeentitypos.object then
			nodeentitypos._metadata:from_table({})
			nodeentitypos:set_node(node, true)
		elseif nodeset then
			local newnode = nodeentity.add(nodeset:get_pos():offset(pos.x, pos.y, pos.z), node)
			newnode:set_attach(nodeset, "", vector.multiply(pos, 10))
			local def = core.registered_nodes[node.name]
			if def.on_construct then
				local newentity = newnode:get_luaentity()
				def.on_construct(pos, newentity)
			end
		else
			oldsetnode(nodeentitypos, node)
		end
	end
end
core.add_node = core.set_node

local oldremovenode = core.remove_node
core.remove_node = function(pos)
	local nodeentitypos = find_nodeentity(pos)
	if nodeentitypos then
		if nodeentitypos.object then
			nodeentitypos.object:remove()
		else
			oldremovenode(nodeentitypos)
		end
	end
end

local oldhash = core.hash_node_position
core.hash_node_position = function(pos)
	if pos.relative then
		return ("%012x@%s"):format(oldhash(pos), pos.relative)
	else
		return oldhash(pos)
	end
end

local oldunhash = core.get_position_from_hash
core.get_position_from_hash = function(hash)
	if type(hash) == "number" then
		return oldunhash(hash)
	elseif hash:find("@") then
		local pos = oldunhash(hash:sub(1, 12))
		pos.relative = hash:sub(14)
		return pos
	else
		return oldunhash(hash)
	end
end

local oldPTS = core.pos_to_string
core.pos_to_string = function(pos, precision)
	local retval = oldPTS(pos, precision)
	if pos.relative then
		retval = retval .. "@" .. pos.relative
	end
	return retval
end

local oldSTP = core.string_to_pos
core.string_to_pos = function(str)
	if not str then return end
	local separate = str:split("@", true, 1)
	local pos = oldSTP(separate[1])
	if not pos then return end
	pos.relative = separate[2]
	return pos
end

local uncommited = {}

local oldgetnodetimer = core.get_node_timer
core.get_node_timer = function(pos)
	local nodeentitypos = find_nodeentity(pos)
	if nodeentitypos then
		if nodeentitypos.object then
			return nodeentitypos._timer
		else
			return oldgetnodetimer(nodeentitypos)
		end
	end
end

local oldsoundplay = core.sound_play
core.sound_play = function(spec, parameters, ephemeral)
	if not parameters.pos then return oldsoundplay(spec, parameters, ephemeral) end
	local parameters = table.copy(parameters)
	local pos = parameters.pos
	local nodeentitypos = find_nodeentity(pos)
	if nodeentitypos then
		if nodeentitypos.object then
			parameters.pos = convert_pos(pos)
		else
			parameters.pos = pos
		end
		return oldsoundplay(spec, parameters, ephemeral)
	end
end

local oldinarea = vector.in_area
vector.in_area = function(pos, minp, maxp)
	return oldinarea(convert_pos(pos), vector.sort(convert_pos(minp), convert_pos(maxp)))
end

local oldrandinarea = vector.random_in_area
vector.random_in_area = function(minp, maxp)
	return oldrandinarea(vector.sort(convert_pos(minp), convert_pos(maxp)))
end

local oldVTS = vector.to_string
vector.to_string = function(pos)
	local retval = oldVTS(pos)
	if pos.relative then
		retval = retval .. "@" .. pos.relative
	end
	return retval
end

local oldSTV = vector.from_string
vector.from_string = function(str, init)
	if not str then return end
	local separate = str:split("@", true, 1)
	local pos = oldSTV(separate[1], init)
	if not pos then return nil end
	pos.relative = separate[2]
	return pos
end

local convert_func = function(location, key)
	local oldfunc = location[key]
	location[key] = function(a, ...)
		return oldfunc(convert_pos(a), ...)
	end
end

local convert_func2 = function(location, key)
	local oldfunc = location[key]
	location[key] = function(a, b, ...)
		local a = convert_pos(a)
		local b = convert_pos(b)
		return oldfunc(a, b, ...)
	end
end

local convert_method = function(location, key)
	local oldfunc = location[key]
	location[key] = function(self, a, ...)
		return oldfunc(self, convert_pos(a), ...)
	end
end

local convert_method2 = function(location, key)
	local oldfunc = location[key]
	location[key] = function(self, a, b, ...)
		return oldfunc(self, convert_pos(a), convert_pos(b), ...)
	end
end

local relativize_func = function(location, key)
	local oldfunc = location[key]
	location[key] = function(a, ...)
		local retval = oldfunc(a, ...)
		retval.relative = a.relative
		return retval
	end
end

local convert_field = function(location, key)
	if not location then return end
	if not location[key] then return end
	location[key] = convert_pos(location[key])
end

local oldaddparticle = core.add_particle
core.add_particle = function(def)
	def = table.copy(def)
	convert_field(def, "pos")
	oldaddparticle(def)
end
--[[
	local oldaddparticlespawner = core.add_particlespawner
	core.add_particlespawner = function(def)
	def = table.copy(def)
	convert_field(def, "minpos")
	convert_field(def, "maxpos")
	if type(def.pos) == "table" then
		if def.pos.x then
			convert_field(def, "pos")
		else
			convert_field(def.pos, "min")
			convert_field(def.pos, "max")
		end
	end
	if def.pos_tween then
		for k, v in ipairs(def.pos_tween) do
			if type(v) == "table" then
				if v.x then
					convert_field(def.pos_tween, k)
				else
					convert_field(v, "min")
					convert_field(v, "max")
				end
			end
		end
	end
	oldaddparticlespawner(def)
end
]]
	
--local oldplacenode = core.place_node
--core.place_node = function(pos, node, placer, ...)
--end

convert_func2(vector, "direction")
convert_func2(vector, "distance")
convert_func2(vector, "sort")

relativize_func(vector, "offset")
relativize_func(vector, "copy")
relativize_func(vector, "apply")
relativize_func(vector, "rotate_around_axis")
relativize_func(vector, "rotate")

convert_func(core, "spawn_falling_node")
convert_func(core, "get_natural_light")
convert_func(core, "add_entity")
convert_func(core, "punch_node")
convert_func(core, "dig_node")
convert_func(core, "add_item")
convert_func(core, "get_objects_inside_radius")
convert_func(core, "objects_inside_radius")
convert_func(core, "find_node_near") -- WISHME: include node entities
convert_func(core, "get_heat")
convert_func(core, "get_humidity")
convert_func(core, "get_biome_data")
convert_func(core, "spawn_tree")
convert_func(core, "transforming_liquid_add")
convert_func(core, "get_node_max_level") -- WISHME: include node entities
convert_func(core, "get_node_level") -- WISHME: include node entities
convert_func(core, "set_node_level") -- WISHME: include node entities
convert_func(core, "add_node_level")
convert_func(core, "check_single_for_falling")
convert_func(core, "check_for_falling")
convert_func(core, "add_item")
convert_func(core, "add_item")

convert_func2(core, "get_objects_in_area")
convert_func2(core, "objects_in_area")
convert_func2(core, "find_nodes_in_area") -- WISHME: include node entities
convert_func2(core, "find_nodes_in_area_under_air") -- WISHME: include node entities
convert_func2(core, "load_area")
convert_func2(core, "emerge_area")
convert_func2(core, "delete_area")
convert_func2(core, "line_of_sight")
convert_func2(core, "raycast")
convert_func2(core, "find_path")
convert_func2(core, "fix_light")
convert_func2(core, "dig_node")
convert_func2(core, "dig_node")
convert_func2(core, "dig_node")
convert_func2(core, "dig_node")

convert_method2(core, "generate_ores")
convert_method2(core, "generate_decorations")

local oldnew = vector.new
vector.new = function(x, y, z, r)
	local newvec = oldnew(x, y, z)
	newvec.relative = r
	return newvec
end

local oldadd = vector.add
vector.add = function(a, b)
	local newvec = oldadd(a, b)
	newvec.relative = a.relative or ((type(b) == "table") and b.relative)
	return newvec
end

relativize_func(vector, "subtract")

local vecmetatable = vector.metatable

oldmetaadd = vecmetatable.__add
vecmetatable.__add = function(a, b)
	local newvec = oldmetaadd(a, b)
	newvec.relative = a.relative or b.relative
	return newvec
end

relativize_func(vecmetatable, "__sub")
relativize_func(vecmetatable, "__unm")

local parseformspec = function(formspec, entity)
	local invname = "[detached:nodeentity"..entity.object:get_guid()
	local meta = entity._metadata
	while true do
		local i, j = formspec:find("%$%{.-%}")
		if not i then break end
		local key = formspec:sub(i + 2, j - 1)
		formspec = formspec:gsub("%$%{"..key.."%}", meta:get_string(key))
	end
	return formspec:gsub("%[context", invname)
end

local t = core.registered_on_player_receive_fields
core.register_last_on_player_receive_fields = function(func)
	t[#t + 1] = func
	core.callback_origins[func] = {
		-- may be nil or return nil
		mod = core.get_current_modname and core.get_current_modname() or "??",
		name = "register_on_player_recieve_fields"
	}
end

core.register_last_on_player_receive_fields(function(player, formname, fields) -- ANTIPRIORITY
	local pname = player:get_player_name()
	if fs_context[formname] and fs_context[formname][pname] then
		if fields.quit then fs_context[formname][pname] = nil end
	end
end)

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname:sub(1, #entityname) == entityname then
		local guid = formname:split(";", true, 1)[2]
		local entity = core.objects_by_guid[guid]:get_luaentity()
		local def = core.registered_nodes[entity:get_node().name]
		def.on_receive_fields(construct_relpos(entity), formname, fields, player, entity)
	end
end)

local abm_neighbors = {
	vector.new(-1,-1,-1),
	vector.new( 0,-1,-1),
	vector.new( 1,-1,-1),
	vector.new(-1, 0,-1),
	vector.new( 0, 0,-1),
	vector.new( 1, 0,-1),
	vector.new(-1, 1,-1),
	vector.new( 0, 1,-1),
	vector.new( 1, 1,-1),
	vector.new(-1,-1, 0),
	vector.new( 0,-1, 0),
	vector.new( 1,-1, 0),
	vector.new(-1, 0, 0),
--	vector.new( 0, 0, 0),
	vector.new( 1, 0, 0),
	vector.new(-1, 1, 0),
	vector.new( 0, 1, 0),
	vector.new( 1, 1, 0),
	vector.new(-1,-1, 1),
	vector.new( 0,-1, 1),
	vector.new( 1,-1, 1),
	vector.new(-1, 0, 1),
	vector.new( 0, 0, 1),
	vector.new( 1, 0, 1),
	vector.new(-1, 1, 1),
	vector.new( 0, 1, 1),
	vector.new( 1, 1, 1),
}

local function check_neighbors(pos, include, exclude)
	local includeset = {}
	local excludeset = {}
	local igroups    = {}
	local egroups    = {}
	local icheck
	if include then
		for _, n in ipairs(include) do
			if n:sub(1,6) == "group:" then
				table.insert(igroups, n:sub(7))
			else
				includeset[n] = true
			end
		end
	else
		icheck = true
	end
	if exclude then
		for _, n in ipairs(exclude) do
			if n:sub(1,6) == "group:" then
				table.insert(egroups, n:sub(7))
			else
				excludeset[n] = true
			end
		end
	end
	for _, neighbor in ipairs(abm_neighbors) do
		local name = core.get_node(pos + neighbor).name
		if excludeset[name] then return false end
		if not icheck then
			if includeset[name] then icheck = true end
			for _, group in ipairs(igroups) do
				if core.get_item_group(name, group) then icheck = true end
			end
		end
		for _, group in ipairs(egroups) do
			if core.get_item_group(name, group) then return false end
		end
	end
	return icheck
end

local invcallbacks = function(entity)
	local relpos = construct_relpos(entity)
	local def = core.registered_nodes[entity:get_node().name]
	return {
	allow_move = def.allow_metadata_inventory_move and function(inv, from_list, from_index, to_list, to_index, count, player)
		return def.allow_metadata_inventory_move(relpos, from_list, from_index, to_list, to_index, count, player, entity)
	end,

	allow_put = def.allow_metadata_inventory_put and function(inv, listname, index, stack, player)
		return def.allow_metadata_inventory_put(relpos, listname, index, stack, player, entity)
	end,

	allow_take = def.allow_metadata_inventory_take and function(inv, listname, index, stack, player)
		return def.allow_metadata_inventory_take(relpos, listname, index, stack, player, entity)
	end,
		
	on_move = def.on_metadata_inventory_move and function(inv, from_list, from_index, to_list, to_index, count, player)
		return def.on_metadata_inventory_move(relpos, from_list, from_index, to_list, to_index, count, player, entity)
	end,

	on_put = def.on_metadata_inventory_put and function(inv, listname, index, stack, player)
		return def.on_metadata_inventory_put(relpos, listname, index, stack, player, entity)
	end,

	on_take = def.on_metadata_inventory_take and function(inv, listname, index, stack, player)
		return def.on_metadata_inventory_take(relpos, listname, index, stack, player, entity)
	end,
} end

local rclick = function(self, clicker)
	local def = core.registered_nodes[self:get_node().name]
	local relpos = construct_relpos(self)
	local abspos = convert_pos(relpos)
	local eyepos = clicker:get_pos() + clicker:get_eye_offset():offset(0,clicker:get_properties().eye_height,0)
	local topos = eyepos + clicker:get_look_dir() * 16
	local childoffset = self.object:get_pos() - abspos -- raycasts on children fail miserably (no child offset)
	local raycast = Raycast(eyepos + childoffset, topos + childoffset, true, false, {objects = {[entityname] = true, [nodesetname] = false}})
	local raypoint = nil
	local selfguid = self.object:get_guid()
	for point in raycast do
		if point.ref and (point.ref:get_guid() == selfguid) then raypoint = point break end
	end
	if not raypoint then return end
	local pointed = {
		type = "node",
		under = relpos,
		above = relpos + raypoint.intersection_normal
	}
	local sneaking = clicker and clicker:get_player_control().sneak
	if sneaking then
		local newstack = core.item_place_node(clicker:get_wielded_item(), clicker, pointed)
		clicker:set_wielded_item(newstack)
	else
		local fs = self._metadata:get_string("formspec")
		if def.on_rightclick then
			local retval = def.on_rightclick(relpos, self:get_node(), clicker, clicker:get_wielded_item(), pointed, self)
			if retval then clicker:set_wielded_item(retval) end
		elseif fs ~= "" then
			core.show_formspec(clicker:get_player_name(), entityname..";"..self.object:get_guid(), parseformspec(fs, self))
		elseif clicker then
			local newstack = core.item_place_node(clicker:get_wielded_item(), clicker, pointed)
			clicker:set_wielded_item(newstack)
		end
	end
end

local deactivate = function(self, removal)
	local def = core.registered_nodes[self:get_node().name]
	if self._NOELIM then return end
	local relpos = construct_relpos(self)
	if removal then
		if def.on_destruct then
			def.on_destruct(relpos, self)
		end
		if def.after_destruct then
			local node = self:get_node()
			def.after_destruct(relpos, node, self)
		end
	else
		self._NOREMOVE = true
	end
	core.remove_detached_inventory("nodeentity" .. self.object:get_guid())
end

local death = function(self, killer)
	local def = core.registered_nodes[self:get_node().name]
	local tool = killer:get_wielded_item()
	local absolutepos = convert_pos(construct_relpos(self))
	core.handle_node_drops(absolutepos, core.get_node_drops(self:get_node(), tool:get_name(), tool, killer, absolutepos), killer)
	if def.after_dig_node then
		def.after_dig_node(absolutepos, self:get_node(), self._metadata, killer, self)
	end
end

local punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
	local def = core.registered_nodes[self:get_node().name]
	local relpos = construct_relpos(self)
	local punch = def.on_punch or core.node_punch
	punch(relpos, self:get_node(), puncher, {
		type = "node",
		under = convert_pos(relpos),
		above = nil
	}, self)
	if def.can_dig then
		if def.can_dig(relpos, puncher, self) then
			local dig = def.on_dig or core.node_dig
			dig(relpos, self:get_node(), puncher, self)
		else
			return true
		end
	end
end

local eval_number = function(str, default)
	if str == "" then return default end
	return tonumber(str, 16)
end

local eval_string = function(str, default)
	if str == "" then return default end
	return str
end

local activate = function(self, staticdata, dtime_s)
	self._timer = create_detached_nodetimer()
	local data = {"", "", "", ""}
	if staticdata and (staticdata ~= "") then
		data = staticdata:split("|", true, 3)
	end
	local nodename = data[3]
	if nodename == "ignore" or nodename == "air" or nodename == "" then
		self._NOELIM = true
		return self.object:remove()
	end
	local metaref = create_detached_nodemeta("nodeentity" .. self.object:get_guid(), invcallbacks(self))
	self._metadata = metaref
	self._timer:set(tonumber(data[1]), tonumber(data[2]))
	
	staticdata = data[4]
	metaref:from_table(core.deserialize(staticdata:sub(5)) or {})

	self:set_node({
		param1 = eval_number(staticdata:sub(1,2), 240),
		param2 = eval_number(staticdata:sub(3,4), core.registered_nodes[nodename].place_param2),
		name   = nodename
	})

	local node = self:get_node()
	for _, lbm in ipairs(core.registered_lbms) do
		if not lbm.run_at_every_load then return end -- known flaw
		for _, name in ipairs(lbm.nodenames) do
			if (node.name == name) or ((name:sub(1,6) == "group:") and (core.get_item_group(node.name, name:sub(7)) ~= 0)) then
				lbm.action(relpos, node, dtime_s, self)
				break
			end
		end
	end
end

local step = function(self, dtime, moveresult)
	local def = core.registered_nodes[self:get_node().name]
	local pos = construct_relpos(self)
	local timer = self._timer
	if timer:tick(dtime) then
		if def.on_timer(pos, timer.prevtimeout, self) then
			timer:start(timer.prevtimeout)
		end
	end
	local fname = entityname..";"..self.object:get_guid()
	local fs = self._metadata:get_string("formspec")
	local parsedfs = parseformspec(fs, self)
	if self._prevfs and (parsedfs ~= self._prevfs) then
		for pname, fsc in pairs(fs_context[fname] or {}) do
			core.show_formspec(pname, fname, fs)
		end
	end
	local newtimerabm = timer.abm + dtime
	self.object:set_properties({infotext = self._metadata:get_string("infotext")})
	local node = self:get_node()
	for _, abm in ipairs(core.registered_abms) do
		if ((timer.abm % abm.interval) > (newtimerabm % abm.interval)) and (math.random(abm.chance) == 1) then
			for _, name in ipairs(abm.nodenames) do
				if (node.name == name) or ((name:sub(1,6) == "group:") and (core.get_item_group(node.name, name:sub(7)) ~= 0)) then
					if check_neighbors(pos, abm.neighbors, abm.without_neighbors) then
						abm.action(pos, node, 0, 0, self, dtime, moveresult) -- missing object counts
					end
					break
				end
			end
		end
	end
	timer.abm = newtimerabm
	if def._nodeentity_step then
		def._nodeentity_step(self, dtime, moveresult)
	end
end

core.register_entity(entityname, {
	initial_properties = {

		visual = "node",

		makes_footstep_sound = true,
		-- If true, object is able to make footstep sounds of nodes
		-- (see node sound definition for details).

		damage_texture_modifier = "^[brighten",
		-- Texture modifier to be applied for a short duration when object is hit
	},

	on_activate = activate,
	on_deactivate = deactivate,
	on_step = step,
	on_punch = punch,
	on_death = death,
	on_rightclick = rclick,
	--[[
	on_attach_child = function(self, child) end,
	on_detach_child = function(self, child) end,
	on_detach = function(self, parent) end,
	]]
	get_node = function(self)
		return self.object:get_properties().node
	end,
	set_node = function(self, node, init)
		local def = core.registered_nodes[node.name]

		local selbox
		if def.selection_box.type == "regular" then
			selbox = { -0.5, -0.5, -0.5, 0.5, 0.5, 0.5, rotate = true }
		elseif def.selection_box.fixed then
			selbox = def.selection_box.fixed
			if selbox then
				if type(selbox[1]) == "table" then selbox = selbox[1] end
			else
				selbox = (def.drawtype == "nodebox") and def.node_box
			end
			selbox = selbox and table.copy(selbox)
			selbox.rotate = true
		else
			selbox = { -0.125, -0.125, -0.125, 0.125, 0.125, 0.125, rotate = true }
		end

		self.object:set_properties({
			node = node,
			selectionbox = selbox,
			glow = def.light_source,
			physical = def.walkable or (def.walkable == nil),
			--pointable = true, --def.pointable or (def.pointable == nil),
			collide_with_objects = def.walkable or (def.walkable == nil),
			collisionbox = def.collision_box or (def.drawtype == "nodebox" and def.node_box),
		})

		if init then
			local relpos = construct_relpos(self)

			if def.on_construct then
				def.on_construct(relpos, self)
			end
		end
	end,
	get_staticdata = function(self)
		local node = self:get_node()
		local timer = self._timer
		return string.format("%f|%f|%s|%02x%02x%s", timer.timeout, timer.elapsed, node.name, node.param1, node.param2, (self._metadata and core.serialize(self._metadata:to_table())) or "")
	end,
})

core.register_entity(nodesetname, {
	
	initial_properties = {

		visual =  "upright_sprite",
		textures = {"blank.png", "blank.png"},

		shaded = false,

		static_save = true,
		-- If false, never save this object statically. It will simply be
		-- deleted when the block gets unloaded.
		-- The get_staticdata() callback is never called then.
		-- Defaults to 'true'.
	},
	-- A table of object properties, see the `Object properties` section.
	-- The properties in this table are applied to the object
	-- once when it is spawned.

	-- Refer to the "Registered entities" section for explanations
	on_activate = function(self, staticdata, dtime_s)
		if staticdata and staticdata ~= "" then
			self._attachments = core.deserialize(staticdata)
		else
			self._attachments = {}
		end
	end,
	on_step = function(self, dtime, moveresult)
		if not self._attachments then return end
		for pos, guid in pairs(self._attachments) do
			local child = core.objects_by_guid[guid]
			if child and child:is_valid() then
				local listpos = pos:split("|")
				child:set_attach(self.object, "", 10 * vector.new(tonumber(listpos[1], 16) - 32768, tonumber(listpos[2], 16) - 32768, tonumber(listpos[3], 16) - 32768))
			end
		end
	end,
	on_attach_child = function(self, child)
		local _, _, attachpos = child:get_attach()
		self._attachments[("%04x|%04x|%04x"):format(attachpos.x / 10 + 32768, attachpos.y / 10 + 32768, attachpos.z / 10 + 32768)] = child:get_guid()
	end,
	on_detach_child = function(self, child)
		if true then return end
		local entity = child:get_luaentity()
		if entity._NOREMOVE then return end
		local _, _, attachpos = child:get_attach()
		self._attachments[("%04x|%04x|%04x"):format(attachpos.x / 10 + 32768, attachpos.y / 10 + 32768, attachpos.z / 10 + 32768)] = nil
	end,
	get_staticdata = function(self)
		return core.serialize(self._attachments)
	end,
})

local function add_nodeentity(pos, node)
	if node.name == "ignore" or node.name == "air" then return end
	return core.add_entity(pos, entityname, "0|0|"..node.name.."|")
end

nodeentity.add = add_nodeentity
core.register_on_mods_loaded(function()
	
	local oldisprotected = core.is_protected
	core.is_protected = function(pos, player)
		local pos = convert_pos(pos)
		if pos then return oldisprotected(pos, player) end
	end

	core.after(0, function()

	local vmanipmeta = getmetatable(VoxelManip())

	local oldvmget = vmanipmeta.get_node_at
	vmanipmeta.get_node_at = function(self, pos)
		local nodeentitypos = find_nodeentity(pos)
		if nodeentitypos then
			if nodeentitypos.object then
				return nodeentitypos:get_node()
			elseif nodeentitypos.x then
				return oldvmget(self, nodeentitypos)
			end
			return {name = "air", param1 = 0, param2 = 0}
		end
		return {name = "ignore", param1 = 0, param2 = 0}
	end

	local oldvmset = vmanipmeta.set_node_at
	vmanipmeta.set_node_at = function(self, pos, node)
		local nodeentitypos, attachment = find_nodeentity(pos)
		if nodeentitypos then
			if nodeentitypos.object then
				uncommited[self] = uncommited[self] or {}
				uncommited[self][core.hash_node_position(pos)] = function()
					nodeentitypos:set_node(node)
				end
			elseif attachment then
				uncommited[self] = uncommited[self] or {}
				uncommited[self][core.hash_node_position(pos)] = function()
					local newnode = nodeentity.add(attachment.parent:get_pos():offset(pos.x, pos.y, pos.z), node, true)
					newnode:set_attach(attachment.parent, "", vector.multiply(pos, 10))
				end
			else
				oldvmset(self, nodeentitypos, node)
			end
		end
	end
	local oldvmwrite = vmanipmeta.write_to_map
	vmanipmeta.write_to_map = function(self, light)
		oldvmwrite(self, light)
		if not uncommited[self] then return end
		for k, v in pairs(uncommited[self]) do v() end
	end

	local dummy = core.add_entity(veczero, nodesetname)
	local objmeta = getmetatable(dummy)
	dummy:remove()

	convert_method(objmeta, "set_pos")
	convert_method(objmeta, "move_to")

	end)
end)

function nodeentity.read_world(pos, anchor, minp, maxp)
	local minp, maxp = vector.sort(convert_pos(minp), convert_pos(maxp))
	local pos = convert_pos(pos)
	local anchor = convert_pos(anchor)
	assert(pos, "can't read from the void")
	assert(anchor, "can't place in the void")
	local vm = VoxelManip(minp, maxp)
	local nodeset = core.add_entity(pos, nodesetname)
	local nodepos = vector.zero()
	for x = minp.x, maxp.x do
	for y = minp.y, maxp.y do
	for z = minp.z, maxp.z do
		nodepos.x, nodepos.y, nodepos.z = x, y, z
		local node = vm:get_node_at(nodepos)
		if (node.name ~= "air") and (node.name ~= "ignore") then
			local newobject = add_nodeentity(pos, node)
			local newentity = newobject:get_luaentity()
			newentity._metadata:from_table(oldgetmeta(nodepos):to_table())
			newobject:set_attach(nodeset, "", (nodepos - anchor) * 10)
		end
	end end end
	return nodeset
end

local csvify_pos = function(pos)
	return core.pos_to_string(pos):gsub("[%(%)]", "")
end

local uncsvify_pos = function(str)
core.log(str)
	local separate = str:split("@", true, 1)
	core.log(dump(separate))
	local pos = core.string_to_pos("("..separate[1]..")")
	if not pos then return end
	pos.relative = separate[2]
	return pos
end

local utils = {}
nodeentity.utils = utils
utils.pos_to_csv = csvify_pos
utils.csv_to_pos = uncsvify_pos

do
	local fs_invloc_init = "%[nodemeta%:"
	local fs_invloc_init_len = #fs_invloc_init - 2
	local num = "[%d.-]+"
	local delim = "[,%s]%s*"
	local guid = "%@%@[a-zA-Z0-9%/%+]*"
	local base_pattern = fs_invloc_init .. num .. delim .. num .. delim .. num .. guid
	local oldshowformspec = core.show_formspec
	core.show_formspec = function(playername, formname, formspec, ...)
		local searched = formspec
		local nformspec = ""
		while true do
			local i, j = searched:find(base_pattern)
			if not i then
				nformspec = nformspec .. searched
				break
			end
			local head = i > 1 and searched:sub(1, i-1) or ""
			local tail = j < #searched and searched:sub(j+1, -1) or ""
			local pos = uncsvify_pos(searched:sub(i + fs_invloc_init_len, j))
			if pos then
				local entity, nodeset = find_nodeentity(pos)
				if entity and entity.object then
					nformspec = nformspec .. head .. "[detached:nodeentity" .. entity.object:get_guid()
				end
			end
			searched = tail
		end
		core.log(nformspec)
		return oldshowformspec(playername, formname, nformspec, ...)
	end
end

local modpath = core.get_modpath(modname).."/"

dofile(modpath.."compat.lua") -- some mods are helplessly incompatible, this is to modify their behavior accordingly
