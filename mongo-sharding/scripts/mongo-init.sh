#!/bin/bash

echo "🚀 Configuration server initialization..."
docker compose exec -T configSrv mongosh --port 27017 --quiet <<EOF
try {
    let result = rs.initiate(
      {
        _id : "config_server",
           configsvr: true,
        members: [
          { _id : 0, host : "configSrv:27017" }
        ]
      }
    );
    assert(result.ok, 1, "Failed to initialize configuration server");
    exit();
} catch (error) {
    print("Exception: " + (error.message));
    quit(1);
}
EOF
echo
if [ $? -eq 0 ]; then
    echo "✅ Done"
else
    echo "❌ Failed"
    exit 1
fi


echo "🚀 Shard1 initialization"
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
try {
    let result = rs.initiate(
        {
          _id : "shard1",
          members: [
            { _id : 0, host : "shard1:27018" }
          ]
        }
    );
    assert(result.ok, 1, "Failed to initialize shard1");
    exit();
} catch (error) {
    print("Exception: " + (error.message));
    quit(1);
}   
EOF
echo
if [ $? -eq 0 ]; then
    echo "✅ Done"
else
    echo "❌ Failed"
    exit 1
fi


echo "🚀 Shard2 initialization"
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
try {
    let result = rs.initiate(
        {
          _id : "shard2",
          members: [
            { _id : 1, host : "shard2:27019" }
          ]
        }
    );
    assert(result.ok, 1, "Failed to initialize shard2");
    exit();
} catch (error) {
    print("Exception: " + (error.message));
    quit(1);
}   
EOF
echo
if [ $? -eq 0 ]; then
    echo "✅ Done"
else
    echo "❌ Failed"
    exit 1
fi


echo "⌛ Waiting for mongos_router ready"
until [ "$(docker inspect -f {{.State.Health.Status}} mongos_router)" == "healthy" ]; do
    sleep 3
done

echo "💾 Enable sharding and write some data"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
try {
    let result = sh.addShard( "shard1/shard1:27018");
    assert(result.ok, 1, "Failed to add shard1");

    result = sh.addShard( "shard2/shard2:27019");
    assert(result.ok, 1, "Failed to add shard2");

    result = sh.enableSharding("somedb");
    assert(result.ok, 1, "Failed to enable sharding");

    result = sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )
    assert(result.ok, 1, "Failed to shard collection");

    const somedb = db.getSiblingDB("somedb");

    for(var i = 0; i < 1000; i++) somedb.helloDoc.insert({age:i, name:"ly"+i})
    exit();
} catch (error) {
    print("Exception: " + (error.message));
    quit(1); 
}
EOF
echo
if [ $? -eq 0 ]; then
    echo "✅ Done"
else
    echo "❌ Failed"
    exit 1
fi

echo "📊 Count shard1 documents"
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb;
db.helloDoc.countDocuments();
exit();
EOF
echo

echo "📊 Count shard2 documents"
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
use somedb;
db.helloDoc.countDocuments();
exit();
EOF
echo

echo "📊 Count all documents"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb;
db.helloDoc.countDocuments();
exit();
EOF
echo