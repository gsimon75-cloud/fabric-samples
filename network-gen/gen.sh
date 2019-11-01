#!/bin/bash
#
# Copyright IBM Corp All Rights Reserved
# SPDX-License-Identifier: Apache-2.0
#
# This script will orchestrate a sample end-to-end execution of the Hyperledger Fabric network.

export FABRIC_CFG_PATH=$PWD

# Print the usage message
function printHelp() {
  set +vx
  echo "Usage: "
  echo "  byfn.sh <mode> [-c <channel name>] [-s <dbtype>]"
  echo "    <mode> - one of 'generate' or 'mrproper'"
  echo "      - 'generate' - generate required certificates and genesis block"
  echo "      - 'mrproper' - wipe generated config data as well"
  echo "    -c <channel name> - channel name to use (defaults to \"mychannel\")"
  echo "    -h (print this message)"
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

function generateArtifacts() {
  echo "# Generate certificates using cryptogen tool"
  rm -rf crypto-config
  cryptogen generate --config=crypto-config.yaml || die "Failed to generate certificates..."
  echo

  echo "# Generating Orderer Genesis block"
  # Note: For some unknown reason (at least for now) the block file can't be named orderer.genesis.block or the orderer will fail to launch!
  configtxgen -profile TwoOrgsOrdererGenesis -channelID $SYS_CHANNEL -outputBlock channel-artifacts/genesis.block || die "Failed to generate orderer genesis block"
  echo

  echo "# Generating channel configuration transaction 'channel.tx'"
  configtxgen -profile TwoOrgsChannel -channelID $CHANNEL_NAME -outputCreateChannelTx channel-artifacts/channel.tx || die "Failed to generate channel configuration transaction"
  echo

  export ORG_NAME
  for ORG_NAME in org1 org2; do
    echo "# Generate CCP files for $ORG_NAME"
    TLSCA_CERT_FILE=crypto-config/peerOrganizations/$ORG_NAME.$DOMAIN_NAME/tlsca/tlsca.$ORG_NAME.$DOMAIN_NAME-cert.pem
    CA_CERT_FILE=crypto-config/peerOrganizations/$ORG_NAME.$DOMAIN_NAME/ca/ca.$ORG_NAME.$DOMAIN_NAME-cert.pem
    export TLSCA_CERT="$(one_line_pem $TLSCA_CERT_FILE)"
    export CA_CERT="$(one_line_pem $CA_CERT_FILE)"

    envsubst < ccp-template.json > connection-$ORG_NAME.json
    envsubst < ccp-template.yaml | yaml_expand_nl > connection-$ORG_NAME.yaml

    echo "# Generating anchor peer update for Org1MSP"
    configtxgen -profile TwoOrgsChannel -channelID $CHANNEL_NAME -asOrg $ORG_NAME-msp -outputAnchorPeersUpdate channel-artifacts/$ORG_NAME-msp-anchors.tx || die "Failed to generate anchor peer update for $ORG_NAME-msp..."
    echo
  done

}

which cryptogen >/dev/null || die "cryptogen tool not found. exiting"
which configtxgen >/dev/null || die "configtxgen tool not found. exiting"

export DOMAIN_NAME=svc.cluster.local
export PEER_PORT=7051
export CA_PORT=7054
SYS_CHANNEL="sys-channel"
CHANNEL_NAME="mychannel"

MODE="$1"
shift
while getopts "h?c:i:" opt; do
  case "$opt" in
    h | \?) printHelp; exit 0;;
    c) CHANNEL_NAME=$OPTARG;;
  esac
done


case "$MODE" in
  "")
    printHelp;;

  generate)
    echo Generating certs and genesis block
    set -vx
    generateArtifacts
    set +vx
    ;;

  mrproper)
    echo Wiping config data
    set -vx
    rm -rf channel-artifacts/*.block channel-artifacts/*.tx crypto-config
    set +vx
    ;;
esac

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
#
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

# vim: set sw=2 ts=2 et:
