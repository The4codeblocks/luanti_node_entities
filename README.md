# Node entity library (`nodeentity`)
Library for functional node entities, with minimal setup

[ContentDB page](https://content.luanti.org/packages/The4spaceconstants/nodeentity/)

Node entities should act exactly like normal nodes
<br><sup>any discrepancy should be reported</sup>

## Namespace reference
```lua
nodeentity = {
	add = function(pos, node), -- creates a functional node entity at specified position in accordance to specified MapNode table (actually returns an ObjectRef)
		-- standalone node entities are deprecated, this is for use with nodeset:add_node()
	read_world = function(pos, anchor, minp, maxp), -- creates a nodeset at <pos> with nodes from <minp> to <maxp> relative to <anchor>
	relative_pos = function(object), -- given a node object, a position is constructed from which to access the node entity like one'd access normal nodes, returns
		-- relative_pos, nodeset_exists
	get = function(pos), -- given a position, a node entity is obtained -- returns:
		-- nodeentity, (entity if present) (pos if pos.relative is absent) (empty table if only nodeset is found) (nil if invalid pos)
		-- nodeset (nil if invalid pos)
	entityname, -- name of node entity
	nodesetname, -- name of nodeset

	-- common utilities written for compatibility
	utils = {
		function pos_to_csv(pos), -- returns a csv of a position for use in nodemeta inventory location
		function csv_to_pos(str), -- inverse of the above
	},

	-- exposed internal tables
	fs_context = {
		[formname] = {
			[playername] = {formspec, entity} 
		}
	}, -- table of active forms in nodeentities
}
```

## Position format
```lua
local position = {
	x, y, z, -- position components
	relative = entityID -- optional relativity specifier; when present, the position is relative to the specified node entity or its corresponding node entity set
}
```
`core`/`vector` namespace functions and `ObjectRef`/`Voxelmanip` methods are wrapped to work with these positions
`nodemeta:X,Y,Z@relative` inventory location notation represents `{ x = X, y = Y, z = Z, relative = relative }`
<br><sup>if any of them don't work, make an issue</sup>

## Node entity sets (`"nodeentity:nodeset"`)
2 node entities *attached* to the same nodeset share the same `pos.relative`, and exist at offsets of each-other's positions.

### Entity fields
```lua
local entity = {
	...,
	_attachments = {
        [("%04x|%04x|%04x"):format(x + 32768, y + 32768, z + 32768)]
        	= entity.object:get_guid()
    }, -- internal table for updating scale of and tracking nodeentities
	_scale = 1, -- scale of nodeset, do not set directly
	set_scale = function(self, newscale), -- sets scale of nodeset
	add_node = function(pos, nodeobject), -- adds a node entity to a node set, only use if the node entity to add is already present
	...,
}
```

### Serialization fields
Some fields are omissible
```lua
local staticdata = core.serialize({
	attachments = {
		[("%04x|%04x|%04x"):format(x + 32768, y + 32768, z + 32768)]
			= entity:get_staticdata()
	}, -- table containing serialized nodeentities, indexed by position relative to nodeset
	scale = 1, -- scale of nodeset
	__version = 2 -- serialization version, do not set unless you know what you are doing
})
```

## Node definition interface
```lua
local nodedef = {
	...
	_nodeentity_step = function(self, dtime, moveresult), -- runs exclusively on node entities, identical to <step> in entity defintions
	<other callbacks> -- current entity is appended to the end of function arguments (abms and lbms included)
	...
}
```

## Entity fields
```lua
local entity = {
	...
	set_scale = function(self, newscale), -- sets scale of nodeentity
	_scale = 1, -- scale of nodeentity, do not set directly
	_metadata, -- imitation of NodeMetaRef
	_timer, -- Lua implementation of NodeTimerRef
	...
}
```

## Serialization fields
Some fields are omissible
```lua
local staticdata = core.serialize({
	node, -- MapNode *table*, do not omit!
	metadata, -- serializable table form of NodeMetaRef, take care to ensure that the inventory section uses itemstrings rather than itemstacks
	timer, -- Lua implementation of NodeTimerRef, do not set unless you know what you are doing
	scale = 1, -- nodeentity scale
	__version = 1 -- serialization version, do not set unless you know what you are doing
})
```
