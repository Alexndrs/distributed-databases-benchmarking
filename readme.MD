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

B) 