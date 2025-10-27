// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RockPaperScissors is VRFConsumerBaseV2Plus {
    using SafeERC20 for IERC20;

    address public gameOwner;
    uint public totalGames;
    uint public totalMultiplayerGames;
    uint public betAmount;
    uint public houseEdge;

    // Multi-tokens
    mapping(address => bool) public supportedTokens;
    mapping(address => uint256) public tokenBetAmounts;
    address[] public tokenList;

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
        bool isTokenGame;
        address token;
    }

    mapping(uint256 => SingleGameRequest) public singleGameRequests;
    mapping(address => uint) public wins;
    mapping(address => uint) public losses;
    mapping(address => uint) public totalProfits;
    mapping(address => mapping(address => uint)) public totalTokenProfits;

    
    struct MultiplayerGame {
        address player1;
        address player2;
        uint8 player1Choice;
        uint8 player2Choice;
        bool player1Committed;
        bool player2Committed;
        uint256 betAmount;
        bool finished;
        bool isTokenGame;
        address token; 
    }
    
    mapping(uint256 => MultiplayerGame) public multiplayerGames;


    modifier onlyGameOwner() {
        require(msg.sender == gameOwner, "Only the game owner can call this function");
        _;
    }

    modifier validMove(uint move) {
        require(move >= 1 && move <= 3, "Invalid move. Choose 1 (Rock), 2 (Paper), or 3 (Scissors)");
        _;
    }

    event SingleGameStarted(uint256 requestId, address player, bool isTokenGame, address token);
    event SingleGameResult(address player, uint256 playerChoice, uint256 houseChoice, uint256 result, uint256 payout, bool isTokenGame, address token);
    event MultiplayerGameCreated(uint256 indexed gameId, address indexed player1, bool isTokenGame, address token);
    event MultiplayerGameJoined(uint256 indexed gameId, address indexed player2);
    event MultiplayerGameResult(uint256 indexed gameId, address winner, uint256 payout, bool isTokenGame, address token);
    event TokenAdded(address indexed token, uint256 betAmount);
    event TokenRemoved(address indexed token);
    event TokenBetAmountUpdated(address indexed token, uint256 newAmount);

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

    function addToken(address _token, uint256 _tokenBetAmount) external onlyGameOwner {
        require(_token != address(0), "Invalid token address");
        require(_tokenBetAmount > 0, "Token bet amount must be greater than zero");
        require(!supportedTokens[_token], "Token already supported");
        
        supportedTokens[_token] = true;
        tokenBetAmounts[_token] = _tokenBetAmount;
        tokenList.push(_token);
        
        emit TokenAdded(_token, _tokenBetAmount);
    }

    function removeToken(address _token) external onlyGameOwner {
        require(supportedTokens[_token], "Token not supported");
        
        supportedTokens[_token] = false;
        tokenBetAmounts[_token] = 0;
        
        for (uint i = 0; i < tokenList.length; i++) {
            if (tokenList[i] == _token) {
                tokenList[i] = tokenList[tokenList.length - 1];
                tokenList.pop();
                break;
            }
        }
        
        emit TokenRemoved(_token);
    }

    function updateTokenBetAmount(address _token, uint256 _newAmount) external onlyGameOwner {
        require(supportedTokens[_token], "Token not supported");
        require(_newAmount > 0, "Token bet amount must be greater than zero");
        
        tokenBetAmounts[_token] = _newAmount;
        emit TokenBetAmountUpdated(_token, _newAmount);
    }

    function isTokenSupported(address _token) public view returns (bool) {
        return supportedTokens[_token];
    }

    function getSupportedTokens() public view returns (address[] memory) {
        return tokenList;
    }

    function getTokenBetAmount(address _token) public view returns (uint256) {
        require(supportedTokens[_token], "Token not supported");
        return tokenBetAmounts[_token];
    }

    function playAgainstHouse(uint8 playerChoice) public payable {
        require(msg.value == betAmount, "Incorrect bet");
        require(address(this).balance >= betAmount * 2, "Insufficient house founds");

        uint256 requestId = _requestRandomWords();

        singleGameRequests[requestId] = SingleGameRequest({
            player: msg.sender,
            betAmount: betAmount,
            playerChoice: playerChoice,
            fulfilled: false,
            isTokenGame: false,
            token: address(0)
        });

        totalGames++;
        emit SingleGameStarted(requestId, msg.sender, false, address(0));
    }

    function playAgainstHouseWithToken(uint8 playerChoice, address _token) public {
        require(supportedTokens[_token], "Token not supported");
        uint256 _tokenBetAmount = tokenBetAmounts[_token];
        
        IERC20 token = IERC20(_token);
        require(token.balanceOf(address(this)) >= _tokenBetAmount * 2, "Insufficient house token funds");

        token.safeTransferFrom(msg.sender, address(this), _tokenBetAmount);

        uint256 requestId = _requestRandomWords();

        singleGameRequests[requestId] = SingleGameRequest({
            player: msg.sender,
            betAmount: _tokenBetAmount,
            playerChoice: playerChoice,
            fulfilled: false,
            isTokenGame: true,
            token: _token
        });

        totalGames++;
        emit SingleGameStarted(requestId, msg.sender, true, _token);
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
            if (gameRequest.isTokenGame) {
                IERC20(gameRequest.token).safeTransfer(player, payout);
            } else {
                (bool refund, ) = player.call{value: payout}("");
                require(refund, "Refund failed");
            }
        } else if (result == 1) {
            uint256 pot = gameRequest.betAmount * 2;
            uint256 houseEdgePart = (pot * houseEdge) / 10000;
            payout = pot - houseEdgePart;

            if (gameRequest.isTokenGame) {
                IERC20(gameRequest.token).safeTransfer(player, payout);
                totalTokenProfits[player][gameRequest.token] += payout;
            } else {
                (bool success, ) = player.call{value: payout}("");
                require(success, "Payout failed");
                totalProfits[player] += payout;
            }

            wins[player] += 1;
        } else {
            losses[player] += 1;
        }

        gameRequest.fulfilled = true;
        emit SingleGameResult(player, gameRequest.playerChoice, houseChoice, result, payout, gameRequest.isTokenGame, gameRequest.token);
    }

    function createMultiplayerGame() external payable returns (uint256) {
        require(msg.value == betAmount, "Incorrect bet");

        totalMultiplayerGames++;
        multiplayerGames[totalMultiplayerGames] = MultiplayerGame({
            player1: msg.sender,
            player2: address(0),
            player1Choice: 0,
            player2Choice: 0,
            player1Committed: false,
            player2Committed: false,
            betAmount: msg.value,
            finished: false,
            isTokenGame: false,
            token: address(0)
        });

        emit MultiplayerGameCreated(totalMultiplayerGames, msg.sender, false, address(0));
        return totalMultiplayerGames;
    }

    function createMultiplayerGameWithToken(address _token) external returns (uint256) {
        require(supportedTokens[_token], "Token not supported");
        uint256 _tokenBetAmount = tokenBetAmounts[_token];
        
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _tokenBetAmount);

        totalMultiplayerGames++;
        multiplayerGames[totalMultiplayerGames] = MultiplayerGame({
            player1: msg.sender,
            player2: address(0),
            player1Choice: 0,
            player2Choice: 0,
            player1Committed: false,
            player2Committed: false,
            betAmount: _tokenBetAmount,
            finished: false,
            isTokenGame: true,
            token: _token
        });

        emit MultiplayerGameCreated(totalMultiplayerGames, msg.sender, true, _token);
        return totalMultiplayerGames;
    }

    function joinMultiplayerGame(uint256 gameId) external payable {
        MultiplayerGame storage game = multiplayerGames[gameId];
        require(game.player1 != address(0), "Game does not exist");
        require(game.player2 == address(0), "Game already has two players");
        require(!game.isTokenGame, "This is a token game, use joinMultiplayerGameWithToken");
        require(msg.value == game.betAmount, "Incorrect bet");

        game.player2 = msg.sender;
        emit MultiplayerGameJoined(gameId, msg.sender);
    }

    function joinMultiplayerGameWithToken(uint256 gameId) external {
        MultiplayerGame storage game = multiplayerGames[gameId];
        require(game.player1 != address(0), "Game does not exist");
        require(game.player2 == address(0), "Game already has two players");
        require(game.isTokenGame, "This is an BNB game, use joinMultiplayerGame");
        require(supportedTokens[game.token], "Token not supported");

        IERC20(game.token).safeTransferFrom(msg.sender, address(this), game.betAmount);

        game.player2 = msg.sender;
        emit MultiplayerGameJoined(gameId, msg.sender);
    }

    function makeMove(uint256 gameId, uint8 choice) external validMove(choice) {
        MultiplayerGame storage game = multiplayerGames[gameId];
        require(!game.finished, "Game finished");
        require(game.player1 != address(0) && game.player2 != address(0), "Game not ready");

        if (msg.sender == game.player1) {
            require(!game.player1Committed, "Already made move");
            game.player1Choice = choice;
            game.player1Committed = true;
        } else if (msg.sender == game.player2) {
            require(!game.player2Committed, "Already made move");
            game.player2Choice = choice;
            game.player2Committed = true;
        } else {
            revert("Not a player in this game");
        }

        if (game.player1Committed && game.player2Committed) {
            _resolveMultiplayerGame(gameId);
        }
    }

    function _resolveMultiplayerGame(uint256 gameId) internal {
        MultiplayerGame storage game = multiplayerGames[gameId];
        uint result = calculateWinner(game.player1Choice, game.player2Choice);
        uint256 pot = game.betAmount * 2;
        uint256 houseEdgePart = (pot * houseEdge) / 10000;
        uint256 payout = pot - houseEdgePart;
        address winner;

        if (result == 0) {
            if (game.isTokenGame) {
                IERC20(game.token).safeTransfer(game.player1, game.betAmount);
                IERC20(game.token).safeTransfer(game.player2, game.betAmount);
            } else {
                (bool s1, ) = game.player1.call{value: game.betAmount}("");
                (bool s2, ) = game.player2.call{value: game.betAmount}("");
                require(s1 && s2, "Refund failed");
            }
        } else if (result == 1) {
            winner = game.player1;
            if (game.isTokenGame) {
                IERC20(game.token).safeTransfer(winner, payout);
                totalTokenProfits[winner][game.token] += payout;
            } else {
                (bool success, ) = winner.call{value: payout}("");
                require(success, "Payout failed");
                totalProfits[winner] += payout;
            }
            wins[winner]++;
            losses[game.player2]++;
        } else {
            winner = game.player2;
            if (game.isTokenGame) {
                IERC20(game.token).safeTransfer(winner, payout);
                totalTokenProfits[winner][game.token] += payout;
            } else {
                (bool success, ) = winner.call{value: payout}("");
                require(success, "Payout failed");
                totalProfits[winner] += payout;
            }
            wins[winner]++;
            losses[game.player1]++;
        }

        game.finished = true;
        emit MultiplayerGameResult(gameId, winner, payout, game.isTokenGame, game.token);
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

    function _requestRandomWords() internal returns (uint256) {
        return s_vrfCoordinator.requestRandomWords(
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
    }

    // View functions
    function getPlayerStats(address _player) public view returns (
        uint _wins,
        uint _losses,
        uint _totalProfits
    ) {
        return (wins[_player], losses[_player], totalProfits[_player]);
    }
    
    function getPlayerTokenProfits(address _player, address _token) public view returns (uint256) {
        return totalTokenProfits[_player][_token];
    }

    function getAllPlayerTokenProfits(address _player) public view returns (
        address[] memory tokens,
        uint256[] memory profits
    ) {
        tokens = new address[](tokenList.length);
        profits = new uint256[](tokenList.length);
        
        for (uint i = 0; i < tokenList.length; i++) {
            tokens[i] = tokenList[i];
            profits[i] = totalTokenProfits[_player][tokenList[i]];
        }
        
        return (tokens, profits);
    }

    // Owner functions
    function depositFunds() external payable onlyGameOwner {}

    function depositTokens(address _token, uint256 amount) external onlyGameOwner {
        require(supportedTokens[_token], "Token not supported");
        IERC20(_token).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdrawFunds(uint amount) external onlyGameOwner {
        require(amount <= address(this).balance, "Not enough balance");
        (bool success, ) = gameOwner.call{value: amount}("");
        require(success, "Withdraw failed");
    }

    function withdrawTokens(address _token, uint256 amount) external onlyGameOwner {
        require(supportedTokens[_token], "Token not supported");
        require(amount <= IERC20(_token).balanceOf(address(this)), "Not enough token balance");
        IERC20(_token).safeTransfer(gameOwner, amount);
    }

    function emergencyWithdrawTokens(address token, uint256 amount) external onlyGameOwner {
        IERC20(token).safeTransfer(gameOwner, amount);
    }

    function getContractTokenBalance(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }
}