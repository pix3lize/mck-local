## How to Install MongoDB Connector for Kubernetes (MCK)  locally 

#### Background 
Since MongoDB Connector for Kubernetes 1.3 support ARM processor.  

This repository is a guide for those who would like to install MCK locally on your Macbook (ARM) utilising docker, k3d, kubectl, and k9s 

#### Pre-requisite 
- Homebrew installed on your mac as this make life easier to install other dependencies
- Install docker, kubectl, helm, k3d, and k9s 
- Good internet connection 
- Have a chat GPT or your prefer AI friend handy in case if you facing an issue 

### K3D 

##### Create k3d cluster locally

This setup assuming that you already install docker and kubectl 

The easiest to install k3d is using homebrew

```shell
k3d cluster create mongocluster --agents 3 -p\
 "8080:8080@server:0" --network local
```
![alt text](img/container.png)

## Mongodb Connector for Kubernetes (MCK) Setup
##### Install mongodb connector for kubernetes

For more information please look into official document : https://www.mongodb.com/docs/kubernetes/current/kind-quick-start/

##### Using helm 
```shell
helm repo add mongodb https://mongodb.github.io/helm-charts
```

##### Install the CRD (Custom Resources Definition)
```shell
kubectl apply\
 -f https://raw.githubusercontent.com/mongodb/mongodb-kubernetes/1.4.0/public/crds.yaml
```

##### Install with helm with mongodb namespace (this is best practise)
```shell
helm upgrade --install mongodb-kubernetes-operator mongodb/mongodb-kubernetes \
--namespace mongodb \
--create-namespace
```

##### Run the opsmanager.yaml
```shell
kba opsmanager.yaml
```
This definition will create a ops-manager-svc load balancer services and ops-manager-svc-ext services 

To connect within kubernetes internally it use default host name which 

http://ops-manager-svc.mongodb.svc.cluster.local:8080


##### Forward port 8080 to localhost 
```shell
kubectl port-forward service/ops-manager-svc 8080:8080 -n mongodb
```

##### Provision project 
Please create the account and start prepare the ops manager to produce config map that will be used by MongoDB resource to connect to the ops manager 

![alt text](img/image.png)

```⚠️ Please ensure you add the correct ip address range on this. You can refer to services on your kubernetes```

Run this command if you're running with k3d 
```shell
kubectl get nodes -o jsonpath=\
'{range .items[*]}{.metadata.name}{"\t"}{.spec.podCIDR}{"\n"}{end}'
```

![alt text](img/cidr.png)

It will produce this config map setup and secret 

![alt text](img/configmap.png)

I combined this secret and config map into project.yaml, so please run this : 

```shell
kba project1.yaml
```

## Jetstack / Certificate Setup

##### Install jetstack io to allow self sign certificate on kubernetes
```shell
helm repo add jetstack https://charts.jetstack.io
```

```shell
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --set crds.enabled=true --create-namespace
```

##### Create custom CA (Certificate Authority)

```shell
kba ca-issuer.yaml
```

##### Get the CA certificate 
```shell
kubectl get secret mongodb-root-ca-cert-rsa -n \
cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d > ca.crt
```

##### Create config map for CA certificate
```shell
kubectl create configmap mongo-ca -n mongodb --from-file=ca-pem=ca.crt
```

## Install MongoDB resources with MCK

##### Install certificate for mongodb database 
```shell
kba certificate1.yaml
```

##### Install replica-external with NodePort 
```shell
kba replica-external.yaml
```

⚠️ Please be warn this process might be taking quite long, if you have a VPN behind would recommend to disabled it 

Once it's completed this would look like this from Ops Manager

![alt text](img/replicaexternal.png)

To access it internally please use this : 
```shell
mongosh "mongodb://ituser:ituser@\
replica-external-0.replica-external-svc.mongodb.svc.cluster.local:27017\
,replica-external-1.replica-external-svc.mongodb.svc.cluster.local:27017\
,replica-external-2.replica-external-svc.mongodb.svc.cluster.local:27017\
/?replicaSet=replica-external&tls=true&tlsAllowInvalidCertificates=true"
```

------------ 

#### How access the DB it externally 

This method is quite interesting as we need to perhaps edit/update the node port number on k3d 

Please refer to the services created after running this query 

![alt text](img/nodeport.png)

Follow your port on the picture it's ```31945, 32217, and 30523```.

Run this command to update k3d 
```shell 
k3d cluster edit mongocluster --port-add "31945:31945@server:0"
k3d cluster edit mongocluster --port-add "32217:32217@server:0"
k3d cluster edit mongocluster --port-add "30523:30523@server:0"
```

Once it's done plese update your /etc/hosts file on macbook 
```csharp
127.0.0.1 replica-external-0.mongodb.local
127.0.0.1 replica-external-1.mongodb.local
127.0.0.1 replica-external-2.mongodb.local
```

You also need to update the horizon on ```replica-external.yaml``` to make it works
```yaml
  connectivity:
    replicaSetHorizons:
      # So that clients outside the K8S cluster can access the cluster
      # Must match externalService.annotations.external-dns.alpha.kubernetes.io/hostname
      # REPLACE THIS - Change to your own Route 53 domain
      - "external-horizon": "replica-external-0.mongodb.local:31945"
      - "external-horizon": "replica-external-1.mongodb.local:32217"
      - "external-horizon": "replica-external-2.mongodb.local:30523"
```

This would be the connection string 

```shell
mongodb://ituser:ituser@replica-external-0.mongodb.local:31945\
,replica-external-1.mongodb.local:32217\
,replica-external-2.mongodb.local:30523\
/?tls=true&tlsAllowInvalidCertificates=true&\
replicaSet=replica-external
```
-----
### Add second project with authentication 

The new project name would be MongoDBUser, below is how it looks like 

![alt text](img/project2.png)

#### Provision the project
```shell
kba project2.yaml
```

#### Install the replica-user
```shell
kba replica-user.yaml
```

The connection string as follow 
```shell
mongodb://admin:adminpassword\
@replica-user-0.replica-user-svc.mongodb.svc.cluster.local:27017,\
replica-user-1.replica-user-svc.mongodb.svc.cluster.local:27017,\
replica-user-2.replica-user-svc.mongodb.svc.cluster.local:27017/\
?replicaSet=replica-user
```

## Install MongoDBSearch resources with MCK 

For MongoDB Search and Vector Search, we're going to use replica-user cluster and MongoDBUser project.

#### Install MongoDB Search 
```shell
kba replica-user-search.yaml
```
This resources will create two users : mdb-admin (root access) and search-sync-source. 

#### Install the mongodb-tools-pod.yaml
```shell 
kba mongodb-tools-pod.yaml
```
This pod will be useful to check, if we're deploying the MongoDB Search correctly 

#### Shell to the pod

![alt text](img/shell.png)
To exec shell to pod you can use k9s or VSCode extension, once you're in the shell on the pod please run this command below

##### Download the dataset 
```shell
curl https://atlas-education.s3.amazonaws.com/sample_mflix.archive \
  -o /tmp/sample_mflix.archive
```
##### Mongorestore the data 
Configure the enviroment variable, now we're using the root user which is mdb-admin
```shell
export MDB_CONNECTION_STRING=\
mongodb://mdb-admin:adminpassword\
@replica-user-0.replica-user-svc.mongodb.svc.cluster.local:27017,\
replica-user-1.replica-user-svc.mongodb.svc.cluster.local:27017,\
replica-user-2.replica-user-svc.mongodb.svc.cluster.local:27017/\
?replicaSet=replica-user
```

Mongosh to cluster

```shell
mongosh $MDB_CONNECTION_STRING
```

##### Run the mongorestore 
```shell
mongorestore \
  --archive=/tmp/sample_mflix.archive \
  --verbose=1 \
  --drop \
  --nsInclude 'sample_mflix.*' \
  --uri="${MDB_CONNECTION_STRING}"
```

##### Create the MongoDB Search index 
```shell
mongosh --quiet \
    "${MDB_CONNECTION_STRING}" \
    --eval "use sample_mflix" \
    --eval 'db.movies.createSearchIndex("default",\
     { mappings: { dynamic: true } });
```

##### Run the MongoDB Search query 
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

If it's succesfull you will get this result 

```js
{
    plot: 'A sports agent stages an unconventional recruitment strategy to get talented Indian cricket players to play Major League Baseball.',
    genres: [ 'Biography', 'Drama', 'Sport' ],
    title: 'Million Dollar Arm',
    released: ISODate('2014-05-16T00:00:00.000Z')
  }
```
This would be how it looks like 

![alt text](img/resultsearch.png)


## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

We welcome contributions to improve this guide! Here's how you can help:

### How to Contribute

1. **Fork the repository**
2. **Create a feature branch** (`git checkout -b feature/improvement`)
3. **Make your changes** and test them thoroughly
4. **Commit your changes** (`git commit -m 'Add some improvement'`)
5. **Push to the branch** (`git push origin feature/improvement`)
6. **Open a Pull Request**

### Guidelines

- Ensure your changes work with the latest versions of the tools mentioned
- Test your modifications on both ARM and x86 architectures if possible
- Update documentation for any new features or changes
- Follow existing code style and formatting
- Include clear commit messages

### Reporting Issues

If you encounter any problems or have suggestions:

1. Check existing issues first
2. Create a new issue with:
    - Clear description of the problem
    - Steps to reproduce
    - Your environment details (OS, tool versions)
    - Expected vs actual behavior

### Support

For questions or help:
- Open an issue for bugs or feature requests
- Check the official MongoDB Kubernetes documentation
- Consult the k3d and kubectl documentation for cluster-related issues
