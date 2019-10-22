/*
 * SPDX-License-Identifier: Apache-2.0
 */

'use strict';
const util = require('util');

const { FileSystemWallet, Gateway } = require('fabric-network');
const fs = require('fs');
const path = require('path');

// connection params
const ccpPath = 'connection-org1.json';

// chaincode params
const org_name = 'Org1MSP';
const channel_name = 'mychannel';
const chaincode_id = 'mycc';
const chaincode_path = './chaincode';

async function main() {
    try {
        // Create a new file system based wallet for managing identities.
        const walletPath = path.join(process.cwd(), 'wallet');
        const wallet = new FileSystemWallet(walletPath);
        console.log("Wallet path: " + walletPath);

        // Check to see if we've already enrolled the user.
        const userExists = await wallet.exists('user1');
        if (!userExists) {
            console.log('Run the registerUser.js application before retrying');
            return;
        }

        // read the connection param file
        const ccpJSON = fs.readFileSync(ccpPath, 'utf8');
        const ccp = JSON.parse(ccpJSON);

        // parse the chaincode version from its package.json
        const cc_pkg = JSON.parse(fs.readFileSync(chaincode_path + "/package.json", 'utf8'));
        const chaincode_version = cc_pkg.version;

        // Create a new gateway for connecting to our peer node.
        const gateway = new Gateway();
        await gateway.connect(ccpPath, { wallet, identity: 'user1', discovery: { enabled: true, asLocalhost: true } });
        console.log('DBG: gateway connected');

        const client = gateway.getClient();
        //console.log("DBG: client=" + util.inspect(client));
        const peers = client.getPeersForOrg(org_name);
        console.log("DBG: peers=" + util.inspect(peers));

        let installResponse = await client.installChaincode({
            targets: peers,
            chaincodeType: 'node',
            chaincodeId: chaincode_id,
            chaincodeVersion: chaincode_version,
            chaincodePath: chaincode_path,
            channelNames: [channel_name]
        });
        console.log("DBG: installResponse=" + util.inspect(installResponse));

        let network = await gateway.getNetwork(channel_name);
        //console.log("DBG: network=" + util.inspect(network));
        let channel = await network.getChannel();
        //console.log("DBG: channel=" + util.inspect(channel));

        let proposalResponse = await channel.sendUpgradeProposal({
            targets: peers,
            chaincodeType: 'node',
            chaincodeId: chaincode_id,
            chaincodeVersion: chaincode_version,
            fcn: 'instantiate',
            args: ['c', 'd', '1000', '2000'],
            txId: client.newTransactionID()
        });

        console.log('proposalResponse=' + util.inspect(proposalResponse));

        console.log('Sending the Transaction ..');
        const transactionResponse = await channel.sendTransaction({
            proposalResponses: proposalResponse[0],
            proposal: proposalResponse[1]
        });

        console.log('transactionResponse=' + util.inspect(transactionResponse));
    }
    catch (error) {
        console.error("Failed: " + util.inspect(error));
        process.exit(1);
    }
}

main();

// vim: set sw=4 ts=4 et:
