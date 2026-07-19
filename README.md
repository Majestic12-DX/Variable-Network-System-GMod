# Variable Network System — Private-by-default networked variables for Garry's Mod

A small custom system for replicating per-entity variables from server
to client written a long enough time ago. Think of it as an alternative to GMod's built-in entity vars networking solutions with two key differences:

- **Private by default.** A variable is sent only to the entity (if it's a
  player) and its owner. Widen visibility per-player with a `shareWithFunc`.
- **CreationID-keyed.** Values survive `EntIndex` reuse without ever applying to
  the wrong entity.

Supported types: `Number, Boolean, String, Table, Entity, Vector, Angle, Color`.
Entity references (including nested inside tables) are resolved on the client before
the value is applied, so you never get a dangling entity.

## Features

- Supporting many datatypes
- Private-by-default variable replication
- Public and selectively shared variables
- Automatic entity reference resolution
- Built-in type serialization
- CreationID-based entity tracking
- Global networked variables
- Automatic getter/setter/network method generation

## Install

Drop the `variable_network_system` folder into
`GarrysMod/garrysmod/addons/`

## Quick start

Register variables **on shared** (both realms must agree a variable exists):

```lua
-- Private: only the player + its owner receive it
ent:PrivateNetworkVariable("Number", "Stamina", 100)

-- Public: everyone receives it
ent:PublicNetworkVariable("Boolean", "IsGhost", false)

-- Private, but shared with some players via a server-side predicate
ent:PrivateNetworkVariable("Vector", "TeammatePos", nil, nil, function(ply, ent, owner)
    return ply:Team() == owner:Team()
end)

-- With a server-side value sanitizer
ent:PrivateNetworkVariable("Number", "Health", 100, function(v)
    return math.Clamp(v, 0, 100)
end)
```

Registering auto-generates methods on the entity:

| Method | Realm | Purpose |
|--------|-------|---------|
| `ent:Get<Name>()` | shared | current value |
| `ent:Set<Name>(v)` | server | set + replicate (returns success `bool`) |
| `ent:Network<Name>()` | server | re-send current value without changing it |
| `ent.On<Name>Change(ent, old, new)` | either | define this to react to changes |

Push all entity variables to a player (e.g. if previously-hidden variables should now be visible after some major event):

```lua
VAR_NET_SYS:SendNetworkVariablesFullUpdate(ply)
```

### Global variables

```lua
-- register once, on the world entity, on shared:
VAR_NET_SYS:SetGlobalNetworkedVariable("RoundState", 2)  -- server
VAR_NET_SYS:GetGlobalNetworkedVariable("RoundState")     -- shared
```

### Logging

```lua
VAR_NET_SYS.EnableLogging = true   -- master switch
VAR_NET_SYS.DebugEnabled  = true   -- enables DEBUG/DEV logs (also gated by `developer`)
```

## Limitations (by design / known)

- **The delta cache is not cleared on player disconnect** (`sv_sending.lua`,
  `LAST_DATA_SENT_TO_PLAYER`). A slow leak on very-long-uptime servers. Open an issue if this matters to you.
- **Mutable variables require manual networking and have no delta-compression.** 
  If a mutable object has been changed, but it's reference remains the same you may need to manually trigger networking.
  `ent:Network<Name>()`
- **`shareWithFunc` is only re-evaluated on set / owner change / full update.**
  After any entity-related event that changes who should see a variable, call
  `ent:Network<Name>()` or `VAR_NET_SYS:FullNetworkEntityNetworkData(ent)` (for all variables to re-network) yourself.
- **Variables per entity limit is 128.**
  This was done for less packet size while still providing large limit. If this bothers you, sorry, you may be doing something wrong
- **Entities outside of PVS and non-networked can stall tables.**
  Before committing the replicated table, the client ensures the validity of all entities (if there are any) in table and its sub-tables. An entity that has never been replicated to client/dropped by fullupdate may stall the whole table of valid entities for the time it is not replicated on the client. If this bothers you, open an issue. This might take some time but should be resolved in my free time

## A note on globals

For simplicity this defines a handful of bare globals: `VAR_NET_SYS`,
`IsValidEntity`, the `LOG_*` enums, and the `*_BYTE_SIZE` / `MAX_NET_SIZE` /
`CREATIONID_BYTE_SIZE` constants. If another addon defines any of these
differently, please write an issue and I'll take a look.

## Layout

```
lua/
  autorun/netvar_loader.lua      -- recursive prefix-based loader
  netvar/
    01_core/       bootstrap (globals, constants, logging), net codecs, creationid lookup
    02_network/    AddNetworkSender, netstrings, client apply-scheduler
    03_variables/  registration + data store, server setters, client request stub
    04_handlers/   server senders, client receivers
    05_entity/     Entity:PrivateNetworkVariable / PublicNetworkVariable / ClearVarNetSysData
    06_hooks/      full update on player load
```

Files are prefixed `sv_` / `sh_` / `cl_` for realm; numbered folders control
load order.

## Planned

- [ ] Direct function for initializing "global" networked variables
- [ ] Delta data cleanup on player disconnect
- [ ] Automatic networking for mutable data types
- [ ] Non-blocking entities in table verification
- [ ] Optimize clear-data packets
- [ ] Optimize mutable networking updates for less traffic (table) and GC pressure
- [ ] Client-requested value synchronization
