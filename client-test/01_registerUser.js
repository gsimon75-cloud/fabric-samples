/*
 * SPDX-License-Identifier: Apache-2.0
 */

"use strict";

const { FileSystemWallet, Gateway, X509WalletMixin } = require("fabric-network");
const path = require("path");

// connection params
const ccp_path = "connection-org1.json";
const admin_name = "admin";
const user_name = "user1";
const user_affiliation = "org1.department1";

// chaincode params
const org_mspid = "Org1MSP";

async function main() {
    try {
        // Create a new file system based wallet for managing identities.
        const wallet_path = path.join(process.cwd(), "wallet");
        console.log("Opening wallet; path='" + wallet_path + "'");
        const wallet = new FileSystemWallet(wallet_path);

        // Check to see if we've already enrolled the user.
        const user_exists = await wallet.exists(user_name);
        if (user_exists) {
            console.log("User already exists; user='" + user_name + "'");
            return;
        }

        // Check to see if we've already enrolled the admin user.
        const admin_exists = await wallet.exists("admin");
        if (!admin_exists) {
            console.log("No such user; user='" + admin_name + "'");
            console.log("Run the enrollAdmin.js application before retrying");
            return;
        }

        // Create a new gateway for connecting to our peer node.
        console.log("Connecting to gateway;");
        const gateway = new Gateway();
        await gateway.connect(ccp_path, { wallet, identity: admin_name, discovery: { enabled: true, asLocalhost: true } });

        console.log("Getting admin identity;");
        const admin_identity = gateway.getCurrentIdentity();

        // Get the CA client object from the gateway for interacting with the CA.
        console.log("Getting client;");
        const client = gateway.getClient();
        console.log("Retrieved client; mspid='" + client.getMspid() + "'");

        console.log("Getting ca;");
        const ca = client.getCertificateAuthority();
        console.log("Retrieved ca; name='" + ca.getName() + "', url='" + ca.getUrl() + "'");

        console.log("Registering user; name='" + user_name + "'");
        const secret = await ca.register({ affiliation: user_affiliation, enrollmentID: user_name, role: "admin" }, admin_identity);

        console.log("Enrolling user; name='" + user_name + "'");
        const enrollment = await ca.enroll({ enrollmentID: user_name, enrollmentSecret: secret });

        console.log("Creating identity;");
        const user_identity = X509WalletMixin.createIdentity(org_mspid, enrollment.certificate, enrollment.key.toBytes());

        console.log("Adding identity to wallet;");
        await wallet.import(user_name, user_identity);

        console.log("Success;");
        await gateway.disconnect();
    }
    catch (error) {
        console.error("Operation failed; error='" + util.inspect(error) + "'");
        process.exit(1);
    }
}

main();

// vim: set sw=4 ts=4 et:
