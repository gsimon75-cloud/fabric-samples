#!/bin/bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

# This script will orchestrate a sample end-to-end execution of the Hyperledger
# Fabric network.
#
# The end-to-end verification provisions a sample Fabric network consisting of
# two organizations, each maintaining two peers, and a “solo” ordering service.
#
# This verification makes use of two fundamental tools, which are necessary to
# create a functioning transactional network with digital signature validation
# and access control:
#
# * cryptogen - generates the x509 certificates used to identify and
#   authenticate the various components in the network.
# * configtxgen - generates the requisite configuration artifacts for orderer
#   bootstrap and channel creation.
#
# Each tool consumes a configuration yaml file, within which we specify the topology
# of our network (cryptogen) and the location of our certificates for various
# configuration operations (configtxgen).  Once the tools have been successfully run,
# we are able to launch our network.  More detail on the tools and the structure of
# the network will be provided later in this document.  For now, let's get going...

# prepending $PWD/../bin to PATH to ensure we are picking up the correct binaries
# this may be commented out to resolve installed version of tools if desired
export PATH=$PWD/../bin:$PWD:$PATH
export FABRIC_CFG_PATH=$PWD
export VERBOSE=false

set -vx

# Print the usage message
function printHelp() {
  set +vx
  echo "Usage: "
  echo "  byfn.sh <mode> [-c <channel name>] [-t <timeout>] [-d <delay>] [-f <docker-compose-file>] [-s <dbtype>] [-l <language>] [-o <consensus-type>] [-i <imagetag>] [-a] [-n] [-v]"
  echo "    <mode> - one of 'up', 'down', 'restart', 'generate' or 'upgrade'"
  echo "      - 'up' - bring up the network with docker-compose up"
  echo "      - 'down' - clear the network with docker-compose down"
  echo "      - 'restart' - restart the network"
  echo "      - 'generate' - generate required certificates and genesis block"
  echo "      - 'upgrade'  - upgrade the network from version 1.3.x to 1.4.0"
  echo "    -c <channel name> - channel name to use (defaults to \"mychannel\")"
  echo "    -t <timeout> - CLI timeout duration in seconds (defaults to 10)"
  echo "    -d <delay> - delay duration in seconds (defaults to 3)"
  echo "    -f <docker-compose-file> - specify which docker-compose file use (defaults to docker-compose-cli.yaml)"
  echo "    -s <dbtype> - the database backend to use: goleveldb (default) or couchdb"
  echo "    -l <language> - the chaincode language: golang (default) or node"
  echo "    -o <consensus-type> - the consensus-type of the ordering service: solo (default), kafka, or etcdraft"
  echo "    -i <imagetag> - the tag to be used to launch the network (defaults to \"latest\")"
  echo "    -a - launch certificate authorities (no certificate authorities are launched by default)"
  echo "    -n - do not deploy chaincode (abstore chaincode is deployed by default)"
  echo "    -v - verbose mode"
  echo "  byfn.sh -h (print this message)"
  echo
  echo "Typically, one would first generate the required certificates and "
  echo "genesis block, then bring up the network. e.g.:"
  echo
  echo "        byfn.sh generate -c mychannel"
  echo "        byfn.sh up -c mychannel -s couchdb"
  echo "        byfn.sh up -c mychannel -s couchdb -i 1.4.0"
  echo "        byfn.sh up -l node"
  echo "        byfn.sh down -c mychannel"
  echo "        byfn.sh upgrade -c mychannel"
  echo
  echo "Taking all defaults:"
  echo "        byfn.sh generate"
  echo "        byfn.sh up"
  echo "        byfn.sh down"
}

function die {
  echo "$*"
  exit 1
}

function one_line_pem {
  awk 'BEGIN {ORS=""} {print $0 "\\n"}' $1
}

function yaml_expand_nl {
  awk '/\\n/ {match($0, "^\\s*", prefix); gsub("\\\\n", "\n" prefix[0])} {print}'
}

# Versions of fabric known not to work with this release of first-network
BLACKLISTED_VERSIONS="1.0.* 1.1.0-preview 1.1.0-alpha"

declare -A CONSENSUS_PROFILES
CONSENSUS_PROFILES=(
  [solo]="TwoOrgsOrdererGenesis"
  [kafka]="SampleDevModeKafka"
  [etcdraft]="SampleMultiNodeEtcdRaft"
)

# Generate the needed certificates, the genesis block and start the network.
function networkUp() {
  # Do some basic sanity checking to make sure that the appropriate versions of fabric
  # binaries/images are available.  In the future, additional checking for the presence
  # of go or other items could be added.
  # Note, we check configtxlator externally because it does not require a config file, and peer in the
  # docker image because of FAB-8551 that makes configtxlator return 'development version' in docker
  LOCAL_VERSION=$(configtxlator version | sed -ne 's/ Version: //p')
  DOCKER_IMAGE_VERSION=$(docker run --rm hyperledger/fabric-tools:$IMAGE_TAG peer version | sed -ne 's/ Version: //p' | head -1)

  echo "LOCAL_VERSION=$LOCAL_VERSION"
  echo "DOCKER_IMAGE_VERSION=$DOCKER_IMAGE_VERSION"

  if [ "$LOCAL_VERSION" != "$DOCKER_IMAGE_VERSION" ]; then
    echo "=================== WARNING ==================="
    echo "  Local fabric binaries and docker images are  "
    echo "  out of  sync. This may cause problems.       "
    echo "==============================================="
  fi

  for UNSUPPORTED_VERSION in $BLACKLISTED_VERSIONS; do
    if [[ "$LOCAL_VERSION" == "$UNSUPPORTED_VERSION" ]]; then
      die "ERROR! Local Fabric binary version of $LOCAL_VERSION does not match this newer version of BYFN and is unsupported. Either move to a later version of Fabric or checkout an earlier version of fabric-samples."
    fi

    if [[ "$DOCKER_IMAGE_VERSION" == "$UNSUPPORTED_VERSION" ]]; then
      die "ERROR! Fabric Docker image version of $DOCKER_IMAGE_VERSION does not match this newer version of BYFN and is unsupported. Either move to a later version of Fabric or checkout an earlier version of fabric-samples."
    fi
  done

  # generate artifacts if they don't exist
  [ -d crypto-config ] || die "Please run '$0 generate' first!"

  COMPOSE_FILES="-f $COMPOSE_FILE"

  if [ "$CERTIFICATE_AUTHORITIES" == "true" ]; then
    COMPOSE_FILES="$COMPOSE_FILES -f $COMPOSE_FILE_CA"
    export BYFN_CA1_PRIVATE_KEY=$(basename crypto-config/peerOrganizations/org1.example.com/ca/*_sk)
    export BYFN_CA2_PRIVATE_KEY=$(basename crypto-config/peerOrganizations/org2.example.com/ca/*_sk)
  fi

  case "$CONSENSUS_TYPE" in
    kafka) COMPOSE_FILES="$COMPOSE_FILES -f $COMPOSE_FILE_KAFKA";;
    etcdraft) COMPOSE_FILES="$COMPOSE_FILES -f $COMPOSE_FILE_RAFT2";;
  esac

  if [ "$IF_COUCHDB" == "couchdb" ]; then
    COMPOSE_FILES="$COMPOSE_FILES -f $COMPOSE_FILE_COUCH"
  fi

  docker-compose $COMPOSE_FILES up -d 2>&1

  docker ps -a || die "ERROR !!!! Unable to start network"

  case "$CONSENSUS_TYPE" in
    kafka)
    echo "Sleeping 10s to allow $CONSENSUS_TYPE cluster to complete booting"
    sleep 10;;

    etcdraft)
    echo "Sleeping 15s to allow $CONSENSUS_TYPE cluster to complete booting"
    sleep 15;;
  esac

  # now run the end to end script
  if [ "$NO_CHAINCODE" != "true" ]; then
    CHAINCODE_NAME="mycc"
  fi
  docker exec cli scripts/script.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT $VERBOSE $CHAINCODE_NAME || die "ERROR !!!! Test failed"
}


# Upgrade the network components which are at version 1.3.x to 1.4.x
# Stop the orderer and peers, backup the ledger for orderer and peers, cleanup chaincode containers and images
# and relaunch the orderer and peers with latest tag
function upgradeNetwork() {
  if [[ "$IMAGE_TAG" == "1.4.*" || "$IMAGE_TAG" == "latest" ]]; then
    docker inspect -f '{{.Config.Volumes}}' orderer.example.com | grep -q '/var/hyperledger/production/orderer' || die "ERROR !!!! This network does not appear to start with fabric-samples >= v1.3.x?"

    LEDGERS_BACKUP=./ledgers-backup

    # create ledger-backup directory
    mkdir -p $LEDGERS_BACKUP

    COMPOSE_FILES="-f $COMPOSE_FILE"
    if [ "$CERTIFICATE_AUTHORITIES" == "true" ]; then
      COMPOSE_FILES="$COMPOSE_FILES -f $COMPOSE_FILE_CA"
      export BYFN_CA1_PRIVATE_KEY=$(basename crypto-config/peerOrganizations/org1.example.com/ca/*_sk)
      export BYFN_CA2_PRIVATE_KEY=$(basename crypto-config/peerOrganizations/org2.example.com/ca/*_sk)
    fi

    case "$CONSENSUS_TYPE" in
      kafka) COMPOSE_FILES="$COMPOSE_FILES -f $COMPOSE_FILE_KAFKA";;
      etcdraft) COMPOSE_FILES="$COMPOSE_FILES -f $COMPOSE_FILE_RAFT2";;
    esac
    
    if [ "$IF_COUCHDB" == "couchdb" ]; then
      COMPOSE_FILES="$COMPOSE_FILES -f $COMPOSE_FILE_COUCH"
    fi

    # removing the cli container
    docker-compose $COMPOSE_FILES stop cli
    docker-compose $COMPOSE_FILES up -d --no-deps cli

    echo "Upgrading orderer"
    docker-compose $COMPOSE_FILES stop orderer.example.com
    docker cp -a orderer.example.com:/var/hyperledger/production/orderer $LEDGERS_BACKUP/orderer.example.com
    docker-compose $COMPOSE_FILES up -d --no-deps orderer.example.com

    for PEER in peer0.org1.example.com peer1.org1.example.com peer0.org2.example.com peer1.org2.example.com; do
      echo "Upgrading peer $PEER"

      # Stop the peer and backup its ledger
      docker-compose $COMPOSE_FILES stop $PEER
      docker cp -a $PEER:/var/hyperledger/production $LEDGERS_BACKUP/$PEER/

      # Remove any old containers and images for this peer
      docker ps -f "NAME=dev-$PEER-*" --format "{{.ID}}" | xargs -r docker rm -f
      docker images -f "REFERENCE=dev-$PEER-*" --format "{{.ID}}" | xargs -r docker rmi -f

      # Start the peer again
      docker-compose $COMPOSE_FILES up -d --no-deps $PEER
    done

    docker exec cli sh -c "SYS_CHANNEL=$CH_NAME && scripts/upgrade_to_v14.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT $VERBOSE" || die "ERROR !!!! Test failed"
  else
    echo "ERROR !!!! Pass the v1.4.x image tag"
  fi
}


# Tear down running network
function networkDown() {
  # stop org3 containers also in addition to org1 and org2, in case we were running sample to add org3
  # stop kafka and zookeeper containers in case we're running with kafka consensus-type
  docker-compose \
    -f $COMPOSE_FILE \
    -f $COMPOSE_FILE_COUCH \
    -f $COMPOSE_FILE_KAFKA \
    -f $COMPOSE_FILE_RAFT2 \
    -f $COMPOSE_FILE_CA \
    -f $COMPOSE_FILE_ORG3 \
    down \
    --volumes \
    --remove-orphans

  # Don't remove the generated artifacts -- note, the ledgers are always removed
  if [ "$MODE" != "restart" ]; then
    # Bring down the network, deleting the volumes

    #Delete any ledger backups
    docker run -v $PWD:/tmp/first-network --rm hyperledger/fabric-tools:$IMAGE_TAG rm -Rf /tmp/first-network/ledgers-backup

    #Cleanup the chaincode containers
    # Obtain CONTAINER_IDS and remove them, TODO Might want to make this optional - could clear other containers
    docker ps -a | awk '($2 ~ /dev-peer.*.mycc.*/) {print $1}' | xargs -r docker rm -f

    #Cleanup images
    # Delete any images that were generated as a part of this setup specifically the following images are often left behind:
    docker images | awk '($1 ~ /dev-peer.*.mycc.*/) {print $3}' | xargs -r docker rmi -f

    # remove orderer block and other channel configuration transactions and certs
    echo FAKE rm -rf channel-artifacts/*.block channel-artifacts/*.tx crypto-config ./org3-artifacts/crypto-config/ channel-artifacts/org3.json
    # remove the docker-compose yaml file that was customized to the example
    echo FAKE rm -f docker-compose-e2e.yaml
  fi
}



function generateArtifacts() {
  # We will use the cryptogen tool to generate the cryptographic material (x509 certs)
  # for our various network entities.  The certificates are based on a standard PKI
  # implementation where validation is achieved by reaching a common trust anchor.
  #
  # Cryptogen consumes a file - ``crypto-config.yaml`` - that contains the network
  # topology and allows us to generate a library of certificates for both the
  # Organizations and the components that belong to those Organizations.  Each
  # Organization is provisioned a unique root certificate (``ca-cert``), that binds
  # specific components (peers and orderers) to that Org.  Transactions and communications
  # within Fabric are signed by an entity's private key (``keystore``), and then verified
  # by means of a public key (``signcerts``).  You will notice a "count" variable within
  # this file.  We use this to specify the number of peers per Organization; in our
  # case it's two peers per Org.  The rest of this template is extremely
  # self-explanatory.
  #
  # After we run the tool, the certs will be parked in a folder titled ``crypto-config``.

  # Generates Org certs using cryptogen tool
  which cryptogen || die "cryptogen tool not found. exiting"

  echo
  echo "##########################################################"
  echo "##### Generate certificates using cryptogen tool #########"
  echo "##########################################################"
  rm -rf crypto-config
  #set -x
  cryptogen generate --config=./crypto-config.yaml || die "Failed to generate certificates..."
  #set +x

  echo
  echo "Generate CCP files for Org1 and Org2"

  export ORG=1
  export P0PORT=7051
  export P1PORT=8051
  export CAPORT=7054
  PEERPEM_FILE=crypto-config/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem
  CAPEM_FILE=crypto-config/peerOrganizations/org1.example.com/ca/ca.org1.example.com-cert.pem
  export PEERPEM="$(one_line_pem $PEERPEM_FILE)"
  export CAPEM="$(one_line_pem $CAPEM_FILE)"

  envsubst < ccp-template.json > connection-org1.json
  envsubst < ccp-template.yaml | yaml_expand_nl > connection-org1.yaml

  export ORG=2
  export P0PORT=9051
  export P1PORT=10051
  export CAPORT=8054
  PEERPEM_FILE=crypto-config/peerOrganizations/org2.example.com/tlsca/tlsca.org2.example.com-cert.pem
  CAPEM_FILE=crypto-config/peerOrganizations/org2.example.com/ca/ca.org2.example.com-cert.pem
  export PEERPEM="$(one_line_pem $PEERPEM_FILE)"
  export CAPEM="$(one_line_pem $CAPEM_FILE)"

  envsubst < ccp-template.json > connection-org2.json
  envsubst < ccp-template.yaml | yaml_expand_nl > connection-org2.yaml


  #replacePrivateKey
  # Using docker-compose-e2e-template.yaml, replace constants with private key file names
  # generated by the cryptogen tool and output a docker-compose.yaml specific to this
  # configuration
  # The next steps will replace the template's contents with the
  # actual values of the private key file names for the two CAs.
  export CA1_PRIVATE_KEY=$(basename crypto-config/peerOrganizations/org1.example.com/ca/*_sk)
  export CA2_PRIVATE_KEY=$(basename crypto-config/peerOrganizations/org2.example.com/ca/*_sk)

  envsubst '$CA1_PRIVATE_KEY $CA2_PRIVATE_KEY' <docker-compose-e2e-template.yaml >docker-compose-e2e.yaml

  # The `configtxgen tool is used to create four artifacts:
  #    orderer **bootstrap block**
  #    fabric **channel configuration transaction**
  #    two **anchor peer transactions** - one for each Peer Org.
  #
  # The orderer block is the genesis block for the ordering service, and the
  # channel transaction file is broadcast to the orderer at channel creation
  # time.  The anchor peer transactions, as the name might suggest, specify each
  # Org's anchor peer on this channel.
  #
  # Configtxgen consumes a file - ``configtx.yaml`` - that contains the definitions
  # for the sample network. There are three members - one Orderer Org (``OrdererOrg``)
  # and two Peer Orgs (``Org1`` & ``Org2``) each managing and maintaining two peer nodes.
  # This file also specifies a consortium - ``SampleConsortium`` - consisting of our
  # two Peer Orgs.  Pay specific attention to the "Profiles" section at the top of
  # this file.  You will notice that we have two unique headers. One for the orderer genesis
  # block - ``TwoOrgsOrdererGenesis`` - and one for our channel - ``TwoOrgsChannel``.
  # These headers are important, as we will pass them in as arguments when we create
  # our artifacts.  This file also contains two additional specifications that are worth
  # noting.  Firstly, we specify the anchor peers for each Peer Org
  # (``peer0.org1.example.com`` & ``peer0.org2.example.com``).  Secondly, we point to
  # the location of the MSP directory for each member, in turn allowing us to store the
  # root certificates for each Org in the orderer genesis block.  This is a critical
  # concept. Now any network entity communicating with the ordering service can have
  # its digital signature verified.
  #
  # This function will generate the crypto material and our four configuration
  # artifacts, and subsequently output these files into the ``channel-artifacts``
  # folder.
  #
  # If you receive the following warning, it can be safely ignored:
  #
  # [bccsp] GetDefault -> WARN 001 Before using BCCSP, please call InitFactories(). Falling back to bootBCCSP.
  #
  # You can ignore the logs regarding intermediate certs, we are not using them in
  # this crypto implementation.

  # Generate orderer genesis block, channel configuration transaction and
  # anchor peer update transactions
  which configtxgen || die "configtxgen tool not found. exiting"

  echo "##########################################################"
  echo "#########  Generating Orderer Genesis block ##############"
  echo "##########################################################"
  # Note: For some unknown reason (at least for now) the block file can't be
  # named orderer.genesis.block or the orderer will fail to launch!
  echo "CONSENSUS_TYPE=$CONSENSUS_TYPE"
  CONSENSUS_PROFILE=${CONSENSUS_PROFILES[$CONSENSUS_TYPE]}
  [ -n "$CONSENSUS_PROFILE" ] || die "Unrecognized CONSESUS_TYPE='$CONSENSUS_TYPE'"

  configtxgen \
      -profile $CONSENSUS_PROFILE \
      -channelID $SYS_CHANNEL \
      -outputBlock ./channel-artifacts/genesis.block || die "Failed to generate orderer genesis block..."

  echo
  echo "#################################################################"
  echo "### Generating channel configuration transaction 'channel.tx' ###"
  echo "#################################################################"
  configtxgen -profile TwoOrgsChannel -outputCreateChannelTx ./channel-artifacts/channel.tx -channelID $CHANNEL_NAME || die "Failed to generate channel configuration transaction..."

  echo
  echo "#################################################################"
  echo "#######    Generating anchor peer update for Org1MSP   ##########"
  echo "#################################################################"
  configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/Org1MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org1MSP || die "Failed to generate anchor peer update for Org1MSP..."

  echo
  echo "#################################################################"
  echo "#######    Generating anchor peer update for Org2MSP   ##########"
  echo "#################################################################"
  configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/Org2MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org2MSP || die "Failed to generate anchor peer update for Org2MSP..."
  echo
}


########################################################################################################################

# Obtain the OS and Architecture string that will be used to select the correct
# native binaries for your platform, e.g., darwin-amd64 or linux-amd64
OS_SYSTEM="$(uname -s | tr '[:upper:]' '[:lower:]' | sed 's/mingw64_nt.*/windows/')"
OS_MACHINE="$(uname -m | tr '[:upper:]' '[:lower:]' | sed 's/x86_64/amd64/g')"
OS_ARCH="$OS_SYSTEM-$OS_MACHINE"

# timeout duration - the duration the CLI should wait for a response from
# another container before giving up
CLI_TIMEOUT=10

# default for delay between commands
CLI_DELAY=3

# system channel name defaults to "byfn-sys-channel"
SYS_CHANNEL="byfn-sys-channel"

# channel name defaults to "mychannel"
CHANNEL_NAME="mychannel"

# use this as the default docker-compose yaml definition
COMPOSE_FILE=docker-compose-cli.yaml
COMPOSE_FILE_COUCH=docker-compose-couch.yaml

# org3 docker compose file
COMPOSE_FILE_ORG3=docker-compose-org3.yaml

# kafka and zookeeper compose file
COMPOSE_FILE_KAFKA=docker-compose-kafka.yaml

# two additional etcd/raft orderers
COMPOSE_FILE_RAFT2=docker-compose-etcdraft2.yaml

# certificate authorities compose file
COMPOSE_FILE_CA=docker-compose-ca.yaml

# use golang as the default language for chaincode
LANGUAGE=golang

# default image tag
IMAGE_TAG="latest"

# default consensus type
CONSENSUS_TYPE="solo"

# Parse commandline args
[ "$1" = "-m" ] && shift # supports old usage, muscle memory is powerful!
MODE="$1"
shift
# Determine whether starting, stopping, restarting, generating or upgrading
case "$MODE" in
  up) EXPMODE="Starting";;
  down) EXPMODE="Stopping";;
  restart) EXPMODE="Restarting";;
  generate) EXPMODE="Generating certs and genesis block";;
  upgrade) EXPMODE="Upgrading the network";;
  *) printHelp; exit 1;;
esac

while getopts "h?c:t:d:f:s:l:i:o:anv" opt; do
  case "$opt" in
    h | \?) printHelp; exit 0;;
    c) CHANNEL_NAME=$OPTARG;;
    t) CLI_TIMEOUT=$OPTARG;;
    d) CLI_DELAY=$OPTARG;;
    f) COMPOSE_FILE=$OPTARG;;
    s) IF_COUCHDB=$OPTARG;;
    l) LANGUAGE=$OPTARG;;
    i) IMAGE_TAG="$(go env GOARCH)-$OPTARG";;
    o) CONSENSUS_TYPE=$OPTARG;;
    a) CERTIFICATE_AUTHORITIES=true;;
    n) NO_CHAINCODE=true;;
    v) VERBOSE=true;;
  esac
done

export IMAGE_TAG


# Announce what was requested
echo
echo -n "$EXPMODE for channel '$CHANNEL_NAME' with CLI timeout of '$CLI_TIMEOUT' seconds and CLI delay of '$CLI_DELAY' seconds"
if [ "$IF_COUCHDB" == "couchdb" ]; then
  echo " and using database '$IF_COUCHDB'"
else
  echo ""
fi

# Ask user for confirmation to proceed
if [ -t 0 ]; then
  while true; do
    read -p "Continue? [Y/n] " ans
    case "${ans,,}" in
      y | "") echo "proceeding ..."; break;;
      n) echo "exiting..."; exit 1;;
      *) echo "invalid response";;
    esac
  done
fi


# Create the network using docker compose
case "$MODE" in
  up) networkUp;;
  down) networkDown;; ## Clear the network
  generate) generateArtifacts;; ## Generate Artifacts
  restart) networkDown && networkUp;; ## Restart the network
  upgrade) upgradeNetwork;; ## Upgrade the network from version 1.2.x to 1.3.x
esac

# vim: set sw=2 ts=2 et:
