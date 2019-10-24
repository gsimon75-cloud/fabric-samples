/*
 * SPDX-License-Identifier: Apache-2.0
 */

"use strict";
const util = require("util");

const { FileSystemWallet, Gateway } = require("fabric-network");
const fs = require("fs");
const path = require("path");

// connection params
const ccp_path = "connection-org1.json";
const user_name = "user1";

// chaincode params
const org_name = "Org1MSP";
const channel_name = "mychannel";
const chaincode_id = "mycc";
const chaincode_path = "./chaincode";

async function main() {
    try {
        const wallet_path = path.join(process.cwd(), "wallet");
        console.log("Opening wallet; path='" + wallet_path + "'");
        const wallet = new FileSystemWallet(wallet_path);

        // Check to see if we've already enrolled the user.
        console.log("Checking for user; name='" + user_name + "'");
        const user_exists = await wallet.exists(user_name);
        if (!user_exists) {
            console.log("No such user; user='" + user_name + "'");
            console.log("Run the registerUser.js application before retrying");
            return;
        }

        // parse the chaincode version from its package.json
        const cc_pkg = JSON.parse(fs.readFileSync(chaincode_path + "/package.json", "utf8"));
        const chaincode_version = cc_pkg.version;
        console.log("Chaincode version detected; version='" + chaincode_version + "'");

        // Create a new gateway for connecting to our peer node.
        console.log("Connecting to gateway;");
        const gateway = new Gateway();
        await gateway.connect(ccp_path, { wallet, identity: "user1", discovery: { enabled: true, asLocalhost: true } });

        console.log("Getting client;");
        const client = gateway.getClient();
        console.log("Retrieved client; mspid='" + client.getMspid() + "'");

        console.log("Getting peers;");
        const peers = client.getPeersForOrg(org_name);
        if (peers.length < 1) {
            console.log("No peers found");
            return;
        }
        peers.forEach(peer => {
            console.log("Retrieved peer; name='" + peer.getName() + "', url='" + peer.getUrl() + "'");
        });

        console.log("Installing chaincode;");
        let install_response = await client.installChaincode({
            targets: peers,
            chaincodeType: "node",
            chaincodeId: chaincode_id,
            chaincodeVersion: chaincode_version,
            chaincodePath: chaincode_path,
            channelNames: [channel_name]
        });
        if (install_response[0][0] instanceof Error) {
            console.log("Install failed; code='" + install_response[0][0].code + "', message='" + install_response[0][0].message + "'");
            //console.log("Install failed; install_response='" + util.inspect(install_response) + "'");
            return;
        }

        console.log("Getting network and channel;");
        let network = await gateway.getNetwork(channel_name);
        let channel = await network.getChannel();

        console.log("Sending upgrade proposal;");
        let proposal_response = await channel.sendUpgradeProposal({
            targets: peers,
            chaincodeType: "node",
            chaincodeId: chaincode_id,
            chaincodeVersion: chaincode_version,
            fcn: "upgrade",
            args: ["c", "1000", "d", "2000"],
            txId: client.newTransactionID()
        });
        if (proposal_response[0][0] instanceof Error) {
            let upgrade_response = proposal_response;
            console.log("Upgrade failed, trying to Instantiate");
            proposal_response = await channel.sendInstantiateProposal({
                targets: peers,
                chaincodeType: "node",
                chaincodeId: chaincode_id,
                chaincodeVersion: chaincode_version,
                fcn: "instantiate",
                args: ["c", "1000", "d", "2000"],
                txId: client.newTransactionID()
            });
            console.log("proposal_response=" + util.inspect(proposal_response));
            if (proposal_response[0][0] instanceof Error) {
                console.log("Instantiate failed as well;");
                console.log("Upgrade error; code='" + upgrade_response[0][0].code + "', message='" + upgrade_response[0][0].message + "'");
                console.log("Instantiate error; code='" + proposal_response[0][0].code + "', message='" + proposal_response[0][0].message + "'");
                return;
            }
        }

        console.log("Sending the transaction;");
        const transaction_response = await channel.sendTransaction({
            proposalResponses: proposal_response[0],
            proposal: proposal_response[1]
        });

        if (transaction_response.status != "SUCCESS") {
            console.log("Transaction failed; transaction_response='" + util.inspect(transaction_response) + "'");
            return;
        }

        await gateway.disconnect();
        console.log("Success;");
    }
    catch (error) {
        console.error("Operation failed; error='" + util.inspect(error) + "'");
        process.exit(1);
    }
}

main();

// vim: set sw=4 ts=4 et:
