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
are missing — it prints the exact `apt-get` / `usermod` commands to fix them. Use `--no-install` to skip the rootfs instalation, and `--branch` to specify the script branch or tag.

To build the rootfs locally instead (slow, needs docker):

```shell
curl -fsSL https://raw.githubusercontent.com/lynoferraz/cartesi-container-env/main/install.sh \
    | sh -s -- --from-source
```

TO use a specific release of the rootfs:

```shell
curl -fsSL https://raw.githubusercontent.com/lynoferraz/cartesi-container-env/main/install.sh \
    | sh -s -- --tag v0.1.0
```
## Usage

In any project directory:

```shell
cd path/to/project
cartesi-sandbox init      # writes ./sandbox-config.json with this project's path baked in
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

For rootless **podman inside the sandbox**, also:

```shell
sudo sysctl -w kernel.unprivileged_userns_clone=1
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
```

(Persist in `/etc/sysctl.d/`.)

## Manual install (without the installer)

If you don't want to pipe a script from the internet, the manual flow still works.

```shell
mkdir ~/sandbox && cd ~/sandbox
wget https://github.com/lynoferraz/cartesi-container-env/raw/refs/heads/main/Dockerfile
wget https://github.com/lynoferraz/cartesi-container-env/raw/refs/heads/main/sandbox-config.json

docker buildx build -f Dockerfile --output type=tar,dest=docker-sandbox.tar .

mkdir -p docker-sandbox/rootfs
tar xf docker-sandbox.tar -C docker-sandbox/rootfs
sudo cp /etc/resolv.conf docker-sandbox/rootfs/etc/resolv.conf
sudo chown -R 100000:100000 docker-sandbox/rootfs/
sudo chown -R 1000:1000     docker-sandbox/rootfs/home/ubuntu/
sudo chmod 777 docker-sandbox/rootfs/tmp docker-sandbox/rootfs/var/tmp/
sudo setcap cap_setuid+ep docker-sandbox/rootfs/usr/bin/newuidmap
sudo setcap cap_setgid+ep docker-sandbox/rootfs/usr/bin/newgidmap
```

Per project:

```shell
cd path/to/project
cp ~/sandbox/sandbox-config.json .
sed -i "s#{{project_path}}#$(pwd)#g" sandbox-config.json
sed -i "s#{{project}}#$(basename $(pwd))#g" sandbox-config.json

crun run --config sandbox-config.json --bundle ~/sandbox/docker-sandbox/ $(basename $(pwd))
```

For `runc`, the config has to live in the bundle dir:

```shell
mkdir ~/sandbox/myproject
ln -sr ~/sandbox/docker-sandbox/rootfs ~/sandbox/myproject/rootfs
cp ~/sandbox/sandbox-config.json ~/sandbox/myproject/config.json
sed -i "s#{{project_path}}#$(pwd)#g"             ~/sandbox/myproject/config.json
sed -i "s#{{project}}#$(basename $(pwd))#g"      ~/sandbox/myproject/config.json
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
