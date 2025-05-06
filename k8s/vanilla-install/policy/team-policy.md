---
policy-version: 2
---

# Team-Based Network Isolation Policy

This policy extends the default Aranya policy to support team-based network isolation and access control in a k3s cluster.

## Roles & Permissions

The policy defines team-specific roles and permissions:

* Admin:
  * Manage all teams
  * Define team network policies
  * Assign team roles
  * Access all nodes

* AlphaMember:
  * Access Team Alpha nodes
  * Create/delete channels within Team Alpha
  * Configure Team Alpha network settings

* BetaMember:
  * Access Team Beta nodes
  * Create/delete channels within Team Beta
  * Configure Team Beta network settings

**Invariants**:

* Each team has its own isolated network space
* Network access between teams must be explicitly allowed
* The control plane node can communicate with all nodes
* All nodes must authenticate before joining a team

### Imports & Global Constants

```policy
use afc
use aqc
use crypto
use device
use envelope
use idam
use perspective
use team
```

### Enums & Structs

```policy
// Team roles
enum Role {
    Admin,
    AlphaMember,
    BetaMember,
}

// Team network access types
enum NetworkAccess {
    Isolated,
    Shared,
    Restricted,
}

// Team configuration
struct TeamConfig {
    team_id id,
    network_id string,
    access_type enum NetworkAccess,
}

// Team network policy
struct NetworkPolicy {
    team_id id,
    allowed_teams list<id>,
    access_type enum NetworkAccess,
}
```

### Facts

```policy
// Team configuration
fact Team[team_id id]=>{
    network_id string,
    access_type enum NetworkAccess
}

// Team network policy
fact TeamNetworkPolicy[team_id id]=>{
    allowed_teams list<id>,
    access_type enum NetworkAccess
}

// Team device role
fact TeamDeviceRole[team_id id, device_id id]=>{
    role enum Role
}

// Team network access
fact TeamNetworkAccess[team_id id, target_team_id id]=>{
    access_type enum NetworkAccess
}
```

### Functions

```policy
// Verify team exists
function verify_team(team_id id) struct TeamConfig {
    let team = check_unwrap query Team[team_id: id]
    return TeamConfig {
        team_id: id,
        network_id: team.network_id,
        access_type: team.access_type,
    }
}

// Verify team device role
function verify_team_role(team_id id, device_id id) enum Role {
    let role = check_unwrap query TeamDeviceRole[team_id: id, device_id: id]
    return role.role
}

// Check network access between teams
function can_access_team_network(source_team_id id, target_team_id id) bool {
    // Control plane can access all teams
    if source_team_id == "control-plane" {
        return true
    }
    
    let source_policy = check_unwrap query TeamNetworkPolicy[team_id: source_team_id]
    let target_policy = check_unwrap query TeamNetworkPolicy[team_id: target_team_id]
    
    // Check explicit access
    if list::contains(source_policy.allowed_teams, target_team_id) {
        return true
    }
    
    // Check shared access
    if source_policy.access_type == NetworkAccess::Shared &&
       target_policy.access_type == NetworkAccess::Shared {
        return true
    }
    
    return false
}
```

### Commands

```policy
// Create a new team
action create_team(network_id string, access_type enum NetworkAccess) {
    publish CreateTeam {
        network_id: network_id,
        access_type: access_type,
    }
}

effect TeamCreated {
    team_id id,
    network_id string,
    access_type enum NetworkAccess,
}

command CreateTeam {
    fields {
        network_id string,
        access_type enum NetworkAccess,
    }

    seal { return seal_command(serialize(this)) }
    open { return deserialize(open_envelope(envelope)) }

    policy {
        let author = get_valid_device(envelope::author_id(envelope))
        check is_admin(author.role)

        let team_id = envelope::command_id(envelope)

        finish {
            create Team[team_id: team_id]=>{
                network_id: this.network_id,
                access_type: this.access_type,
            }

            create TeamNetworkPolicy[team_id: team_id]=>{
                allowed_teams: [],
                access_type: this.access_type,
            }

            emit TeamCreated {
                team_id: team_id,
                network_id: this.network_id,
                access_type: this.access_type,
            }
        }
    }
}

// Allow network access between teams
action allow_team_access(source_team_id id, target_team_id id) {
    publish AllowTeamAccess {
        source_team_id: source_team_id,
        target_team_id: target_team_id,
    }
}

effect TeamAccessAllowed {
    source_team_id id,
    target_team_id id,
}

command AllowTeamAccess {
    fields {
        source_team_id id,
        target_team_id id,
    }

    seal { return seal_command(serialize(this)) }
    open { return deserialize(open_envelope(envelope)) }

    policy {
        let author = get_valid_device(envelope::author_id(envelope))
        check is_admin(author.role)

        let source_team = verify_team(this.source_team_id)
        let target_team = verify_team(this.target_team_id)

        finish {
            let current_policy = check_unwrap query TeamNetworkPolicy[team_id: this.source_team_id]
            let updated_teams = list::append(current_policy.allowed_teams, [this.target_team_id])

            update TeamNetworkPolicy[team_id: this.source_team_id]=>{
                allowed_teams: current_policy.allowed_teams,
                access_type: current_policy.access_type,
            } to {
                allowed_teams: updated_teams,
                access_type: current_policy.access_type,
            }

            emit TeamAccessAllowed {
                source_team_id: this.source_team_id,
                target_team_id: this.target_team_id,
            }
        }
    }
}
```

## Team Definitions

### Team Alpha
- Control Plane Node
- Agent Node 1
- Agent Node 2
- Agent Node 3
- Agent Node 4

### Team Beta
- Agent Node 5
- Agent Node 6
- Agent Node 7
- Agent Node 8
- Agent Node 9

