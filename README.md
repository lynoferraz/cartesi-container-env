# Cartesi Container Environment

A rootless OCI sandbox preloaded with Cartesi tooling (cartesi-machine, cartesi-cli, foundry,
alto, podman, node, claude-code, …) for isolated development of Cartesi applications and AI
agents.

## Quick install

```shell
curl -fsSL https://raw.githubusercontent.com/lynoferraz/cartesi-container-env/main/install.sh | sh
```

This drops `cartesi-sandbox` into `~/.local/bin/`, downloads a CI-built rootfs tarball for
your architecture from GitHub Releases, verifies it against `SHA256SUMS`, and installs it
under `~/.local/share/cartesi-sandbox/`. The installer aborts early if host prerequisites
are missing — it prints the exact `apt-get` / `usermod` commands to fix them. Use `--no-install` to skip the rootfs installation, and `--branch` to specify the branch or tag the script, Dockerfile and config template are fetched from.

To build the rootfs locally instead (slow, needs docker with buildx). The Dockerfile is
self-contained, so only it is downloaded — no clone of this repo is needed:

```shell
curl -fsSL https://raw.githubusercontent.com/lynoferraz/cartesi-container-env/main/install.sh \
    | sh -s -- --from-source
```

(`--from-source --tag v0.4.0` builds the Dockerfile of that tag instead of `main`.)

To use a specific release of the rootfs:

```shell
curl -fsSL https://raw.githubusercontent.com/lynoferraz/cartesi-container-env/main/install.sh \
    | sh -s -- --tag v0.4.0
```
## Usage

In any project directory:

```shell
cd path/to/project
cartesi-sandbox init      # writes ./sandbox-config.json from the template, with this project's path baked in
cartesi-sandbox run       # exec into the sandbox (uses crun if available, else runc)
```

The current directory is bind-mounted at `/projects/<basename>` inside the sandbox, and
becomes the container's working directory. `./sandbox-config.json` itself is masked over
`/dev/null` inside the container so the sandboxed code can't tamper with its own runtime
config. The `.secrets/` directory in the project is also masked — use it for test secrets
you do NOT want exposed to the agent.

when you run the sand box for the first time, install you favorite AI tool, and it will be available on every sandboxes


### Other subcommands

| Command                          | What it does                                    |
|----------------------------------|-------------------------------------------------|
| `cartesi-sandbox doctor`         | Check host prereqs and print fixes               |
| `cartesi-sandbox update`         | Re-download / rebuild the rootfs                 |
| `cartesi-sandbox uninstall`      | Remove the installation                          |
| `cartesi-sandbox version`        | Print version                                    |

## Host prerequisites

`cartesi-sandbox doctor` checks all of these. None are installed automatically — run the
suggested commands yourself:

- **OCI runtime**: `crun` (preferred) or `runc` — `sudo apt-get install -y crun`
- **uidmap tools**: `newuidmap` / `newgidmap` — `sudo apt-get install -y uidmap`
- **subuid/subgid entries** for your user — `sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER`
- **zstd** (for extracting the release tarball) — `sudo apt-get install -y zstd`
- **/dev/net/tun** readable and writable by your user (it is bind-mounted into the sandbox for
  podman's rootless networking) — `sudo modprobe tun` (normally present and mode 0666)

For rootless **podman inside the sandbox**, also:

```shell
sudo sysctl -w kernel.unprivileged_userns_clone=1
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
```

(Persist in `/etc/sysctl.d/`.)

### Podman inside the sandbox

`sandbox-config.template.json` is tuned so that rootless podman works nested inside the
rootless sandbox:

- `/proc` is mounted without masked or read-only sub-paths. The kernel refuses a new `proc`
  mount in a nested user namespace while the parent `/proc` has such overmounts, which breaks
  `podman run` and every `RUN` step of `podman build`. In a rootless sandbox the user
  namespace already blocks what those masks guard; `/sys/firmware` and `.secrets` stay masked.
- `/dev/net/tun` is bind-mounted from the host so pasta can set up per-container networks
  and publish ports.
- `/run/user/1000` is a per-session tmpfs and `XDG_RUNTIME_DIR` points at it, so podman's
  runtime state (pause process pid, sockets, locks) never leaks from one session into the next.
- `docker` is a shim over `podman` / `podman-compose` (defined inline in the `Dockerfile`,
  installed at `/usr/bin/docker`). It keeps
  argument quoting intact, answers the version probes of the cartesi CLI, remembers compose
  files passed on stdin per project (stored as `.docker-shim.<project>.compose.yml` plus a
  `.docker-shim.<project>.configs/` directory in the project directory until `compose down`;
  add both to your `.gitignore`), rewrites compose `configs` into bind mounts (podman-compose
  ignores them, which would leave the `cartesi run` proxy without routes), and starts
  `podman-healthcheck-runner`, which runs container healthchecks because there is no systemd
  to schedule them. Set `DOCKER_SHIM_DEBUG=1` to see the podman commands it runs.

## Manual install (without the installer)

If you don't want to pipe a script from the internet, the manual flow still works. Building
the rootfs needs only the `Dockerfile` (every file it installs is inlined in it and everything
else is fetched during the build), so there is nothing to clone. Use an empty directory as the
build context so nothing else is sent to the builder:

```shell
mkdir -p ~/sandbox/build && cd ~/sandbox/build
curl -fsSLO https://raw.githubusercontent.com/lynoferraz/cartesi-container-env/main/Dockerfile

docker buildx build -f Dockerfile --output type=tar,dest=../docker-sandbox.tar .
cd ..

mkdir -p docker-sandbox/rootfs
tar xf docker-sandbox.tar -C docker-sandbox/rootfs
sudo cp /etc/resolv.conf docker-sandbox/rootfs/etc/resolv.conf
# SUBUID is the start of your range in /etc/subuid (e.g. 100000); the sandbox's root maps to it,
# and the sandbox's "ubuntu" user (uid 1000 inside) maps to your own uid.
SUBUID=$(grep "^$USER:" /etc/subuid | cut -d: -f2)
sudo chown -R $SUBUID:$SUBUID     docker-sandbox/rootfs/
sudo chown -R $(id -u):$(id -g)   docker-sandbox/rootfs/home/ubuntu/
sudo chown -R $(id -u):$(id -g)   docker-sandbox/rootfs/opt/venv
sudo chmod 777 docker-sandbox/rootfs/tmp docker-sandbox/rootfs/var/tmp/
sudo setcap cap_setuid+ep docker-sandbox/rootfs/usr/bin/newuidmap
sudo setcap cap_setgid+ep docker-sandbox/rootfs/usr/bin/newgidmap
sudo mkdir -p docker-sandbox/rootfs/run/user/1000
sudo chown $(id -u):$(id -g) docker-sandbox/rootfs/run/user/1000
```

Per project (the template's quoted `{{...}}` placeholders become numbers; `cartesi-sandbox init`
does the same substitutions):

```shell
cd path/to/project
curl -fsSL https://raw.githubusercontent.com/lynoferraz/cartesi-container-env/main/sandbox-config.template.json \
    -o sandbox-config.json
sed -i "s#{{project_path}}#$(pwd)#g" sandbox-config.json
sed -i "s#{{project}}#$(basename $(pwd))#g" sandbox-config.json
sed -i -e "s#\"{{host_uid}}\"#$(id -u)#g" -e "s#\"{{host_gid}}\"#$(id -g)#g" \
       -e "s#\"{{subuid_start}}\"#$SUBUID#g" -e "s#\"{{subgid_start}}\"#$SUBUID#g" \
       -e "s#\"{{subuid_start_plus_1}}\"#$((SUBUID+1))#g" -e "s#\"{{subgid_start_plus_1}}\"#$((SUBUID+1))#g" \
       -e "s#\"{{subuid_size_minus_1}}\"#65535#g" -e "s#\"{{subgid_size_minus_1}}\"#65535#g" \   # (range size - 1)
       sandbox-config.json

crun run --config sandbox-config.json --bundle ~/sandbox/docker-sandbox/ $(basename $(pwd))
```

For `runc`, the config has to live in the bundle dir:

```shell
mkdir ~/sandbox/myproject
ln -sr ~/sandbox/docker-sandbox/rootfs ~/sandbox/myproject/rootfs
cp sandbox-config.json ~/sandbox/myproject/config.json   # the substituted file from above
runc run --bundle ~/sandbox/myproject/ $(basename $(pwd))
```

## Troubleshooting

**`[rootlesskit:parent] error: failed to start the child: fork/exec /proc/self/exe: operation not permitted`**

```shell
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
sudo sysctl -w kernel.unprivileged_userns_clone=1
```

**`write to uid_map: Operation not permitted`** — install `uidmap` and check `/etc/subuid` / `/etc/subgid` as above.

**`newuidmap: uid range X -> X not allowed`** — add the subuid range:

```shell
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER
```

**`mount \`proc\` to \`proc\`: Operation not permitted`** (from `podman run` or a `RUN` step of
`podman build`) — the sandbox was started with an old `sandbox-config.json` that masks paths
under `/proc`. Re-run `cartesi-sandbox init` to regenerate it from the current template and
start a new session.

**`pasta failed with exit code 1: ... Failed to open() /dev/net/tun`** — same cause: the old
config does not bind-mount `/dev/net/tun`. Regenerate the config as above and check
`cartesi-sandbox doctor` on the host.

**`podman stop` reports `given PID did not die within timeout` / containers stuck in `Stopping`**
— the container was started with `--pid host` (or `pidns = "host"` in a containers.conf),
which leaves podman no cgroup to signal. Kill the process by hand (`podman inspect --format
'{{.State.Pid}}'`, then `kill -9`), remove the `pidns`/`netns` overrides from
`~/.config/containers/containers.conf`, and use the current template so containers get their
own pid namespace.

**Containers stay `starting` and `cartesi run` never becomes ready** — healthchecks are not
being executed. `podman-healthcheck-runner status` should say running; `docker compose up`
starts it automatically, or start it by hand with `podman-healthcheck-runner start`.

### Updating an existing installation

After pulling a new template, run `cartesi-sandbox init` again in each project and start a
new session. If podman inside your sandbox already has an image store, it keeps the old
runtime directories recorded in its database (`/tmp/containers-user-1000`,
`/tmp/podman-run-1000`); run `podman system reset` once inside the sandbox to move to the
per-session `XDG_RUNTIME_DIR` (this deletes local images and containers, which are re-pulled
on demand).

To patch a rootfs in place instead of re-installing it, extract just the shim files from a
freshly built rootfs tar (see "Manual install" above for building `docker-sandbox.tar`) and
give them back to the sandbox's root (the start of your subuid range):

```shell
ROOTFS=~/.local/share/cartesi-sandbox/bundle/rootfs
sudo tar -xf docker-sandbox.tar -C "$ROOTFS" \
    usr/bin/docker usr/local/bin/podman-healthcheck-runner usr/local/bin/docker-shim-compose-fixup etc/containers
SUBUID=$(grep "^$USER:" /etc/subuid | cut -d: -f2)
sudo chown -R "$SUBUID:$SUBUID" "$ROOTFS/usr/bin/docker" "$ROOTFS/usr/local/bin" "$ROOTFS/etc/containers"
```

Then delete any `netns`, `pidns` or `helper_binaries_dir` lines from
`$ROOTFS/home/ubuntu/.config/containers/containers.conf`. (`cartesi-sandbox update` does a full
re-install instead.)
