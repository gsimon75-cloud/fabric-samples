/*
 * SPDX-License-Identifier: Apache-2.0
 */

"use strict";
const util = require("util");

const FabricCAServices = require("fabric-ca-client");
const { FileSystemWallet, X509WalletMixin } = require("fabric-network");
const fs = require("fs");
const path = require("path");

// connection params
const ccp_path = "connection-org1.json";
const admin_name = "admin";

// chaincode params
const org_mspid = "Org1MSP";

async function main() {
    try {
        // Create a new file system based wallet for managing identities.
        const wallet_path = path.join(process.cwd(), "wallet");
        console.log("Opening wallet; path='" + wallet_path + "'");
        const wallet = new FileSystemWallet(wallet_path);

        // Check to see if we've already enrolled the admin user.
        const admin_exists = await wallet.exists(admin_name);
        if (admin_exists) {
            console.log("User already exists; user='" + admin_name + "'");
            return;
        }

        // Parse the connection param file
        const ccp_json = fs.readFileSync(ccp_path, "utf8");
        const ccp = JSON.parse(ccp_json);

        // Find the (1st) CA for this org
        for (let orgname in ccp.organizations) {
            let org = ccp.organizations[orgname];
            if (org.mspid == org_mspid) {
                var ca_name = org.certificateAuthorities[0];
                break;
            }
        }
        if (!ca_name) {
            console.log("Could not find CA in conn param file; mspid='" + org_mspid + "'");
            return;
        }

        // Create a new CA client for interacting with the CA.
        console.log("Connecting to CA; name='" + ca_name + "'");
        const ca_info = ccp.certificateAuthorities[ca_name];
        const ca = new FabricCAServices(ca_info.url, { trustedRoots: ca_info.tlsCACerts.pem, verify: false }, ca_info.caName);

        // Enroll the admin user, and import the new identity into the wallet.
        console.log("Enrolling user; name='" + admin_name + "'");
        const enrollment = await ca.enroll({ enrollmentID: admin_name, enrollmentSecret: admin_name + "pw" });

        console.log("Creating identity;");
        const identity = X509WalletMixin.createIdentity(org_mspid, enrollment.certificate, enrollment.key.toBytes());

        console.log("Adding identity to wallet;");
        await wallet.import("admin", identity);

        console.log("Success;");
    }
    catch (error) {
        console.error("Operation failed; error='" + util.inspect(error) + "'");
        process.exit(1);
    }
}

main();

// vim: set sw=4 ts=4 et:
