
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

local nodetimer_metatable = {
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
			self.start_epoch = core.get_us_time()
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
		start_epoch = 0,
		timeout = 0,
		elapsed = 0,
		abm = 0,
	}
}

local create_detached_nodetimer = function()
	return setmetatable({
		start_epoch = 0,
		timeout = 0,
		elapsed = 0,
		abm = 0,
	}, nodetimer_metatable)
end

local convert_pos = function(pos)
	if not pos then return nil end
	if pos.relative then
		local object = core.objects_by_guid[pos.relative]
		if not object then return nil end
		if object:is_valid() then
			return object:get_pos() + vector.multiply(pos, object:get_luaentity()._scale):rotate(object:get_rotation())
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
		local nodeobject = core.objects_by_guid[guid]
		return nodeobject and nodeobject:is_valid() and nodeobject:get_luaentity() or {}, object
	else
		if pos ~= veczero then return nil end
		return entity
	end
end

nodeentity.get = find_nodeentity

local construct_relpos = function(entity)
	local nodeset, _, pos = entity.object:get_attach()
	if nodeset and pos then
		pos = pos / (10 * nodeset:get_luaentity()._scale)
		pos.relative = nodeset:get_guid()
	else
		pos = vector.zero()
		pos.relative = entity.object:get_guid()
	end
	return pos, nodeset ~= nil
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
	if type(node) == "string" then node = {name = node} end
	local nodeentitypos, nodeset = find_nodeentity(pos)
	if nodeentitypos then
		if nodeentitypos.object then
			nodeentitypos:set_node(node)
		elseif nodeset then
			local newnode = nodeentity.add(nodeset:get_pos():offset(pos.x, pos.y, pos.z), node)
			nodeset:get_luaentity():add_node(pos, newnode)
		else
			oldswapnode(nodeentitypos, node)
		end
	end
end

local oldsetnode = core.set_node
core.set_node = function(pos, node)
	if type(node) == "string" then node = {name = node} end
	local nodeentitypos, nodeset = find_nodeentity(pos)
	if nodeentitypos then
		if nodeentitypos.object then
			local oldnode = nodeentitypos:get_node()
			local def = core.registered_nodes[oldnode.name]
			if def.on_destruct then
				def.on_destruct(pos, nodeentitypos)
			end
			nodeentitypos._metadata:from_table({})
			nodeentitypos:set_node(node, true)
			if def.after_destruct then
				def.after_destruct(pos, oldnode, nodeentitypos)
			end
		elseif nodeset then
			local newnode = nodeentity.add(nodeset:get_pos():offset(pos.x, pos.y, pos.z), node)
			nodeset:get_luaentity():add_node(pos, newnode)
			local def = core.registered_nodes[node.name]
			if def.on_construct then
				def.on_construct(pos, newnode:get_luaentity())
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
			local oldnode = nodeentitypos:get_node()
			local def = core.registered_nodes[oldnode.name]
			if def.on_destruct then
				def.on_destruct(pos, nodeentitypos)
			end
			nodeentitypos.object:remove()
			if def.after_destruct then
				def.after_destruct(pos, oldnode, nodeentitypos)
			end
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
		local pos = oldunhash(tonumber(hash:sub(1, 12), 16))
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
	newvec.relative = r or type(x) == "table" and x.relative
	return newvec
end

local oldequals = vector.equals
vector.equals = function(a, b)
	return oldequals(a, b) and a.relative == b.relative
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
		local object = core.objects_by_guid[guid]
		if not object then return end
		local entity = object:get_luaentity()
		if not entity then return end
		local def = core.registered_nodes[entity:get_node().name]
		local relpos = construct_relpos(entity)
		def.on_receive_fields(relpos, formname, fields, player, entity)
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
	allow_move = def.allow_metadata_inventory_move and function(_, from_list, from_index, to_list, to_index, count, player)
		return def.allow_metadata_inventory_move(relpos, from_list, from_index, to_list, to_index, count, player, entity)
	end,

	allow_put = def.allow_metadata_inventory_put and function(_, listname, index, stack, player)
		return def.allow_metadata_inventory_put(relpos, listname, index, stack, player, entity)
	end,

	allow_take = def.allow_metadata_inventory_take and function(_, listname, index, stack, player)
		return def.allow_metadata_inventory_take(relpos, listname, index, stack, player, entity)
	end,

	on_move = def.on_metadata_inventory_move and function(_, from_list, from_index, to_list, to_index, count, player)
		return def.on_metadata_inventory_move(relpos, from_list, from_index, to_list, to_index, count, player, entity)
	end,

	on_put = def.on_metadata_inventory_put and function(_, listname, index, stack, player)
		return def.on_metadata_inventory_put(relpos, listname, index, stack, player, entity)
	end,

	on_take = def.on_metadata_inventory_take and function(_, listname, index, stack, player)
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
	local raypoint
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
		local wielded = clicker:get_wielded_item()
		local itemname = wielded:get_name()
		local newstack = core.item_place_node(wielded, clicker, pointed)
		clicker:set_wielded_item(newstack)
		local idef = core.registered_nodes[itemname]
		if idef and idef.on_place then idef.on_place(wielded, clicker, pointed) end
	else
		local fs = self._metadata:get("formspec")
		if def.on_rightclick then
			local retval = def.on_rightclick(relpos, self:get_node(), clicker, clicker:get_wielded_item(), pointed, self)
			if retval then clicker:set_wielded_item(retval) end
		end
		if fs then
			core.show_formspec(clicker:get_player_name(), entityname..";"..self.object:get_guid(), parseformspec(fs, self))
		elseif clicker and not def.on_rightclick then
			local wielded = clicker:get_wielded_item()
			local itemname = wielded:get_name()
			local newstack = core.item_place_node(wielded, clicker, pointed)
			clicker:set_wielded_item(newstack)
			local idef = core.registered_nodes[itemname]
			if idef and idef.on_place then idef.on_place(wielded, clicker, pointed) end
		end
	end
end

local deactivate = function(self)
	if self._metadata then core.remove_detached_inventory("nodeentity" .. self.object:get_guid()) end
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

local punch = function(self, puncher) --, time_from_last_punch, tool_capabilities, dir, damage)
	local def = core.registered_nodes[self:get_node().name]
	local relpos = construct_relpos(self)
	local punch = def.on_punch or core.node_punch
	punch(relpos, self:get_node(), puncher, {
		type = "node",
		under = convert_pos(relpos),
		above = nil
	}, self)
	if (not def.can_dig) or def.can_dig(relpos, puncher, self) then
		local dig = def.on_dig or core.node_dig
		dig(relpos, self:get_node(), puncher, self)
	else
		return true
	end
end

local nodeentity_deserializations = {
	function(self, data) -- version 1
		self._scale = data.scale or 1
		local node = data.node
		self:set_node({
			param1 = node.param1 or 240,
			param2 = node.param2 or core.registered_nodes[node.name].place_param2,
			name   = node.name
		})
		if data.timer then
			self._timer = setmetatable(data.timer, nodetimer_metatable)
		else
			self._timer = create_detached_nodetimer()
		end
		local metaref = create_detached_nodemeta("nodeentity" .. (self.object:get_guid() or data.guid), invcallbacks(self))
		self._metadata = metaref
		metaref:from_table(data.metadata or {})
	end,
}

local activate = function(self, staticdata, dtime_s)
	-- do return self.object:remove() end -- in case of error loop
	if not staticdata then return self.object:remove() end
	if not self.object:is_valid() then return end
	if staticdata:sub(1,6) == "return" then
		local data = core.deserialize(staticdata)
		local version = data.__version or 1 -- or <latest>
		nodeentity_deserializations[version](self, data)
	else
		return self.object:remove()
	end

	local node = self:get_node()
	local relpos = construct_relpos(self)
	for _, lbm in pairs(core.registered_lbms) do
		if lbm.run_at_every_load then -- known flaw
			for _, name in ipairs(lbm.nodenames) do
				if (node.name == name) or ((name:sub(1,6) == "group:") and (core.get_item_group(node.name, name:sub(7)) ~= 0)) then
					lbm.action(relpos, node, dtime_s, self)
					break
				end
			end
		end
	end
end

local step = function(self, dtime, moveresult)
	local def = core.registered_nodes[self:get_node().name]
	local pos = construct_relpos(self)
	local node = self:get_node()
	local timer = self._timer
	if timer:tick(dtime) then
		if def.on_timer(pos, core.get_us_time() - timer.start_epoch, node, timer.prevtimeout, self) then
			timer:start(timer.prevtimeout)
		end
	end
	local fname = entityname..";"..self.object:get_guid()
	local fs = self._metadata:get_string("formspec")
	local parsedfs = parseformspec(fs, self)
	if self._prevfs and (parsedfs ~= self._prevfs) then
		for pname, _ in pairs(fs_context[fname] or {}) do
			core.show_formspec(pname, fname, fs)
		end
	end
	local newtimerabm = timer.abm + dtime
	self.object:set_properties({infotext = self._metadata:get_string("infotext")})
	for _, abm in ipairs(core.registered_abms) do
		if ((timer.abm % abm.interval) > (newtimerabm % abm.interval)) and (math.random(abm.chance) == 1) then
			local nodenames = abm.nodenames
			if type(nodenames) == "string" then
				nodenames = {nodenames}
			end
			for _, name in ipairs(nodenames) do
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
		if node.name == "air" or node.name == "ignore" then
			self.object:remove()
			return
		end

		local def = core.registered_nodes[node.name]
		if not def then return end

		local selbox
		if def.selection_box.type == "regular" then
			selbox = { -0.5, -0.5, -0.5, 0.5, 0.5, 0.5, rotate = true }
		elseif def.selection_box.fixed then
			selbox = def.selection_box.fixed
			if type(selbox[1]) == "table" then selbox = selbox[1] end
			selbox = selbox and table.copy(selbox)
			selbox.rotate = true
		else
			selbox = { -0.125, -0.125, -0.125, 0.125, 0.125, 0.125, rotate = true }
		end

		local colbox
		local colbox_def = def.collision_box or {type = "regular"}
		if colbox_def.type == "regular" then
			colbox = { -0.5, -0.5, -0.5, 0.5, 0.5, 0.5, rotate = true }
		elseif colbox_def.fixed then
			colbox = colbox_def.fixed
			if type(colbox[1]) == "table" then colbox = colbox[1] end
			colbox = colbox and table.copy(colbox)
			colbox.rotate = true
		else
			colbox = { -0.125, -0.125, -0.125, 0.125, 0.125, 0.125, rotate = true }
		end

		local scale = self._scale
		for i,n in ipairs(selbox) do
			selbox[i] = n * scale
		end
		for i,n in ipairs(colbox) do
			colbox[i] = n * scale
		end

		local oldnode = self:get_node()

		self.object:set_properties({
			node = {name = node.name, param2 = node.param1 or oldnode.param1, param2 = node.param2 or oldnode.param2},
			selectionbox = selbox,
			glow = def.light_source,
			physical = def.walkable or (def.walkable == nil),
			--pointable = true, --def.pointable or (def.pointable == nil),
			collide_with_objects = def.walkable or (def.walkable == nil),
			collisionbox = colbox,
			visual_size = vector.new(scale, scale, scale)
		})

		if init then
			if def.on_construct then
				local relpos = construct_relpos(self)
				def.on_construct(relpos, self)
			end
		end
	end,
	set_scale = function(self, newscale)
		self._scale = newscale
		self:set_node(self:get_node())
	end,
	get_staticdata = function(self)
		local metadata = self._metadata and self._metadata:to_table()
		if metadata and metadata.inventory then
			for _, inv in pairs(metadata.inventory) do
				for i, v in ipairs(inv) do
					inv[i] = v:to_string()
				end
			end
		end
		return core.serialize({
			node = self:get_node(),
			metadata = metadata,
			timer = self._timer,
			scale = self._scale,
			guid = self.object:get_guid(), -- sometimes guid isn't accessible during initialization, this ensures that it's remembered
			__version = 1 -- increment when changes are backwards-incompatible
		})
	end,
})

local nodeset_deserializations = {
	function(self, data) -- version 1
		self._attachments = data.attachments or {}
		self._scale = data.scale or 1
	end,
}

core.register_entity(nodesetname, {

	initial_properties = {

		visual =  "upright_sprite",
		textures = {"blank.png", "blank.png"},

		shaded = false,
		pointable = core.settings:get_bool("nodeentity_pointable_nodeset_root", false),

	},

	add_node = function(self, pos, obj)
		obj:set_attach(self.object, "", vector.multiply(pos, 10 * self._scale))
	end,
	set_scale = function(self, newscale)
		self._scale = newscale
	end,
	on_activate = function(self, staticdata, _)
		self._attachments = {}
		self._scale = 1
		if staticdata and staticdata ~= "" then
			local data = core.deserialize(staticdata)
			if data then
				local version = data.__version or 1 -- or <latest>
				nodeset_deserializations[version](self, data)
			end
		end
	end,
	on_step = function(self, _, _)
		if not self._attachments then return end
		if not next(self._attachments) then return self.object:remove() end -- remove when no node entities are attached
		local object = self.object
		local scale = self._scale
		for pos, guid in pairs(self._attachments) do
			local child = core.objects_by_guid[guid]
			if child and child:is_valid() then
				local listpos = pos:split("|")
				child:set_attach(object, "", scale * 10 * vector.new(tonumber(listpos[1], 16) - 32768, tonumber(listpos[2], 16) - 32768, tonumber(listpos[3], 16) - 32768))
				child:get_luaentity():set_scale(scale)
			else
				self._attachments[pos] = nil
			end
		end
	end,
	on_attach_child = function(self, child)
		local _, _, attachpos = child:get_attach()
		attachpos = attachpos / (10 * self._scale)
		self._attachments[("%04x|%04x|%04x"):format(attachpos.x + 32768, attachpos.y + 32768, attachpos.z + 32768)] = child:get_guid()
	end,
	get_staticdata = function(self)
		return core.serialize({
			attachments = self._attachments,
			scale = self._scale,
			__version = 1 -- increment when changes are backwards-incompatible
		})
	end,
})

local function add_nodeentity(pos, node)
	if type(node) == "string" then node = {name = node} end
	if node.name == "ignore" or node.name == "air" then return end
	if not core.registered_nodes[node.name] then return end
	return core.add_entity(pos, entityname, core.serialize({
		node = node
	}))
end

nodeentity.add = add_nodeentity
core.register_on_mods_loaded(function()

	--[[
	local oldisprotected = core.is_protected
	core.is_protected = function(pos, player)
		local pos = convert_pos(pos)
		if pos then return oldisprotected(pos, player) end
	end
	]]

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
	vmanipmeta.set_node_at = function(self, pos, node) -- TODO: move emptiness checks to inside the added function, to avoid late write problems
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
					attachment.parent:get_luaentity():add_node(pos, newnode)
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
		for _, v in pairs(uncommited[self]) do v() end
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
			nodeset:get_luaentity():add_node(nodepos - anchor, newobject)
		end
	end end end
	return nodeset
end

local csvify_pos = function(pos)
	return core.pos_to_string(pos):gsub("[%(%)]", "")
end

local uncsvify_pos = function(str)
	local separate = str:split("@", true, 1)
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
	local fs_invloc_init = "nodemeta%:"
	local fs_invloc_init_len = #fs_invloc_init - 1
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
			local tail = j < #searched and searched:sub(j+1) or ""
			local pos = uncsvify_pos(searched:sub(i + fs_invloc_init_len, j))
			if pos then
				local entity = find_nodeentity(pos)
				if entity and entity.object then
					nformspec = nformspec .. head .. "detached:nodeentity" .. entity.object:get_guid()
				end
			end
			searched = tail
		end
		return oldshowformspec(playername, formname, nformspec, ...)
	end
end

local modpath = core.get_modpath(modname).."/"

dofile(modpath.."compat.lua") -- some mods are helplessly incompatible, this is to modify their behavior accordingly
