# Benchmarking databases

Env : WSL on windows

## I) Setup:

> installed java and made sure docker is accessible from wsl with configuration of wsl in docker desktop settings

```bash
$ sudo apt install -y openjdk-17-jre-headless
```

## II) Docker exploration on mongo image

I have done this exploratory work using dockerHub doc for mongo here : https://hub.docker.com/_/mongo with additionnal help from chatGPT to understand precisely how to use docker and what is the purpose of each argument in command lines.

### A) First container
download mongo image
```bash
$ docker pull mongo
```

run my first mongo container from the `mongo` image
```bash
$ docker run -d --name mongo_mike -p 27017:27017 mongo
```
-d : run in background
-p 27017:27017 : make mongoDB port accessible on my computer

```bash
$ docker ps 
> CONTAINER ID   IMAGE     COMMAND                  CREATED          STATUS          PORTS                      NAMES
  d292edfeae92   mongo     "docker-entrypoint.s…"   12 seconds ago   Up 11 seconds   0.0.0.0:27017->27017/tcp   mongo_mike
```

Connect inside the container with the mongo shell in CLI
```bash
$ docker exec -it mongo_mike mongosh
```

Verifying if the container works properly
```bash
$ use testdb;
> switched to db testdb
$ db.createCollection("users");
> { ok: 1 }
$ db.users.insertOne({ name: "Mike", age: 20 });
> {
    acknowledged: true,
    insertedId: ObjectId('69065c576ecf3271cece5f47')
  }
$ db.users.find();
> [
    { _id: ObjectId('69065c576ecf3271cece5f47'), name: 'Mike', age: 20 }
  ]
```
And in another terminal outside the container : 
```bash
docker exec -it mongo_mike mongosh testdb --eval "db.stats()"
> {
    db: 'testdb',
    collections: Long('1'),
    views: Long('0'),
    objects: Long('1'),
    avgObjSize: 46,
    dataSize: 46,
    storageSize: 20480,
    indexes: Long('1'),
    indexSize: 20480,
    totalSize: 40960,
    scaleFactor: Long('1'),
    fsUsedSize: 62854238208,
    fsTotalSize: 1081101176832,
    ok: 1
  }
```

We have sucessfully created one running container of mongo that can be accessed from outside.

### B) Making mongo replica on multiple nodes (mutliple container about the same database)

In this part we will try to simulate the primary-secondary architecture for mongo by replicating the mongo database on multiple docker container. Following the primary-secondary principle : one container will allow writing while all the other containers will be read-only. 

Doc used : 
- https://docs.docker.com/engine/network/
  https://hub.docker.com/_/mongo
 to create a container network (connecting multiple containers)
- https://www.mongodb.com/docs/manual/administration/configuration/
 for replica config


Creating the network
```bash
$ docker network create mongo-net
```

Creating the containers, making them associate to the `mongo-net` network and allowing them to join the replicaSet `rs0`
```bash
$ docker run -d --name mongo1 --network mongo-net mongo --replSet rs0
$ docker run -d --name mongo2 --network mongo-net mongo --replSet rs0
$ docker run -d --name mongo3 --network mongo-net mongo --replSet rs0
```

Connecting inside mongo1, and initiate mongo replica set `rs0`. This will elect one container as primary and other members as secondary.

```bash
$ docker exec -it mongo1 mongosh
$ rs.initiate({_id:"rs0",members:[{_id:0,host:"mongo1:27017"},{_id:1,host:"mongo2:27017"},{_id:2,host:"mongo3:27017"}]})
> {
   ok: 1,
   ...
  }

$ rs.status()
> {
   set: 'rs0',
   syncSourceHost: 'mongo2:27017',
   ...
   members:[
        {name: 'mongo1:27017', health: 1, stateStr: 'SECONDARY',...},
        {name: 'mongo2:27017', health: 1, stateStr: 'PRIMARY',...},
        {name: 'mongo3:27017', health: 1, stateStr: 'SECONDARY',...}
    ],
    ...
  }
```
Container `mongo2` has been elected by mongo as PRIMARY container for replicaset `rs0`and the two others as SECONDARY.

