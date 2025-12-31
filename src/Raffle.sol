// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {VRFV2PlusClient} from "@chainlink/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";

/**
 * @title Simple contrat de loterie
 * @author Jonas Ayaovi
 *
 */

contract Loterie is VRFConsumerBaseV2Plus {
    /* Erreur  */
    error NotEnoughEth();
    error Raffle_NotOpen();
    error Raffle_TransferFailed();
    error Raffle_UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);

    enum RaffleState {
        OPEN,
        CALCULATING
    }

    //les frais sont immutable pour une bonne gestion de frais de gaz
    uint256 private immutable I_ENTRANCE_FEE;
    uint256 private immutable I_INTERVAL;
    bytes32 private immutable I_KEYHASH;
    uint256 private immutable I_SUBSCRIPTIONID;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private sCallbackGasLimit;
    uint32 private constant NUM_WORDS = 1;
    address payable[] private players;
    uint256 private sLastTimeStamp;
    address private sRecentWinner;
    RaffleState private sRaffleState;

    /* Event*/
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entrancefee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        I_ENTRANCE_FEE = entrancefee;
        I_INTERVAL = interval;
        sLastTimeStamp = block.timestamp;
        I_KEYHASH = gasLane;
        I_SUBSCRIPTIONID = subscriptionId;
        sCallbackGasLimit = callbackGasLimit;
        sRaffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        //Condition pour participer au tirage
        if (msg.value < I_ENTRANCE_FEE) {
            revert NotEnoughEth();
        }
        if (sRaffleState != RaffleState.OPEN) {
            revert Raffle_NotOpen();
        }
        //Garder une trace des joueurs
        players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender);
    }

    //Quand faut il choisir le gagnant ?
    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        returns (
            bool upkeepNeeded,
            bytes memory /* performData */
        )
    {
        bool isOpen = (sRaffleState == RaffleState.OPEN);
        bool timePassed = ((block.timestamp - sLastTimeStamp) > I_INTERVAL);
        bool hasPlayers = (players.length > 0);
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (isOpen && timePassed && hasPlayers && hasBalance);
        return (upkeepNeeded, "");
    }

    function performUpkeep(
        bytes calldata /* performData */
    )
        external
    {
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle_UpkeepNotNeeded(address(this).balance, players.length, uint256(sRaffleState));
        }
        sRaffleState = RaffleState.CALCULATING;

        //Requête vers chainlink pour avoir le nombre aléatoire
        //Si le nativePayement est en true , celà utilise des Eth à la place des LINK
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: I_KEYHASH,
            subId: I_SUBSCRIPTIONID,
            requestConfirmations: REQUEST_CONFIRMATIONS,
            callbackGasLimit: sCallbackGasLimit,
            numWords: NUM_WORDS,
            extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
        });
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        emit RequestedRaffleWinner(requestId);
    }

    //Obtention du nombre aléatoire
    function fulfillRandomWords(
        uint256,
        /* requestId*/
        uint256[] calldata randomWords
    )
        internal
        override
    {
        //choisir le gagnant
        uint256 indexOfWinner = randomWords[0] % players.length;
        address payable winner = players[indexOfWinner];
        sRecentWinner = winner;

        //Préparer la loterie pour le prochain tour
        sRaffleState = RaffleState.OPEN;
        players = new address payable[](0);
        sLastTimeStamp = block.timestamp;
        emit WinnerPicked(sRecentWinner);

        //Envoyer l'argent au gagnant
        (bool success,) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle_TransferFailed();
        }
    }

    /**
     * Getters function
     */
    function getEntrance() external view returns (uint256) {
        return I_ENTRANCE_FEE;
    }

    function getRaffleState() external view returns (RaffleState) {
        return sRaffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return players[indexOfPlayer];
    }

    //Dernier timestamp
    function getLastTimeStamp() external view returns (uint256) {
        return sLastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return sRecentWinner;
    }
    function getNumberOfPlayers() external view returns (uint256) {
        return players.length;
    }
    function getEntranceFee() external view returns (uint256) {
        return I_ENTRANCE_FEE;
    }
}

