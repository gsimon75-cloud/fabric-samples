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
DELAY="${2:-3}"
LANGUAGE="${3:-golang}"
TIMEOUT="${4:-10}"
VERBOSE="${5:-false}"
CHAINCODE_NAME="$6"

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

case "${LANGUAGE,,}" in
    node) CC_SRC_PATH="/opt/gopath/src/github.com/chaincode/chaincode_example02/node/";;
    java) CC_SRC_PATH="/opt/gopath/src/github.com/chaincode/chaincode_example02/java/";;
    *) CC_SRC_PATH="github.com/chaincode/chaincode_example02/go/";;
esac

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

  if [ "$VERBOSE" == "true" ]; then
    env | grep CORE
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

  COUNTER=1
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

installChaincode() {
  PEER=$1
  ORG=$2
  setGlobals $PEER $ORG
  VERSION=${3:-1.0}
  peer chaincode install -n $CHAINCODE_NAME -v $VERSION -l $LANGUAGE -p $CC_SRC_PATH | tee log.txt || die "Chaincode installation on peer${PEER}.org${ORG} has failed"
  echo "===================== Chaincode is installed on peer${PEER}.org${ORG} ===================== "
  echo
}

instantiateChaincode() {
  PEER=$1
  ORG=$2
  setGlobals $PEER $ORG
  VERSION=${3:-1.0}

  # while 'peer chaincode' command can get the orderer endpoint from the peer
  # (if join was successful), let's supply it directly as we know it using
  # the "-o" option
  peer chaincode instantiate -o $ORDERER_ADDRESS --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA -C $CHANNEL_NAME -n $CHAINCODE_NAME -l $LANGUAGE -v 1.0 -c '{"Args":["init","a","100","b","200"]}' -P "AND ('Org1MSP.peer','Org2MSP.peer')" | tee log.txt || die "Chaincode instantiation on peer${PEER}.org${ORG} on channel '$CHANNEL_NAME' failed"
  echo "===================== Chaincode is instantiated on peer${PEER}.org${ORG} on channel '$CHANNEL_NAME' ===================== "
  echo
}

upgradeChaincode() {
  PEER=$1
  ORG=$2
  setGlobals $PEER $ORG

  peer chaincode upgrade -o $ORDERER_ADDRESS --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA -C $CHANNEL_NAME -n $CHAINCODE_NAME -v 2.0 -c '{"Args":["init","a","90","b","210"]}' -P "AND ('Org1MSP.peer','Org2MSP.peer','Org3MSP.peer')" | tee log.txt || die "Chaincode upgrade on peer${PEER}.org${ORG} has failed"
  echo "===================== Chaincode is upgraded on peer${PEER}.org${ORG} on channel '$CHANNEL_NAME' ===================== "
  echo
}

chaincodeQuery() {
  PEER=$1
  ORG=$2
  setGlobals $PEER $ORG
  EXPECTED_RESULT=$3
  echo "===================== Querying on peer${PEER}.org${ORG} on channel '$CHANNEL_NAME'... ===================== "

  # continue to poll
  # we either get a successful response, or reach TIMEOUT
  local starttime=$(date +%s)
  while true; do
    sec_elapsed=$(($(date +%s) - starttime))
    if [ $sec_elapsed -ge $TIMEOUT ]; then
        echo "!!!!!!!!!!!!!!! Query result on peer${PEER}.org${ORG} is INVALID !!!!!!!!!!!!!!!!"
        echo "================== ERROR !!! FAILED to execute End-2-End Scenario =================="
        echo
        exit 1
    fi
    echo "Attempting to Query peer${PEER}.org${ORG} ...$sec_elapsed secs"
    if peer chaincode query -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["query","a"]}' | tee log.txt; then
        VALUE=$(awk '/Query Result/ {print $NF}' log.txt)
        if [ "$VALUE" = "$EXPECTED_RESULT" ]; then
            break
        fi
        # removed the string "Query Result" from peer chaincode query command
        # result. as a result, have to support both options until the change
        # is merged.
        VALUE=$(egrep '^[0-9]+$' log.txt)
        if [ "$VALUE" = "$EXPECTED_RESULT" ]; then
            break
        fi
    fi
    sleep $DELAY
  done
  echo
  echo "===================== Query successful on peer${PEER}.org${ORG} on channel '$CHANNEL_NAME' ===================== "
}

# fetchChannelConfig <channel_id> <output_json>
# Writes the current channel config for a given channel to a JSON file
fetchChannelConfig() {
  CHANNEL=$1
  OUTPUT="$2"

  # Set OrdererOrg.Admin globals
  CORE_PEER_LOCALMSPID="$ORDERER_LOCALMSPID"
  CORE_PEER_TLS_ROOTCERT_FILE="$ORDERER_TLS_ROOTCERT_FILE"
  CORE_PEER_MSPCONFIGPATH="$ORDERER_MSPCONFIGPATH"

  echo "Fetching the most recent configuration block for the channel"
  peer channel fetch config config_block.pb -o $ORDERER_ADDRESS -c $CHANNEL --tls --cafile $ORDERER_CA

  echo "Decoding config block to JSON and isolating config to $OUTPUT"
  configtxlator proto_decode --input config_block.pb --type common.Block | jq .data.data[0].payload.data.config >"$OUTPUT"
}

# signConfigtxAsPeerOrg <org> <configtx.pb>
# Set the peerOrg admin of an org and signing the config update
signConfigtxAsPeerOrg() {
  PEERORG=$1
  TX="$2"
  setGlobals 0 $PEERORG
  peer channel signconfigtx -f "$TX"
}

# createConfigUpdate <channel_id> <original_config.json> <modified_config.json> <output.pb>
# Takes an original and modified config, and produces the config update tx
# which transitions between the two
createConfigUpdate() {
  CHANNEL="$1"
  ORIGINAL="$2"
  MODIFIED="$3"
  OUTPUT="$4"

  configtxlator proto_encode --input "$ORIGINAL" --type common.Config >original_config.pb
  configtxlator proto_encode --input "$MODIFIED" --type common.Config >modified_config.pb
  configtxlator compute_update --channel_id "$CHANNEL" --original original_config.pb --updated modified_config.pb >config_update.pb
  configtxlator proto_decode --input config_update.pb --type common.ConfigUpdate >config_update.json
  echo '{"payload":{"header":{"channel_header":{"channel_id":"'$CHANNEL'", "type":2}},"data":{"config_update":'$(cat config_update.json)'}}}' | jq . >config_update_in_envelope.json
  configtxlator proto_encode --input config_update_in_envelope.json --type common.Envelope >"$OUTPUT"
}

# parsePeerConnectionParameters $@
# Helper function that takes the parameters from a chaincode operation
# (e.g. invoke, query, instantiate) and checks for an even number of
# peers and associated org, then sets $PEER_CONN_PARMS and $PEERS
parsePeerConnectionParameters() {
  # check for uneven number of peer and org parameters
  if [ $(($# % 2)) -ne 0 ]; then
    die "Uneven number of peer connection parameters"
  fi

  PEER_CONN_PARMS=""
  while [ "$#" -gt 0 ]; do
    setGlobals $1 $2
    PEERS="$PEERS peer$1.org$2"
    PEER_CONN_PARMS="$PEER_CONN_PARMS --peerAddresses $CORE_PEER_ADDRESS"
    # shift by two to get the next pair of peer/org parameters
    shift
    shift
  done
  # remove leading space for output
  PEERS="${PEERS## }"
}

# chaincodeInvoke <peer> <org> ...
# Accepts as many peer/org pairs as desired and requests endorsement from each
chaincodeInvoke() {
  parsePeerConnectionParameters $@ || die "Invoke transaction failed on channel '$CHANNEL_NAME' due to uneven number of peer and org parameters "

  # while 'peer chaincode' command can get the orderer endpoint from the
  # peer (if join was successful), let's supply it directly as we know
  # it using the "-o" option
  peer chaincode invoke -o $ORDERER_ADDRESS --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA -C $CHANNEL_NAME -n $CHAINCODE_NAME $PEER_CONN_PARMS -c '{"Args":["invoke","a","b","10"]}' | tee log.txt || die "Invoke execution on $PEERS failed "
  echo "===================== Invoke transaction successful on $PEERS on channel '$CHANNEL_NAME' ===================== "
  echo
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

if [ -n "$CHAINCODE_NAME" ]; then

	## Install chaincode on peer0.org1 and peer0.org2
	echo "Installing chaincode on peer0.org1..."
	installChaincode 0 1
	echo "Install chaincode on peer0.org2..."
	installChaincode 0 2

	# Instantiate chaincode on peer0.org2
	echo "Instantiating chaincode on peer0.org2..."
	instantiateChaincode 0 2

	# Query chaincode on peer0.org1
	echo "Querying chaincode on peer0.org1..."
	chaincodeQuery 0 1 100

	# Invoke chaincode on peer0.org1 and peer0.org2
	echo "Sending invoke transaction on peer0.org1 peer0.org2..."
	chaincodeInvoke 0 1 0 2
	
	## Install chaincode on peer1.org2
	echo "Installing chaincode on peer1.org2..."
	installChaincode 1 2

	# Query on chaincode on peer1.org2, check if the result is 90
	echo "Querying chaincode on peer1.org2..."
	chaincodeQuery 1 2 90
	
fi

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
