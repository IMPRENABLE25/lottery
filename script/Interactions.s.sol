// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig, CodeConstants} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";

//Création de la souscription VRF

contract CreateSubscriptionC is Script {
    function createSubscriptionUsingConfig() public returns (uint256, address) {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        address account = helperConfig.getConfig().account;
        (uint256 subId,) = createSubscription(vrfCoordinator, account);
        return (subId, vrfCoordinator);
    }

    function createSubscription(address vrfCoordinator, address account) public returns (uint256, address) {
        console.log("Creation de la souscription sur l'ID ", block.chainid);
        vm.startBroadcast(account);
        uint256 subId = VRFCoordinatorV2_5Mock(vrfCoordinator).createSubscription();
        vm.stopBroadcast();
        console.log("Your subscription ID is :", subId);
        console.log("Please update the subscriptionId in the HelperConfig.s.sol file");
        return (subId, vrfCoordinator);
    }

    function run() external returns (uint256, address) {
        createSubscriptionUsingConfig();
    }
}


//Ajout de consommateurs à la souscription VRF
contract AddConsumerC is Script {
    function addConsumerUsingConfig(address mostRecentlyDeployed) public {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        uint256 subId = helperConfig.getConfig().subscriptionId;
        address account = helperConfig.getConfig().account;
        addConsumer(mostRecentlyDeployed, vrfCoordinator, subId, account);
    }

    function addConsumer(address contractToaddvrf, address vrfCoordinator, uint256 subId, address account) public {
        console.log("Adding consumer contract ", contractToaddvrf);
        console.log("To VrfCoordinator :", vrfCoordinator);
        console.log("On chain ID :", subId);

        vm.startBroadcast(account);
        VRFCoordinatorV2_5Mock(vrfCoordinator).addConsumer(subId, contractToaddvrf);
        vm.stopBroadcast();
    }

    function run() external {
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment("Loterie", block.chainid);
        addConsumerUsingConfig(mostRecentlyDeployed);
    }
}
//Financement de la souscription VRF
contract FundSubscriptionC is Script, CodeConstants {
    uint256 public constant FUND_AMOUNT = 2 ether;

    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        uint256 subscriptionId = helperConfig.getConfig().subscriptionId;
        address link = helperConfig.getConfig().link;
        address account = helperConfig.getConfig().account;
        fundSubscription(vrfCoordinator, subscriptionId, link, account);
    }

    function fundSubscription(address vrfCoordinator, uint256 subscriptionId, address link, address account) public {
        console.log("On chainID", block.chainid);
        console.log("Funding subscription :", subscriptionId);
        console.log("Using vrfCoordinator :", vrfCoordinator);

        if (block.chainid == LOCAL_CHAIN_ID) {
            vm.startBroadcast(account);
            VRFCoordinatorV2_5Mock(vrfCoordinator).fundSubscription(subscriptionId, FUND_AMOUNT * 100);
            vm.stopBroadcast();
        } else {
            vm.startBroadcast(account);
            //Transfert de LINK au contrat VRFCoordinator pour financer la souscription
            LinkToken(link).transferAndCall(vrfCoordinator, FUND_AMOUNT, abi.encode(subscriptionId));
            vm.stopBroadcast();
        }
    }

    function run() external {
        fundSubscriptionUsingConfig();
    }
}

