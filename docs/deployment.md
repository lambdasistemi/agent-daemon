# Deployment

## NixOS module

The flake exposes a NixOS module:

```nix
# flake.nix
{
  inputs.agent-daemon.url = "github:lambdasistemi/agent-daemon";

  outputs = { nixpkgs, agent-daemon, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        agent-daemon.nixosModules.default
        {
          services.agent-daemon = {
            enable = true;
            host = "127.0.0.1";
            port = 8080;
            baseDir = "/code";
          };
        }
      ];
    };
  };
}
```

By default the module creates a dedicated `agent-daemon` system user.
To run as an existing user instead:

```nix
services.agent-daemon = {
  enable = true;
  host = "127.0.0.1";
  port = 8080;
  baseDir = "/code";
  user = "paolino";
  group = "users";
  createUser = false;
};
```

### Module options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable the service |
| `host` | string | `"*"` | Address to bind to |
| `port` | port | `8080` | HTTP port |
| `baseDir` | path | `/var/lib/agent-daemon` | Root for worktrees |
| `staticDir` | path | (from flake) | Web UI files |
| `package` | package | (from flake) | The binary to use |
| `user` | string | `"agent-daemon"` | User to run as |
| `group` | string | `"agent-daemon"` | Group to run as |
| `createUser` | bool | `true` | Create a dedicated system user |

## Systemd (manual)

If you're not on NixOS, create a unit file:

```ini
# /etc/systemd/system/agent-daemon.service
[Unit]
Description=Agent daemon — Claude Code session manager
After=network.target

[Service]
Type=simple
User=paolino
Group=users
WorkingDirectory=/code
ExecStart=/usr/local/bin/agent-daemon \
  --host 127.0.0.1 \
  --port 8080 \
  --base-dir /code \
  --static-dir /usr/local/share/agent-daemon/static
Restart=on-failure
RestartSec=5
Environment=PATH=/usr/bin:/usr/local/bin

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now agent-daemon
journalctl -u agent-daemon -f   # watch logs
```

## Direct binary

Build with nix and copy the binary:

```bash
nix build .#default
# result/bin/agent-daemon

# Or run directly:
nix run .#default -- --host 127.0.0.1 --port 8080 --base-dir /code
```
