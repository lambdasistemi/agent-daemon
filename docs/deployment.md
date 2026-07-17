# Deployment

The daemon must run as the same user who owns the tmux server it controls. Pick
one of the following persistence routes; all examples keep the browser origin
on localhost so it can be exposed safely through Tailscale Serve.

## NixOS system module (`configuration.nix`, not `home.nix`)

The flake exposes a NixOS module:

```nix
# flake.nix
{
  inputs.tmux-ws.url = "github:lambdasistemi/tmux-ws";

  outputs = { nixpkgs, tmux-ws, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        tmux-ws.nixosModules.default
        {
          services.tmux-ws = {
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

The primary public service is `tmux-ws`; by default it uses the private
`agent-daemon` system account and state directory for compatibility.
To control tmux sessions owned by an existing user, run the daemon as that same
user and point it at the same tmux socket directory. Replace each placeholder
below with local values; obtain the numeric id with `id -u <operator>`:

```nix
services.tmux-ws = {
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
systemd.services.tmux-ws = {
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
| `user` | string | `"agent-daemon"` | Private service account |
| `group` | string | `"agent-daemon"` | Private service group |
| `createUser` | bool | `true` | Create a dedicated system user |

## Systemd (manual)

Use a system service only when a system administrator needs to manage the
daemon. For a personal tmux server, the [user service](#systemd-user-service-for-released-linux-packages)
below is usually the better fit because it already runs as the tmux owner.
If you do need a system service, create this unit file:

```ini
# /etc/systemd/system/tmux-ws.service
[Unit]
Description=tmux-ws — browser SPA and tmux session daemon
After=network.target

[Service]
Type=simple
User=<operator>
Group=<operator-group>
WorkingDirectory=/path/to/worktrees
ExecStart=/bin/tmux-ws \
  --host 127.0.0.1 \
  --port 8080 \
  --base-dir /path/to/worktrees
Restart=on-failure
RestartSec=5
Environment=PATH=/usr/bin:/usr/local/bin
Environment=TMUX_TMPDIR=/run/user/<uid>

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now tmux-ws
journalctl -u tmux-ws -f   # watch logs
```

For a service enabled at boot, ensure `/run/user/<uid>` is created before this
unit starts (for example, enable lingering and order the unit after
`user-runtime-dir@<uid>.service`). Then configure a persistent HTTPS route as
described in [Tailscale HTTPS](tailscale.md).

## Home Manager (`home.nix`) user service

`tmux-ws` exports a NixOS module, not a Home Manager module. Put this user
service in your own `home.nix` after making the `tmux-ws` flake input available
to Home Manager through `extraSpecialArgs`:

```nix
{ inputs, pkgs, ... }:

let
  tmuxWs = inputs.tmux-ws.packages.${pkgs.stdenv.hostPlatform.system}.default;
in {
  home.packages = [ tmuxWs pkgs.tmux pkgs.git pkgs.openssh ];

  systemd.user.services.tmux-ws = {
    Unit = {
      Description = "tmux-ws browser and tmux daemon";
      After = [ "network-online.target" ];
    };
    Service = {
      ExecStart = "${tmuxWs}/bin/tmux-ws --host 127.0.0.1 --port 8080 --base-dir %h";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
```

Enable lingering once so the user service starts after reboot even before a
desktop or SSH login, then activate the service:

```bash
loginctl enable-linger "$USER"
systemctl --user enable --now tmux-ws
systemctl --user status tmux-ws
```

This service and the interactive tmux client share the same Unix user and the
default tmux socket location. Do not set `TMUX_TMPDIR` in only one of them.

## Systemd user service for released Linux packages

For an AppImage, keep the downloaded, verified file at
`~/.local/bin/tmux-ws.AppImage`, then create this user unit:

```ini
# ~/.config/systemd/user/tmux-ws.service
[Unit]
Description=tmux-ws browser and tmux daemon
After=network-online.target

[Service]
ExecStart=%h/.local/bin/tmux-ws.AppImage --host 127.0.0.1 --port 8080 --base-dir %h
Environment=APPIMAGE_EXTRACT_AND_RUN=1
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

For the released DEB or RPM, use the same unit but replace the `ExecStart`
executable with `/bin/tmux-ws` and remove the `APPIMAGE_EXTRACT_AND_RUN`
environment line. Released packages carry their own SPA files, so neither unit
needs a `--static-dir` argument.

```bash
loginctl enable-linger "$USER"
systemctl --user daemon-reload
systemctl --user enable --now tmux-ws
journalctl --user -u tmux-ws -f
```

## Direct binary

Build with nix and copy the binary:

```bash
nix build .#default
# result/bin/tmux-ws

# Or run directly:
nix run .#default -- --host 127.0.0.1 --port 8080 --base-dir /code
```

## Legacy configuration migration

`services.agent-daemon` is a compatibility alias for `services.tmux-ws` in
this corrective release. Rename it in configuration and operate the resulting
single `tmux-ws` unit; do not enable a second legacy daemon. The alias is
limited to this corrective release and removal requires a separately reviewed
migration ticket.