Testing the propagation:
```bash
$ docker exec -it mongo2 mongosh
$ use test_db
$ db.users.insertOne({name: "Alex", score: 100})

$ docker exec -it mongo1 mongosh
$ use test_db
$ db.users.find()
> [
    {
        _id: ObjectId('69066da3aa26303ae1ce5f47'),
        name: 'Alex',
        score: 100
    }
  ]
$ db.users.insertOne({name: "Mike", score: 42})
> MongoServerError[NotWritablePrimary]: not primary
```

Everything seems to work properly : we can write on mongo2, mongo1 is on read only and the propagation among `rs0` seems to work.

### C) Measuring mongo performances with YCSB

doc used for YCSB : https://github.com/brianfrankcooper/YCSB/wiki/Getting-Started

Download YCSB
```bash
$ curl -O --location https://github.com/brianfrankcooper/YCSB/releases/download/0.17.0/ycsb-0.17.0.tar.gz
$ tar xfvz ycsb-0.17.0.tar.gz
$ cd ycsb-0.17.0
```

Making a yml file for creating the different mongo container easily : see [docker-compose-mongo-3.yml](docker-compose-mongo-3.yml)

Start the containers and network: 
```bash
$ docker compose -f docker-compose-mongo-3.yml up -d
$ docker ps
> CONTAINER ID   IMAGE          COMMAND                  CREATED         STATUS         PORTS                      NAMES
  7fd57313a306   mongo:latest   "docker-entrypoint.s…"   5 seconds ago   Up 4 seconds   0.0.0.0:27019->27017/tcp   mongo3
  8a25daf74b21   mongo:latest   "docker-entrypoint.s…"   5 seconds ago   Up 4 seconds   0.0.0.0:27018->27017/tcp   mongo2
  7a3c8ef04cc9   mongo:latest   "docker-entrypoint.s…"   5 seconds ago   Up 4 seconds   0.0.0.0:27017->27017/tcp   mongo1
```

init the replicat set:
```bash
$ docker exec -it mongo1 mongosh
$ # inside mongo shell
$ rs.initiate({
  _id: "rs0",
  members: [
    {_id: 0, host: "mongo1:27017"},
    {_id: 1, host: "mongo2:27017"},
    {_id: 2, host: "mongo3:27017"}
  ]
})
$ exit
```

connecting wsl and mongo driver through localhost: 
```bash
$ sudo nano /etc/hosts
# adding lines : 
127.0.0.1 mongo1
127.0.0.1 mongo2
127.0.0.1 mongo3
```

Creating [mongodb.properties](./ycsb-0.17.0/bin/mongodb.properties) inside to indicate to YCSB where are the mongodb databases
```bash
mongodb.url=mongodb://mongo1:27017,mongo2:27018,mongo3:27019/?replicaSet=rs0
mongodb.database=ycsb 
```

Using YCSB inside bin
```bash
$ ./ycsb load mongodb -s -P ../workloads/workloada -P mongodb.properties
> [OVERALL], RunTime(ms), 4105
  [OVERALL], Throughput(ops/sec), 243.605359317905
  ...
$ ./ycsb run mongodb -s -P ../workloads/workloada -P mongodb.properties
> [OVERALL], RunTime(ms), 4105
  [OVERALL], Throughput(ops/sec), 243.605359317905
  ...
```

### D) Scripting the tests

/!\ I'm not a bash expert, I have done the experiments above and I've given this markdown to claude, from my pseudo code it helped me write the following scripts that simply automate what has been done above by hand in command lines /!\

- [deploy_mongo.sh](./deploy_mongo.sh) : it does exactly the process above of creating the docker containers of mongo nodes and connect them through a docker network for a given number of nodes.
- [run_mongo_benchmark](./run_mongo_benchmark.sh) : it run YCSB through all the workload for a given number of mongo nodes (given in args). It writes the results in results_mongo_{num_nodes} e.g for 3 nodes the logs are in [results_mongo_3](./results_mongo_3/)