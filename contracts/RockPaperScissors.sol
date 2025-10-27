// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract RockPaperScissors is VRFConsumerBaseV2Plus {

    address public gameOwner;
    uint public totalGames;
    uint public betAmount;
    uint public houseEdge;

    // Chainlink VRF v2.5 Configuration
    uint256 s_subscriptionId;
    bytes32 s_keyHash;
    uint32 s_callbackGasLimit = 100000;
    uint16 s_requestConfirmations = 3;
    uint32 s_numWords = 2;
    bool s_nativePayment = true;

    // Single Game
    struct SingleGameRequest {
        address player;
        uint256 betAmount;
        uint8 playerChoice;
        bool fulfilled;
    }

    mapping(uint256 => SingleGameRequest) public singleGameRequests;

    mapping(address => uint) public wins;
    mapping(address => uint) public losses;
    mapping(address => uint) public totalProfits;

    modifier onlyGameOwner() {
        require(msg.sender == gameOwner, "Only the game owner can call this function");
        _;
    }

    modifier validMove(uint move) {
        require(move >= 1 && move <= 3, "Invalid move. Choose 1 (Rock), 2 (Paper), or 3 (Scissors)");
        _;
    }

    event SingleGameStarted(uint256 requestId, address player);
    event SingleGameResult(address player, uint256 playerChoice, uint256 houseChoice, uint256 result, uint256 payout);


    constructor(
        uint _betAmount,
        uint _houseEdge,
        uint256 subscriptionId,
        address vrfCoordinator,
        bytes32 keyHash
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        require(_betAmount > 0, "Bet amount must be greater than zero");
        require(_houseEdge <= 1000, "House edge cannot exceed 10%");

        gameOwner = msg.sender;
        totalGames = 0;
        betAmount = _betAmount;
        houseEdge = _houseEdge;

        s_subscriptionId = subscriptionId;
        s_keyHash = keyHash;

    }

    function playAgainstHouse(uint8 playerChoice) public payable {
        require(msg.value == betAmount, "Incorrect bet");
        require(address(this).balance >= betAmount * 2, "Insufficient house founds");

        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: s_keyHash,
                subId: s_subscriptionId,
                requestConfirmations: s_requestConfirmations,
                callbackGasLimit: s_callbackGasLimit,
                numWords: s_numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: s_nativePayment})
                )
            })
        );

        singleGameRequests[requestId] = SingleGameRequest({
            player: msg.sender,
            betAmount: betAmount,
            playerChoice: playerChoice,
            fulfilled: false
        });

        totalGames++;
        emit SingleGameStarted(requestId, msg.sender);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        SingleGameRequest storage gameRequest = singleGameRequests[requestId];

        require(!gameRequest.fulfilled, "Game already fulfilled");
        require(gameRequest.player != address(0), "Invalid game request");

        uint256 houseChoice = (randomWords[0] % 3) + 1;

        uint256 result = calculateWinner(gameRequest.playerChoice, houseChoice);
        uint256 payout = 0;

        address player = gameRequest.player;

        if (result == 0) {
            payout = gameRequest.betAmount;
            (bool refund, ) = player.call{value: payout}("");
            require(refund, "Refund failed");
        } else if (result == 1) {
            uint256 pot = gameRequest.betAmount * 2;
            uint256 houseEdgePart = (pot * houseEdge) / 10000;
            payout = pot - houseEdgePart;

            (bool success, ) = player.call{value: payout}("");
            require(success, "Payout failed");

            wins[player] += 1;
            totalProfits[player] += payout;
        } else {
            losses[player] += 1;
        }

        gameRequest.fulfilled = true;
        emit SingleGameResult(player, gameRequest.playerChoice, houseChoice, result, payout);
    }

    // Utility function
    function calculateWinner(uint choice1, uint choice2) public pure returns (uint) {
        if (choice1 == choice2) {
            return 0;
        } else if (
            (choice1 == 1 && choice2 == 3) ||
            (choice1 == 2 && choice2 == 1) ||
            (choice1 == 3 && choice2 == 2)
        ) {
            return 1;
        } else {
            return 2;
        }
    }


    // View functions
    function getPlayerStats(address _player) public view returns (
        uint _wins,
        uint _losses,
        uint _totalProfits
    ) {
        return (wins[_player], losses[_player], totalProfits[_player]);
    }

    // Owner functions
    function depositFunds() external payable onlyGameOwner {}

    function withdrawFunds(uint amount) external onlyGameOwner {
        require(amount <= address(this).balance, "Not enough balance");
        (bool success, ) = gameOwner.call{value: amount}("");
        require(success, "Withdraw failed");
    }
}