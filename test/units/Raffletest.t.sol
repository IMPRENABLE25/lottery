// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {Loterie} from "../../src/Raffle.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployRaffle} from "../../script/Deploy.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {Vm} from "forge-std/Vm.sol";
import {CodeConstants} from "../../script/HelperConfig.s.sol";

contract Raffletest is CodeConstants, Test {
    Loterie public loterie;
    DeployRaffle deployer;
    HelperConfig public helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint256 subscriptionId;
    uint32 callbackGasLimit;

    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);
    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployRaffle();
        (loterie, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        subscriptionId = config.subscriptionId;
        callbackGasLimit = config.callbackGasLimit;

        //attribuer des fonds au joueur
        vm.deal(PLAYER, STARTING_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        assert(loterie.getRaffleState() == Loterie.RaffleState.OPEN);
    }

    //TEST DES CONDITIONS DE PARTICIPATION
    function testRaffleWhwnYoudontPayEnoughEth() public {
        // Arrange / Act
        vm.prank(PLAYER);
        // Assert
        vm.expectRevert(Loterie.NotEnoughEth.selector);
        loterie.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        // Arrange
        vm.prank(PLAYER);
        // Act
        loterie.enterRaffle{value: entranceFee}();
        // Assert
        address playerRecorded = loterie.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    //Test des Events
    function testEmitsEventOnEntrance() public {
        // Arrange
        vm.prank(PLAYER);
        // Assert
        vm.expectEmit(true, false, false, false, address(loterie));
        emit RaffleEntered(PLAYER);
        // Act
        loterie.enterRaffle{value: entranceFee}();
    }

    //Test quand on est entrain de faire le tirage
    function testDontAllowEntranceWhenRaffleIsCalculating() public {
        // Arrange
        vm.prank(PLAYER);
        loterie.enterRaffle{value: entranceFee}();
        //Faire passer le temps
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        loterie.checkUpkeep("");
        loterie.performUpkeep("");
        // Assert
        vm.expectRevert(Loterie.Raffle_NotOpen.selector);
        // Act
        vm.prank(PLAYER);
        loterie.enterRaffle{value: entranceFee}();
    }

    //Test Checkupkeep
    function testCheckupkeepReturnFalseIfitHasNoBalance() public {
        // Arrange
        //Faire passer le temps
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        //act
        (bool upkeepNeeded,) = loterie.checkUpkeep("");
        //assert
        assert(!upkeepNeeded);
    }

    function testCheckupReturnFalseIfRaffleNotOpen() public {
        // Arrange
        vm.prank(PLAYER);
        loterie.enterRaffle{value: entranceFee}();
        //Faire passer le temps
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        loterie.checkUpkeep("");
        loterie.performUpkeep("");
        //act
        (bool upkeepNeeded,) = loterie.checkUpkeep("");
        //assert
        assert(!upkeepNeeded);
    }

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        // Arrange
        vm.prank(PLAYER);
        loterie.enterRaffle{value: entranceFee}();
        //Faire passer le temps
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        // Act / Assert
        loterie.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckupIsFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numberOfPlayers = 0;
        Loterie.RaffleState raffleState = Loterie.RaffleState.OPEN;
        vm.prank(PLAYER);
        loterie.enterRaffle{value: entranceFee}();
        currentBalance = currentBalance + entranceFee;
        numberOfPlayers = 1;
        // Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Loterie.Raffle_UpkeepNotNeeded.selector, currentBalance, numberOfPlayers, uint256(raffleState)
            )
        );
        loterie.performUpkeep("");
    }
    
    //TEST FULL FILL RANDOM WORDS
    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    //FUZZ Test (Pour augmenter la couverture de test de nombre aléatoire, dans toml augmenter le fuzz runs)
    function testFullfillrandomWordscanOnlyBeCalledAfterPerformUpkeep(uint256 randomrequestId) public skipFork {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomrequestId, address(loterie));
    }

    //Test de choix du gagnant
    function testFulfillrandomWordsPicksAWinnerResetsTheRaffleAndSendsMoney() public skipFork {
        vm.prank(PLAYER);
        loterie.enterRaffle{value: entranceFee}();
        // Arrange
        uint256 additionalEntrants = 3;
        uint256 startingIndex = 1;
        address expectedWinner = address(1);
        for (uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
            // Chaque joueur a un solde initial
            address newPlayer = address(uint160(i));
            hoax(newPlayer, 1 ether);
            loterie.enterRaffle{value: entranceFee}();
        }
        uint256 startingTimestamp = loterie.getLastTimeStamp();
        uint256 winnerStartingBalance = expectedWinner.balance;
        //act
        vm.recordLogs();
        //Faire passer le temps
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        loterie.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // Decode the RandomWordsRequested non-indexed data from the first (and only) log entry.));
        console2.logBytes32(entries[1].topics[1]);
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(loterie));
        //assert
        address recentWinner = loterie.getRecentWinner();
        Loterie.RaffleState raffleState = loterie.getRaffleState();
        uint256 winnerEndingBalance = recentWinner.balance;
        uint256 endingTimestamp = loterie.getLastTimeStamp();
        uint256 prize = entranceFee * (additionalEntrants + 1);

        assert(recentWinner == expectedWinner);
        assert(raffleState == Loterie.RaffleState.OPEN);
        assert(winnerEndingBalance == winnerStartingBalance + prize);
        assert(endingTimestamp > startingTimestamp);
    }
}
