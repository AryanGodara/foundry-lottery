// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {Vm} from "forge-std/Vm.sol";

contract RaffleTest is Test{
    // Events
    event EnteredRaffle(address indexed player);

    //? ////////////////
    //? State Variables
    //? ////////////////
    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    //? ////////////////
    //? Test Functions
    //? ////////////////

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();

        ( entranceFee,
          interval,
          vrfCoordinator,
          gasLane,
          subscriptionId,
          callbackGasLimit,) = helperConfig.activeNetworkConfig();
        
        vm.deal(PLAYER, STARTING_USER_BALANCE); // Give the player some money
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }
    
    //* ////////////////////////
    //*  Test enterRaffle()  ////
    //* ////////////////////////
    function testRaffleRevertsWhenYouDontPayEnough() public {
        // Arrange
        vm.prank(PLAYER);
        // Act/Assert
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEmitsEventOnAddress() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        
        vm.warp(block.timestamp + interval + 1); // Warp to the end of the raffle (vm.warp() sets the block.timestamp)
        vm.roll(block.number + 1); // Roll the block number forward
        
        raffle.performUpkeep(""); // Perform the upkeep

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    //* ////////////////////////
    //*  Test checkUpkeep()  ///
    //* ////////////////////////
    function testCheckUpKeepReturnsFalseIfItHasNoBalance() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upKeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upKeepNeeded);
    }

    function testCheckUpKeepReturnsFalseIfRaffleNotOpen() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep(""); // Sets RaffleState enum to the "Calculating" state

        // Act
        (bool upKeepNeeded, ) = raffle.checkUpkeep(""); // Should return false now

        // Assert
        assert(!upKeepNeeded);
    }

    function testCheckUpKeepReturnsFalseIfEnoughTimeHasntPassed() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval - 1); // Warp to the end of the raffle (vm.warp() sets the block.timestamp)
        vm.roll(block.number + 1); // Roll the block number forward

        // Act
        (bool upKeepNeeded, ) = raffle.checkUpkeep(""); // Should return false now

        // Assert
        assert(!upKeepNeeded);
    }

    function testCheckUpKeepReturnsTrueIfEnoughTimeHasPassed() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // Warp to the end of the raffle (vm.warp() sets the block.timestamp)
        vm.roll(block.number + 1); // Roll the block number forward

        // Act
        (bool upKeepNeeded, ) = raffle.checkUpkeep(""); // Should return false now

        // Assert
        assert(upKeepNeeded);
    }

    //* ////////////////////////
    //*  Test peformUpkeep()  //
    //* ////////////////////////

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // Warp to the end of the raffle (vm.warp() sets the block.timestamp)
        vm.roll(block.number + 1); // Roll the block number forward, (vm.roll() sets the block.number)

        // Act/Assert
        raffle.performUpkeep(""); // Should work
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 raffleState= 0;

        // Act/Assert
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, raffleState)
        );
        raffle.performUpkeep(""); // Should work
    }

    modifier raffleEnteredAndTimePassed {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // Warp to the end of the raffle (vm.warp() sets the block.timestamp)
        vm.roll(block.number + 1); // Roll the block number forward, (vm.roll() sets the block.number)
        _;
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() 
        public
        raffleEnteredAndTimePassed
    {
        // Arrange
        //* Done inside the modifier
        
        // Act
        vm.recordLogs(); // Automatically saves all the emitted logs inside a data structure
        raffle.performUpkeep("");   // Emits the requestId
        
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        // all log entries are stored in bytes32 (older string lol) type format
        // entries[0] is the event emitted by VRFCoordiantorV2Mock, so our custom event is the second one
        // The first topic is generic (kind of like the first command line argument), so we get ours in the second number in the array
        // The requestId is the second topic in our event, so we get it from the second number in the array
        
        Raffle.RaffleState rState = raffle.getRaffleState();
        // Assert
        assert(rState == Raffle.RaffleState.CALCULATING);
        assert(uint256(rState) == 1);
        assert(uint256(requestId)>0); // Make sure the requestId was actually generated
    }

    //* //////////////////////////////
    //*  Test fulfillRandomWords()  ///
    //* //////////////////////////////

    function testFulFillRandomWordsCanOnnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId) //* Fuzz Test
        public
        raffleEnteredAndTimePassed
    {
        // Arrange
        //* Done inside the modifier
        
        // Act/Assert
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle) );
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() 
        public
        raffleEnteredAndTimePassed 
    {
        // Arrange
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1;
        // Since we already have a modifier, time has passed, and we already have one entrant, 
        // so we're starting from position 1 in array (0 is the owner)
        
        for ( uint256 i = startingIndex ; i < startingIndex+additionalEntrants ; i++ ) {
            address player = address(uint160(i)); // Same as address(1/2/3)
            hoax(player, 10 ether); // Sets up a prank from an address that has some ether
            raffle.enterRaffle{value: entranceFee}();
        }
        
        uint256 prize = entranceFee * (additionalEntrants + 1 );

        // Pretend to be chainlink vrf to get random number & pick winner
        vm.recordLogs();
        raffle.performUpkeep(""); // emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        uint256 previousTimeStamp = raffle.getLastTimeStamp();

        // pretend to be chainlink vrf to get random number & pick winner
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle) 
        );

        // Assert
        // assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
        // assert(raffle.getRecentWinner() != address(0));
        // assert(raffle.getLengthOfPlayers() == 0);
        // assert(raffle.getLastTimeStamp() > previousTimeStamp);
        console.log(raffle.getRecentWinner().balance);
        console.log(STARTING_USER_BALANCE + prize - entranceFee);
        assert(raffle.getRecentWinner().balance == STARTING_USER_BALANCE + prize - entranceFee);
    }
}
