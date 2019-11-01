## Build Your ~First~ Second Network (BY~F~SN)

Like BYFN, only gradually tailored toward the minimalistic setup I want to construct and **understand** every step of it.

## Environment on `ca_peerOrg1`

```
FABRIC_CA_HOME=/etc/hyperledger/fabric-ca-server
FABRIC_CA_SERVER_CA_NAME=ca-org1
FABRIC_CA_SERVER_PORT=7054
FABRIC_CA_SERVER_TLS_CERTFILE=/etc/hyperledger/fabric-ca-server-config/ca.org1.example.com-cert.pem
FABRIC_CA_SERVER_TLS_ENABLED=true
FABRIC_CA_SERVER_TLS_KEYFILE=/etc/hyperledger/fabric-ca-server-config/fb2d808a3558e79ecc1b3277cadcd5db3516088140347e0cd0c1aa1c69c5e3e1_sk
HOSTNAME=dd4dd474cae3
PWD=/
```

## Environment on `peer0.org1.example.com`

```
CORE_LEDGER_STATE_COUCHDBCONFIG_COUCHDBADDRESS=couchdb0:5984
CORE_LEDGER_STATE_COUCHDBCONFIG_PASSWORD=
CORE_LEDGER_STATE_COUCHDBCONFIG_USERNAME=
CORE_LEDGER_STATE_STATEDATABASE=CouchDB
CORE_PEER_ADDRESS=peer0.org1.example.com:7051
CORE_PEER_CHAINCODEADDRESS=peer0.org1.example.com:7052
CORE_PEER_CHAINCODELISTENADDRESS=0.0.0.0:7052
CORE_PEER_GOSSIP_BOOTSTRAP=peer1.org1.example.com:8051
CORE_PEER_GOSSIP_EXTERNALENDPOINT=peer0.org1.example.com:7051
CORE_PEER_GOSSIP_ORGLEADER=false
CORE_PEER_GOSSIP_USELEADERELECTION=true
CORE_PEER_ID=peer0.org1.example.com
CORE_PEER_LISTENADDRESS=0.0.0.0:7051
CORE_PEER_LOCALMSPID=Org1MSP
CORE_PEER_PROFILE_ENABLED=true
CORE_PEER_TLS_CERT_FILE=/etc/hyperledger/fabric/tls/server.crt
CORE_PEER_TLS_ENABLED=true
CORE_PEER_TLS_KEY_FILE=/etc/hyperledger/fabric/tls/server.key
CORE_PEER_TLS_ROOTCERT_FILE=/etc/hyperledger/fabric/tls/ca.crt
CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE=net_byfn
CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock
FABRIC_LOGGING_SPEC=INFO
GOCACHE=off
GOROOT=/opt/go
HOSTNAME=3a2b32abad75
PWD=/opt/gopath/src/github.com/hyperledger/fabric/peer
SYS_CHANNEL=byfn-sys-channel
```

## Environment on `cli`

```
CORE_PEER_ADDRESS=peer0.org1.example.com:7051
CORE_PEER_ID=cli
CORE_PEER_LOCALMSPID=Org1MSP
CORE_PEER_TLS_CERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/server.crt
CORE_PEER_TLS_ENABLED=true
CORE_PEER_TLS_KEY_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/server.key
CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock
FABRIC_LOGGING_SPEC=INFO
GOCACHE=off
GOROOT=/opt/go
HOSTNAME=4d9938e46149
PWD=/opt/gopath/src/github.com/hyperledger/fabric/peer
SYS_CHANNEL=byfn-sys-channel
```

## Environment on orderer

```
FABRIC_LOGGING_SPEC=INFO
HOSTNAME=646bdc965202
ORDERER_GENERAL_CLUSTER_CLIENTCERTIFICATE=/var/hyperledger/orderer/tls/server.crt
ORDERER_GENERAL_CLUSTER_CLIENTPRIVATEKEY=/var/hyperledger/orderer/tls/server.key
ORDERER_GENERAL_CLUSTER_ROOTCAS='[/var/hyperledger/orderer/tls/ca.crt]'
ORDERER_GENERAL_GENESISFILE=/var/hyperledger/orderer/orderer.genesis.block
ORDERER_GENERAL_GENESISMETHOD=file
ORDERER_GENERAL_LISTENADDRESS=0.0.0.0
ORDERER_GENERAL_LOCALMSPDIR=/var/hyperledger/orderer/msp
ORDERER_GENERAL_LOCALMSPID=OrdererMSP
ORDERER_GENERAL_TLS_CERTIFICATE=/var/hyperledger/orderer/tls/server.crt
ORDERER_GENERAL_TLS_ENABLED=true
ORDERER_GENERAL_TLS_PRIVATEKEY=/var/hyperledger/orderer/tls/server.key
ORDERER_GENERAL_TLS_ROOTCAS='[/var/hyperledger/orderer/tls/ca.crt]'
PWD=/opt/gopath/src/github.com/hyperledger/fabric
```

## Creating channel


```
docker cp crypto-config peer0.org1.example.com:/tmp
docker cp channel-artifacts peer0.org1.example.com:/tmp
```

On peer0.org1.example.com:
```
export CORE_PEER_MSPCONFIGPATH=/tmp/crypto-config/peerOrganizations/org1.example.com/users/Admin\@org1.example.com/msp

peer channel create -o orderer.example.com:7050 -c mychannel -f /tmp/channel-artifacts/channel.tx  --tls --cafile /tmp/crypto-config/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
# Generates: mychannel.block

peer channel join -b mychannel.block
# Still needs CORE_PEER_MSPCONFIGPATH

# Anchor peer0
peer channel update -o orderer.example.com:7050 -c mychannel -f /tmp/channel-artifacts/Org1MSPanchors.tx --tls --cafile /tmp/crypto-config/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
```

