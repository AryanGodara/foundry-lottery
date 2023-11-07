// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract RaffleTest is Test{
    // Events
    event EnteredRaffle(address indexed player);

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
}
 