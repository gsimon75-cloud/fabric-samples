/*
 * SPDX-License-Identifier: Apache-2.0
 */

"use strict";
const util = require("util");

const { FileSystemWallet, Gateway } = require("fabric-network");
const fs = require("fs");
const path = require("path");

// connection params
const ccpPath = "connection-org1.json";
const userName = "user1";

// chaincode params
const org_name = "Org1MSP";
const channel_name = "mychannel";
const chaincode_id = "mycc";
const chaincode_path = "./chaincode";

async function main() {
    try {
        const walletPath = path.join(process.cwd(), "wallet");
        console.log("Opening wallet; path='" + walletPath + "'");
        const wallet = new FileSystemWallet(walletPath);

        // Check to see if we"ve already enrolled the user.
        console.log("Checking for user; name='" + userName + "'");
        const userExists = await wallet.exists(userName);
        if (!userExists) {
            console.log("Run the registerUser.js application before retrying");
            return;
        }

        console.log("Reading connection param file; path='" + ccpPath + "'");
        const ccpJSON = fs.readFileSync(ccpPath, "utf8");
        const ccp = JSON.parse(ccpJSON);

        // parse the chaincode version from its package.json
        const cc_pkg = JSON.parse(fs.readFileSync(chaincode_path + "/package.json", "utf8"));
        const chaincode_version = cc_pkg.version;
        console.log("Chaincode version detected; version='" + chaincode_version + "'");

        // Create a new gateway for connecting to our peer node.
        console.log("Connecting to gateway;");
        const gateway = new Gateway();
        await gateway.connect(ccpPath, { wallet, identity: "user1", discovery: { enabled: true, asLocalhost: true } });

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
        let installResponse = await client.installChaincode({
            targets: peers,
            chaincodeType: "node",
            chaincodeId: chaincode_id,
            chaincodeVersion: chaincode_version,
            chaincodePath: chaincode_path,
            channelNames: [channel_name]
        });
        if (installResponse[0][0] instanceof Error) {
            console.log("Install failed; code='" + installResponse[0][0].code + "', message='" + installResponse[0][0].message + "'");
            //console.log("Install failed; installResponse='" + util.inspect(installResponse) + "'");
            return;
        }

        console.log("Getting network and channel;");
        let network = await gateway.getNetwork(channel_name);
        let channel = await network.getChannel();

        console.log("Sending upgrade proposal;");
        let proposalResponse = await channel.sendUpgradeProposal({
            targets: peers,
            chaincodeType: "node",
            chaincodeId: chaincode_id,
            chaincodeVersion: chaincode_version,
            fcn: "upgrade",
            args: ["c", "d", "1000", "2000"],
            txId: client.newTransactionID()
        });
        if (proposalResponse[0][0] instanceof Error) {
            let upgradeResponse = proposalResponse;
            console.log("Upgrade failed, trying to Instantiate");
            proposalResponse = await channel.sendInstantiateProposal({
                targets: peers,
                chaincodeType: "node",
                chaincodeId: chaincode_id,
                chaincodeVersion: chaincode_version,
                fcn: "instantiate",
                args: ["c", "d", "1000", "2000"],
                txId: client.newTransactionID()
            });
            console.log("proposalResponse=" + util.inspect(proposalResponse));
            if (proposalResponse[0][0] instanceof Error) {
                console.log("Instantiate failed as well;");
                console.log("Upgrade error; code='" + upgradeResponse[0][0].code + "', message='" + upgradeResponse[0][0].message + "'");
                console.log("Instantiate error; code='" + proposalResponse[0][0].code + "', message='" + proposalResponse[0][0].message + "'");
                return;
            }
        }

        console.log("Sending the transaction;");
        const transactionResponse = await channel.sendTransaction({
            proposalResponses: proposalResponse[0],
            proposal: proposalResponse[1]
        });

        if (transactionResponse.status != "SUCCESS") {
            console.log("Transaction failed; transactionResponse='" + util.inspect(transactionResponse) + "'");
        }

        console.log("Success;");
    }
    catch (error) {
        console.error("Operation failed; error='" + util.inspect(error) + "'");
        process.exit(1);
    }
}

main();

// vim: set sw=4 ts=4 et:
