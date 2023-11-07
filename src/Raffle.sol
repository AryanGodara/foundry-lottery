// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title Raffle
 * @author Aryan Godara
 * @notice This contract is for creating a simple raffle
 * @dev Implements Chainlik VRFv2
 */
contract Raffle is VRFConsumerBaseV2 {
    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, RaffleState raffleState);

    // ** Type Declarations
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    // ** State Variables
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1; // How many random numbers we want

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval; //? @dev Duration of the lottery in seconds
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64  private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    // ** Events
    event EnteredRaffle(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;                                    // Entrance fee in wei
        i_interval = interval;                                          // Duration of the lottery in seconds
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);   // VRF Coordinator
        i_gasLane = gasLane;                                            // gas lane
        i_subscriptionId = subscriptionId;                              // Id we funded with link in order to make these requests
        i_callbackGasLimit = callbackGasLimit;                          // Make sure that we don't overspend on this call
        s_lastTimeStamp = block.timestamp;                                // Set the last time stamp to the current block timestamp
        s_raffleState = RaffleState.OPEN;                                   // Set the initial state to open
    }

    function enterRaffle() external payable {
        // require(msg.value >= i_entranceFee, "Raffle: Not enough ETH sent");
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN ) {
            revert Raffle__RaffleNotOpen();
        }

        s_players.push(payable(msg.sender)); // Push the player to the array, payable is used to convert the address to a payable address
        emit EnteredRaffle(msg.sender);
    }

    // When is the winner supposed to be picked?
    /**
     * @dev This is the function that the Chainlink Automation nodes call to see if it's time to perform an upkeep.
     * The following should be true for this to return true:
     * 1. The time internval has passed between raffle runs
     * 2. The raffle is in the OPEN state
     * 4. (Implicit) The subscription is funded with LINK
     * @return upkeepNeeded 
     * @return performData 
     */
    function checkUpkeep(
        bytes memory /*checkData*/
    ) public view returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = ( (block.timestamp - s_lastTimeStamp) >= i_interval ) 
                    && ( s_raffleState == RaffleState.OPEN )
                    && ( address(this).balance > 0 )
                    && ( s_players.length > 0 );
        performData = "0x0";
    }

    function performUpkeep(bytes calldata /*performData*/) public {
        (bool upkeepNeeded, ) = checkUpkeep("0x0");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                s_raffleState
            );
        }
        // Check if enough time has passed
        if( block.timestamp - s_lastTimeStamp < i_interval) {
            revert();
        }
        s_raffleState = RaffleState.CALCULATING; // Set the state to calculating

        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,                    // gas lane
            i_subscriptionId,           // Id we funded with link in order to make these requests
            REQUEST_CONFIRMATIONS,        // No of block confirmations for your random number to be considered good
            i_callbackGasLimit,           // Make sure that we don't overspend on this call
            NUM_WORDS                    // No of random numbers
        );

        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords( // This function is called by the VRF Coordinator (Chainlink), we need to override it
        uint256 /*requestId*/,
        uint256[] memory randomWords
    ) internal override {
        // Pick a random player
        uint256 randomIndexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[randomIndexOfWinner];

        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN; // Set the state back to open
        s_players = new address payable[](0); // Reset the players array
        s_lastTimeStamp = block.timestamp;

        // Send the winner the money
        emit WinnerPicked(winner); // Emit the event before sending the money, ie, before external interaction/call
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    //* Getters>
    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns(address) {
        return s_players[indexOfPlayer];
    }
}

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions