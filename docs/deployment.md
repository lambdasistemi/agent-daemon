# Deployment

## NixOS module

The flake exposes a NixOS module:

```nix
# flake.nix
{
  inputs.agent-daemon.url = "github:lambdasistemi/tmux-ws";

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
To control tmux sessions owned by an existing user, run the daemon as that same
user and point it at the same tmux socket directory. Replace each placeholder
below with local values; obtain the numeric id with `id -u <operator>`:

```nix
services.agent-daemon = {
  enable = true;
  host = "127.0.0.1";
  port = 8080;
  baseDir = "/path/to/worktrees";
  user = "<operator>";
  group = "<operator-group>";
  createUser = false;
};

# Keep the user's runtime directory available for the boot-started service.
users.users."<operator>".linger = true;
systemd.services.agent-daemon = {
  after = [ "user-runtime-dir@<uid>.service" ];
  requires = [ "user-runtime-dir@<uid>.service" ];
  environment.TMUX_TMPDIR = "/run/user/<uid>";
};
```

`tmux` locates its server through a Unix socket. An interactive shell may set
`TMUX_TMPDIR`, but a system service does not inherit that shell environment.
Without the explicit setting, the daemon can start successfully yet look in a
different socket directory and report no sessions. `/run/user/<uid>` is the
existing user's private, reboot-stable runtime location: systemd recreates it
with the right ownership at boot, and both the user's tmux processes and the
daemon can consistently use it. Set the same `TMUX_TMPDIR` when starting tmux
outside the service.

Do not use another user's runtime directory or copy tmux sockets between
directories. The service user, tmux owner, numeric uid, and runtime directory
must agree.

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
User=<operator>
Group=<operator-group>
WorkingDirectory=/path/to/worktrees
ExecStart=/usr/local/bin/agent-daemon \
  --host 127.0.0.1 \
  --port 8080 \
  --base-dir /path/to/worktrees \
  --static-dir /usr/local/share/agent-daemon/static
Restart=on-failure
RestartSec=5
Environment=PATH=/usr/bin:/usr/local/bin
Environment=TMUX_TMPDIR=/run/user/<uid>

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now agent-daemon
journalctl -u agent-daemon -f   # watch logs
```

For a service enabled at boot, ensure `/run/user/<uid>` is created before this
unit starts (for example, enable lingering and order the unit after
`user-runtime-dir@<uid>.service`). Then configure a persistent HTTPS route as
described in [Tailscale HTTPS](tailscale.md).

## Direct binary

Build with nix and copy the binary:

```bash
nix build .#default
# result/bin/agent-daemon

# Or run directly:
nix run .#default -- --host 127.0.0.1 --port 8080 --base-dir /code
```
