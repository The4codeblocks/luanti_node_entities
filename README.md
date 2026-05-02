# Node entity library (`nodeentity`)
Library for functional node entities, with minimal setup

Node entities should act exactly like normal nodes
<br><sup>any discrepancy should be reported</sup>

## Namespace reference
```lua
nodeentity = {
  function add(pos, node), -- creates a functional node entity at specified position in accordance to specified MapNode table (actually returns an ObjectRef)  
  function read_world(pos, anchor, minp, maxp), -- creates a nodeset at <pos> with nodes from <minp> to <maxp> relative to <anchor>
  function relative_pos(object), -- given a node object, a position is constructed from which to access the node entity like one'd access normal nodes
  function get(pos), -- given a position, a node entity is obtained -- returns:
    -- nodeentity, (entity if present) (pos if pos.relative is absent) (empty table if only nodeset is found) (nil if invalid pos)
    -- nodeset (nil if invalid pos)

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
  x, y, z -- position components
  relative = entityID -- optional relativity specifier; when present, the position is relative to the specified node entity or its corresponding node entity set
}
```
`core`/`vector` namespace functions and `ObjectRef`/`Voxelmanip` methods are wrapped to work with these positions
written as `nodemeta:X,Y,Z@relative` in inventory location notation
<br><sup>if any of them don't work, make an issue</sup>

## Node entity sets (`"nodeentity:nodeset"`)
2 node entities *attached* to the same nodeset share the same `pos.relative`, and exist at xyz offsets of each-other's positions

To add a node entity to a node set, attach it as specified: `nodeobject:set_attach(nodeset, "", pos * 10)`, the engine requires the pos multiplication, but the automatic inclusion of the entity works as normal

## Node definition interface
```lua
local nodedef = {
  ...
  function _nodeentity_step(self, dtime, moveresult), -- runs exclusively on node entities, identical to <step> in entity defintions
  <other callbacks> -- current entity is appended to the end of function arguments (abms and lbms included)
  ...
}
```

## Entity fields
```lua
local entity = {
  ...
  function _showfs(playername, formname, formspec), -- used like core.show_formspec, includes the nuances in node forms
  _metadata, -- imitation of NodeMetaRef
  _timer, -- Lua implementation of NodeTimerRef
  ...
}
```
