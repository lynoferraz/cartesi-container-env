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
mkdir -p docker-sandbox
sudo mkdir docker-sandbox/rootfs
sudo tar xf docker-sandbox.tar -C docker-sandbox/rootfs
sudo cp /etc/resolv.conf docker-sandbox/rootfs/etc/resolv.conf
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
sudo crun run --config sandbox-config.json --bundle ~/sandbox/docker-sandbox/ $(basename $(pwd))
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
sudo runc run --config sandbox-config.json --bundle ~/sandbox/myproject/ $(basename $(pwd))
```

### Secrets

The container makes the `sandbox-config.json` inaccessible, so it won't be able to change the configuration of the own container. Also it  the directory `.secrets`, so you can use this directory to add any secrets to test the application.
