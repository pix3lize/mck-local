# How to Install MongoDB Connector for Kubernetes (MCK) Locally

## Background 
MongoDB Connector for Kubernetes version 1.3+ supports ARM processors. This repository provides a guide for installing MCK locally on your MacBook (ARM) using Docker, k3d, kubectl, and k9s.

## 🦺 Prerequisites 
Before starting, make sure you have:
- **Homebrew** installed on your Mac (makes installing dependencies easier)
- **Required tools**: Docker, kubectl, helm, k3d, and k9s
- **Good internet connection** 
- **AI assistant** (ChatGPT or similar) available for troubleshooting

## 🧩 Setup: Aliases and kubectl Context
1. **Set kubectl context** to the appropriate Kubernetes config
2. **Add these useful aliases** for the tutorial:
```shell
alias kba="kubectl apply -f"
alias kbd="kubectl delete -f"
```

## K3D Setup

### Create k3d Cluster Locally

**Prerequisites**: Docker and kubectl must be installed.

**Install k3d** using Homebrew:
```shell
brew install k3d
```
**Create the local network**:
```shell
docker network create --driver bridge --subnet 10.0.0.0/24 --gateway 10.0.0.1 local
```

**Create the cluster**:
```shell
k3d cluster create mongocluster --agents 3 -p "8081:8080@server:0" --network local
```

> ⚠️ **Warning**: Due to the k3s [bug](https://github.com/k3s-io/k3s/issues/12844) please use this parameters. Please check if the lastest images already included the fix 

Temporary solution : 
```shell
k3d cluster create mongocluster --agents 3 -p "8081:8080@server:0" --network local --image "rancher/k3s:v1.31.6-k3s1
```

![Container Setup](img/container.png)

## MongoDB Connector for Kubernetes (MCK) Setup

For detailed information, see the [official documentation](https://www.mongodb.com/docs/kubernetes/current/kind-quick-start/).

#### Step 1: Add MongoDB Helm Repository
```shell
helm repo add mongodb https://mongodb.github.io/helm-charts
```

#### Step 2: Install Custom Resource Definitions (CRDs)
```shell
kubectl apply -f https://raw.githubusercontent.com/mongodb/mongodb-kubernetes/1.4.0/public/crds.yaml
```

#### Step 3: Install MongoDB Kubernetes Operator
```shell
helm upgrade --install mongodb-kubernetes-operator mongodb/mongodb-kubernetes \
--namespace mongodb \
--create-namespace
```

#### Step 4: Deploy OpsManager
```shell
kba opsmanager.yaml
```

> ⚠️ **Warning**: This process may take a long time. If you're using a VPN, consider disabling it during installation.

This creates:
- `ops-manager-svc` load balancer service
- `ops-manager-svc-ext` service

**Internal cluster access**: `http://ops-manager-svc.mongodb.svc.cluster.local:8080`

#### Step 5: Access OpsManager in Browser
Since we forwarded port 8080 to 8081 on the host:
```
http://localhost:8081
```

#### Step 6: Configure OpsManager Project
1. **Create an account** in OpsManager
2. **Configure the project** to generate the config map for MongoDB resources

![OpsManager Setup](img/image.png)

> ⚠️ **Important**: Add the correct IP address range. Check your Kubernetes services for reference.

**For k3d clusters**, run this command to get the CIDR range:
```shell
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.podCIDR}{"\n"}{end}'
```

![CIDR Information](img/cidr.png)

#### Step 7: Apply Project Configuration
The setup generates a config map and secret. Apply the combined configuration:
```shell
kba project1.yaml
```

![Config Map Setup](img/configmap.png)

## 🔐 Certificate Setup with Jetstack

#### Step 1: Install cert-manager
```shell
helm repo add jetstack https://charts.jetstack.io
```

```shell
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --set crds.enabled=true --create-namespace
```

#### Step 2: Create Custom Certificate Authority (CA)
```shell
kba ca-issuer.yaml
```

#### Step 3: Extract CA Certificate
```shell
kubectl get secret mongodb-root-ca-cert-rsa -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d > ca.crt
```

#### Step 4: Create ConfigMap for CA Certificate
```shell
kubectl create configmap mongo-ca -n mongodb --from-file=ca-pem=ca.crt
```

## Install MongoDB Resources with MCK

#### Step 1: Install MongoDB Certificate
```shell
kba certificate1.yaml
```

#### Step 2: Deploy MongoDB Replica Set
```shell
kba replica-external.yaml
```

> ⚠️ **Warning**: This process may take a long time. Consider disabling VPN if you're behind one.

**Result**: Your replica set will appear in OpsManager:

![Replica External](img/replicaexternal.png)

#### Step 3: Internal Database Access
Use this connection string for internal cluster access:
```shell
mongosh "mongodb://ituser:ituser@replica-external-0.replica-external-svc.mongodb.svc.cluster.local:27017,replica-external-1.replica-external-svc.mongodb.svc.cluster.local:27017,replica-external-2.replica-external-svc.mongodb.svc.cluster.local:27017/?replicaSet=replica-external&tls=true&tlsAllowInvalidCertificates=true"
```

## External Database Access Setup

#### Step 1: Create NodePort Services
```shell
kba services-nodeport.yaml
```

> ⚠️ **Note**: If you modify the replica-external deployment, wait for completion and re-run this command.

**Check the created services**:

![NodePort Services](img/nodeport.png)

Note your ports (example: `30001, 30002, 30003`).

#### Step 2: Configure k3d Port Forwarding
```shell 
k3d cluster edit mongocluster --port-add "30001:30001@server:0"
k3d cluster edit mongocluster --port-add "30002:30002@server:0"
k3d cluster edit mongocluster --port-add "30003:30003@server:0"
```

#### Step 3: Update /etc/hosts File
Add these entries to your `/etc/hosts` file:
```
127.0.0.1 replica-external-0.mongodb.local
127.0.0.1 replica-external-1.mongodb.local
127.0.0.1 replica-external-2.mongodb.local
```

#### Step 4: Update Replica Set Configuration
Update the `replica-external.yaml` file with the correct hostnames:
```yaml
connectivity:
  replicaSetHorizons:
    # For external client access
    - "external-horizon": "replica-external-0.mongodb.local:30001"
    - "external-horizon": "replica-external-1.mongodb.local:30002"
    - "external-horizon": "replica-external-2.mongodb.local:30003"
```

#### Step 5: External Connection String
Use this connection string for external access:
```shell
mongodb://ituser:ituser@replica-external-0.mongodb.local:30001,replica-external-1.mongodb.local:30002,replica-external-2.mongodb.local:30003/?tls=true&tlsAllowInvalidCertificates=true&replicaSet=replica-external
```

## MongoDB Search Setup

This section sets up MongoDB Search and Vector Search using the existing replica-external cluster.

#### Step 1: Install MongoDB Search
```shell
kba replica-external-search.yaml
```

This creates two users:
- `mdb-admin` (root access)
- `search-sync-source`

#### Step 2: Recreate NodePort Services
```shell
kba services-nodeport.yaml
```

#### Step 3: Deploy MongoDB Tools Pod
```shell 
kba mongodb-tools-pod.yaml
```

This pod helps verify the MongoDB Search deployment.

#### Step 4: Access the Tools Pod
Use k9s or VS Code extension to shell into the pod:

![Shell Access](img/shell.png)

#### Step 5: Download Sample Dataset
```shell
curl https://atlas-education.s3.amazonaws.com/sample_mflix.archive -o /tmp/sample_mflix.archive
```

#### Step 6: Configure Environment Variables
Set up the connection string using the root user:
```shell
export MDB_CONNECTION_STRING="mongodb://mdb-admin:adminpassword@replica-external-0.replica-external-svc.mongodb.svc.cluster.local:27017,replica-external-1.replica-external-svc.mongodb.svc.cluster.local:27017,replica-external-2.replica-external-svc.mongodb.svc.cluster.local:27017/?replicaSet=replica-external&tls=true&tlsInsecure=true"
```

#### Step 7: Test Connection
```shell
mongosh $MDB_CONNECTION_STRING
```

#### Step 8: Restore Sample Data
```shell
mongorestore \
  --archive=/tmp/sample_mflix.archive \
  --verbose=1 \
  --drop \
  --nsInclude 'sample_mflix.*' \
  --uri="${MDB_CONNECTION_STRING}"
```

#### Step 9: Create Search Index
```shell
mongosh --quiet \
    "${MDB_CONNECTION_STRING}" \
    --eval "use sample_mflix" \
    --eval 'db.movies.createSearchIndex("default", { mappings: { dynamic: true } });'
```

#### Step 10: Test MongoDB Search
Run this search query:
```js
use sample_mflix;

db.movies.aggregate([
  {
    $search: {
      "compound": {
        "must": [ {
          "text": {
            "query": "baseball",
            "path": "plot"
          }
        }],
        "mustNot": [ {
          "text": {
            "query": ["Comedy", "Romance"],
            "path": "genres"
          }
        } ]
      },
      "sort": {
        "released": -1
      }
    }
  },
  {
    $limit: 3
  },
  {
    $project: {
      "_id": 0,
      "title": 1,
      "plot": 1,
      "genres": 1,
      "released": 1
    }
  }
]);
```

**Expected result**:
```js
{
  plot: 'A sports agent stages an unconventional recruitment strategy to get talented Indian cricket players to play Major League Baseball.',
  genres: [ 'Biography', 'Drama', 'Sport' ],
  title: 'Million Dollar Arm',
  released: ISODate('2014-05-16T00:00:00.000Z')
}
```

![Search Results](img/resultsearch.png)

## Additional Project: Non-TLS Replica Set

This section creates a second project called "MongoDBUser" without TLS encryption.

![Project 2](img/project2.png)

#### Step 1: Provision Project 2
```shell
kba project2.yaml
```

#### Step 2: Deploy Non-TLS Replica Set
```shell
kba replica-user.yaml
```

#### Step 3: Connection String for Project 2
```shell
mongodb://admin:adminpassword@replica-user-0.replica-user-svc.mongodb.svc.cluster.local:27017,replica-user-1.replica-user-svc.mongodb.svc.cluster.local:27017,replica-user-2.replica-user-svc.mongodb.svc.cluster.local:27017/?replicaSet=replica-user
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

We welcome contributions! Here's how you can help:

### How to Contribute

1. **Fork** the repository
2. **Create a feature branch**: `git checkout -b feature/improvement`
3. **Make and test** your changes thoroughly
4. **Commit**: `git commit -m 'Add some improvement'`
5. **Push**: `git push origin feature/improvement`
6. **Open a Pull Request**

### Guidelines

- Test changes with the latest tool versions
- Test on both ARM and x86 architectures when possible
- Update documentation for new features
- Follow existing code style
- Write clear commit messages

### Reporting Issues

When reporting problems:

1. Check existing issues first
2. Create a new issue with:
   - Clear problem description
   - Steps to reproduce
   - Environment details (OS, tool versions)
   - Expected vs actual behavior

### Getting Help

- Open an issue for bugs or feature requests
- Check official MongoDB Kubernetes documentation
- Consult k3d and kubectl documentation for cluster issues