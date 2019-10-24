/*
 * SPDX-License-Identifier: Apache-2.0
 */

"use strict";
const util = require("util");

const { FileSystemWallet, Gateway } = require("fabric-network");
const path = require("path");

// connection params
const ccp_path = "connection-org1.json";
const user_name = "user1";

// chaincode params
const channel_name = "mychannel";
const chaincode_id = "mycc";

async function main() {
    try {
        const wallet_path = path.join(process.cwd(), "wallet");
        console.log("Opening wallet; path='" + wallet_path + "'");
        const wallet = new FileSystemWallet(wallet_path);

        console.log("Checking for user; name='" + user_name + "'");
        const user_exists = await wallet.exists(user_name);
        if (!user_exists) {
            console.log("No such user; user='" + user_name + "'");
            console.log("Run the registerUser.js application before retrying");
            return;
        }

        console.log("Connecting to gateway;");
        const gateway = new Gateway();
        await gateway.connect(ccp_path, { wallet, identity: user_name, discovery: { enabled: true, asLocalhost: true } });

        console.log("Getting network and contract;");
        const network = await gateway.getNetwork(channel_name);
        const contract = network.getContract(chaincode_id);

        console.log("Submitting transaction;");
        await contract.submitTransaction(process.argv[1+1], process.argv[1+2], process.argv[1+3], process.argv[1+4]);
        console.log("Transaction submitted;");

        await gateway.disconnect();
    }
    catch (error) {
        console.error("Operation failed; error='" + util.inspect(error) + "'");
        process.exit(1);
    }
}

main();

// vim: set sw=4 ts=4 et:
