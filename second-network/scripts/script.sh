#!/bin/bash

echo
echo " ____    _____      _      ____    _____ "
echo "/ ___|  |_   _|    / \    |  _ \  |_   _|"
echo "\___ \    | |     / _ \   | |_) |   | |  "
echo " ___) |   | |    / ___ \  |  _ <    | |  "
echo "|____/    |_|   /_/   \_\ |_| \_\   |_|  "
echo
echo "Build your first network (BYFN) end-to-end test"
echo "(with local modifications)"
echo

set -o pipefail
set -x

CHANNEL_NAME="${1:-mychannel}"

DELAY=3
TIMEOUT=10
MAX_RETRY=10

# verify the result of the end-to-end test
die() {
    echo "!!!!!!!!!!!!!!! "$@" !!!!!!!!!!!!!!!!"
    echo "========= ERROR !!! FAILED to execute End-2-End Scenario ==========="
    echo
    exit 1
}

if [ "$CORE_PEER_TLS_ENABLED" = "false" ]; then
    unset CORE_PEER_TLS_ENABLED
    die "Non-TLS is no longer supported"
fi

CC_SRC_PATH="/opt/gopath/src/github.com/chaincode/chaincode_example02/node/"

echo "Channel name : "$CHANNEL_NAME

ORDERER_CA="/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"
ORDERER_LOCALMSPID="OrdererMSP"
ORDERER_TLS_ROOTCERT_FILE="/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"
ORDERER_MSPCONFIGPATH="/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/users/Admin@example.com/msp"
ORDERER_ADDRESS="orderer.example.com:7050"

PEER_LOCALMSPIDS=(
    [1]="Org1MSP"
    [2]="Org2MSP"
    [3]="Org3MSP"
)

PEER_TLS_ROOTCERT_FILES=(
    [1]="/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
    [2]="/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt"
    [3]="/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt"
)

PEER_MSPCONFIGPATHS=(
    [1]="/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
    [2]="/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp"
    [3]="/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org3.example.com/users/Admin@org3.example.com/msp"
)

declare -A PEER_ADDRESSES # index: "org,peer"
PEER_ADDRESSES=(
    [1,0]="peer0.org1.example.com:7051"
    [1,1]="peer1.org1.example.com:8051"
    [2,0]="peer0.org2.example.com:9051"
    [2,1]="peer1.org2.example.com:10051"
    [3,0]="peer0.org3.example.com:11051"
    [3,1]="peer1.org3.example.com:12051"
)

setGlobals() {
  PEER=$1
  ORG=$2

  CORE_PEER_LOCALMSPID="${PEER_LOCALMSPIDS[$ORG]}"
  CORE_PEER_TLS_ROOTCERT_FILE="${PEER_TLS_ROOTCERT_FILES[$ORG]}"
  CORE_PEER_MSPCONFIGPATH="${PEER_MSPCONFIGPATHS[$ORG]}"
  CORE_PEER_ADDRESS="${PEER_ADDRESSES[$ORG,$PEER]}"

  if [ -z "$CORE_PEER_LOCALMSPID" ]; then
      echo "================== ERROR !!! ORG Unknown =================="
  fi
}


updateAnchorPeers() {
  PEER=$1
  ORG=$2
  setGlobals $PEER $ORG

  peer channel update -o $ORDERER_ADDRESS -c $CHANNEL_NAME -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA | tee log.txt || die "Anchor peer update failed"
  echo "===================== Anchor peers updated for org '$CORE_PEER_LOCALMSPID' on channel '$CHANNEL_NAME' ===================== "
  sleep $DELAY
  echo
}

## Sometimes Join takes time hence RETRY at least 5 times
joinChannelWithRetry() {
  PEER=$1
  ORG=$2
  setGlobals $PEER $ORG

  local COUNTER=1
  while [ $COUNTER -lt $MAX_RETRY ]; do
      if peer channel join -b $CHANNEL_NAME.block | tee log.txt; then
          return
      fi
      COUNTER=$(expr $COUNTER + 1)
      echo "peer${PEER}.org${ORG} failed to join the channel, Retry after $DELAY seconds"
      sleep $DELAY
  done
  die "After $MAX_RETRY attempts, peer${PEER}.org${ORG} has failed to join channel '$CHANNEL_NAME' "
}


## Create channel
echo "Creating channel..."
setGlobals 0 1
peer channel create -o $ORDERER_ADDRESS -c $CHANNEL_NAME -f ./channel-artifacts/channel.tx --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA | tee log.txt || die "Channel creation failed"
echo "===================== Channel '$CHANNEL_NAME' created ===================== "
echo


## Join all the peers to the channel
echo "Having all peers join the channel..."
for org in 1 2; do
    for peer in 0 1; do
        joinChannelWithRetry $peer $org
        echo "===================== peer${peer}.org${org} joined channel '$CHANNEL_NAME' ===================== "
        sleep $DELAY
        echo
    done
done

## Set the anchor peers for each org in the channel
echo "Updating anchor peers for org1..."
updateAnchorPeers 0 1

echo "Updating anchor peers for org2..."
updateAnchorPeers 0 2

set +x

echo
echo "========= All GOOD, BYFN execution completed =========== "
echo

echo
echo " _____   _   _   ____   "
echo "| ____| | \ | | |  _ \  "
echo "|  _|   |  \| | | | | | "
echo "| |___  | |\  | | |_| | "
echo "|_____| |_| \_| |____/  "
echo

exit 0

# vim: set sw=4 ts=4 et:
