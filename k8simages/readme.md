# Export and Import Kubernetes Images

This guide explains how to export Docker images from an existing Kubernetes cluster and import them into a new k3d cluster. This allows you to use images locally without downloading them from the internet.

## Overview

- **Export**: Save all Docker images from your existing cluster to the `exported-images` folder
- **Import**: Load these saved images into a new k3d cluster

> ⚠️ **Note**: Currently, you need to manually adjust the `NODE="k3d-mongocluster-agent-2"` variable in the export script to get images from all nodes.

## Prerequisites

- Docker installed and running
- k3d installed
- Bash shell

## Step 1: Create a k3d Cluster

Create a new k3d cluster with 3 agent nodes:

```shell
k3d cluster create mongocluster-1 --agents 3 -p "8081:8080@server:0" --network local
```

## Step 2: Export Images

Export all images from your existing Kubernetes cluster:

1. Make the export script executable:
   ```shell
   chmod +x export-script.sh
   ```

2. Run the export script:
   ```shell
   ./export-script.sh
   ```

This will create an `exported-images` folder and save all Docker images as `.tar` files.

## Step 3: Import Images to k3d

Import the exported images into your k3d cluster:

1. Make the import script executable:
   ```shell
   chmod +x import-script.sh
   ```

2. Run the import script with your cluster name:
   ```shell
   ./import-script.sh -c mongocluster-1
   ```

## Script Options

### Import Script Options:
- `-c <cluster-name>`: Name of the k3d cluster (required)
- `-d <directory>`: Directory containing exported images (default: `./exported-images`)
- `-h`: Show help

### Examples:
```shell
# Import to cluster named 'dev'
./import-script.sh -c dev

# Import from custom directory
./import-script.sh -c dev -d /path/to/my-images
```

## Benefits

- **Faster deployments**: Images are available locally
- **Offline development**: No internet connection needed for image pulls
- **Consistent environments**: Use the exact same images across clusters

## Compatibility

> ⚠️ **Testing Note**: These scripts have been tested on MacBook M4 Pro (ARM architecture)

## Troubleshooting

- Ensure Docker daemon is running before executing scripts
- Verify k3d cluster exists before importing images
- Check that the `exported-images` directory contains `.tar` or `.tar.gz` files