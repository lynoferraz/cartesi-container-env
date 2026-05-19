# Cartesi Container Environemt

Container with cartesi tools to isolate development of Applications with AI tools. This approach creates a global 

## Requirements

- [docker](https://docs.docker.com/) to build the rootfs image.

Optionally

- [crun](https://github.com/containers/crun) to execute the container (Possible with `runc`).

## Global Setup

Copy the repo files `Dockerfile` and `sandbox-config.json` to a chosen destination where it will contain the rootfs for the container. We'll assume you you'll install in ~/sandbox

```shell
mkdir ~/sandbox
cd ~/sandbox
wget https://github.com/lynoferraz/cartesi-container-env/raw/refs/heads/main/Dockerfile
wget https://github.com/lynoferraz/cartesi-container-env/raw/refs/heads/main/sandbox-config.json
```

Build the image and generate the tar of the file system.

```shell
docker buildx build -f Dockerfile --output type=tar,dest=docker-sandbox.tar .
```

Extract the tar and finalize configurations

```shell
mkdir -p docker-sandbox/rootfs
tar xf docker-sandbox.tar -C docker-sandbox/rootfs
cp /etc/resolv.conf docker-sandbox/rootfs/etc/resolv.conf
sudo chown -R 100000:100000 docker-sandbox/rootfs/
sudo chown -R 1000:1000 docker-sandbox/rootfs/home/ubuntu/
sudo chmod 777 docker-sandbox/rootfs/tmp
sudo chmod 777 docker-sandbox/rootfs/var/tmp/
```

Also, do some final adjustments on the filesystem to enable rootless podman:

```shell
sudo setcap cap_setuid+ep docker-sandbox/rootfs/usr/bin/newuidmap
sudo setcap cap_setgid+ep docker-sandbox/rootfs/usr/bin/newgidmap
```

## Project Setup

To initiate the project with container, in the project directory:

```shell
cd path/to/project
```

Copy the template `sandbox-config.json` and customize

```shell
cp ~/sandbox/sandbox-config.json .
sed -i "s#{{project_path}}#$(pwd)#g" sandbox-config.json
sed -i "s#{{project}}#$(basename $(pwd))#g" sandbox-config.json
```

## Run Project Container (with `crun`)

```shell
crun run --config sandbox-config.json --bundle ~/sandbox/docker-sandbox/ $(basename $(pwd))
```

### Run with `runc`

With `runc` the config.json should be int the bundle directory. So instead of conpying only the file to the project dir, you should create a bundle dir with the configuration:

```shell
mkdir ~/sandbox/myproject
ln -sr ~/sandbox/docker-sandbox/rootfs ~/sandbox/docker-sandbox/rootfs
cp ~/sandbox/sandbox-config.json mkdir ~/sandbox/myproject/.
sed -i "s#{{project_path}}#$(pwd)#g" ~/sandbox/myproject/sandbox-config.json
sed -i "s#{{project}}#$(basename $(pwd))#g" ~/sandbox/myproject/sandbox-config.json
```

And the you can run with:

```shell
runc run --config sandbox-config.json --bundle ~/sandbox/myproject/ $(basename $(pwd))
```

### Secrets

The container makes the `sandbox-config.json` inaccessible, so it won't be able to change the configuration of the own container. Also it  the directory `.secrets`, so you can use this directory to add any secrets to test the application.

### Rootless Docker inside the Container

The Dockerfile install the docker tools including the rootless docker. Since you can't run docker as a service you have to run it with:

```shell
dockerd-rootless.sh > ~/.docker/docker.log 2>&1 &
```

#### Troubleshooting

**failed to start the child**

If you have errors like these when trying to start docker roUbuntu namespace permission error

```

[rootlesskit:parent] error: failed to start the child: fork/exec /proc/self/exe: operation not permitted
```

Set this allow the container to create the namespaces:

```shell
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 
sudo sysctl -w kernel.unprivileged_userns_clone=1
```

Ypu can add these configurations to `/etc/sysctl.conf` to make it permanent.

**write to `uid_map`: Operation not permitted**

If you get this error while trying to run `crun`/`runc`, make sure you have `newuidmap`/`newgidmap` installed (`uidmap` package). 

If you get the following error:

```
newuidmap: uid range X -> X not allowed
```

ensure that your user have entries in `/etc/subuid` and `/etc/subgid`. You can add with: 

```shell
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 <your_username>
```

**failed to setup UID/GID map**

```
[rootlesskit:parent] error: failed to setup UID/GID map: newuidmap XXX [0 1000 1 1 100000 165536] failed: newuidmap: write to uid_map failed: Operation not permitted
```
