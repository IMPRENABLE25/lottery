// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;
import {Script} from "forge-std/Script.sol";
import {Loterie} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscriptionC, FundSubscriptionC, AddConsumerC} from "./Interactions.s.sol";

contract DeployRaffle is Script {
    //local -> deploy mock , get local config
    // sepolia -> get sepolia config

    function run() public {
        deployContract();
    }

    function deployContract() public returns (Loterie, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        //Création de l'abonnement VRF
        if (config.subscriptionId == 0) {
            CreateSubscriptionC subscriptioncreate = new CreateSubscriptionC();
            (config.subscriptionId, config.vrfCoordinator) =
                subscriptioncreate.createSubscription(config.vrfCoordinator, config.account);
        }
        //Fund it
        FundSubscriptionC fundSubscription = new FundSubscriptionC();
        fundSubscription.fundSubscription(config.vrfCoordinator, config.subscriptionId, config.link, config.account);

        vm.startBroadcast(config.account);
        Loterie loterie = new Loterie(
            config.entranceFee,
            config.interval,
            config.vrfCoordinator,
            config.gasLane,
            config.subscriptionId,
            config.callbackGasLimit
        );
        vm.stopBroadcast();

        AddConsumerC addconsumer = new AddConsumerC();
        addconsumer.addConsumer(address(loterie), config.vrfCoordinator, config.subscriptionId, config.account);
        return (loterie, helperConfig);
    }
}
