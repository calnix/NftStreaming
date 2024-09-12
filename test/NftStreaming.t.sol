// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2, stdStorage, StdStorage } from "forge-std/Test.sol";

import {NftStreaming} from "./../src/NftStreaming.sol";
import "./../src/Errors.sol";
import "./../src/Events.sol";

import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import "./MockNFT.sol";

abstract contract StateDeploy is Test {    
    using stdStorage for StdStorage;

    NftStreaming public streaming;
    ERC20Mock public token;
    MockNFT public nft;

    // entities
    address public userA;
    address public userB;
    address public userC;
    address public owner;
    address public operator;
    address public depositor;

    // stream period
    uint256 public startTime;
    uint256 public endTime;

    // allocation
    uint256 public totalAllocation;
    uint256 public allocationPerNft;

    // record-keeping
    uint256 public totalClaimed;

    function setUp() public virtual {

        // starting point: T0
        vm.warp(0 days); 

        // users
        userA = makeAddr("userA");
        userB = makeAddr("userB");
        userC = makeAddr("userC");
        owner = makeAddr("owner");
        operator = makeAddr("operator");
        depositor = makeAddr("depositor");

        // stream params
        startTime = 2;
        endTime = 12;
        allocationPerNft = 10 ether;
        totalAllocation = 10 ether * 4;

        // contracts
        vm.startPrank(owner);

        token = new ERC20Mock();       
        nft = new MockNFT();

        streaming = new NftStreaming(address(nft), address(token), owner, depositor, address(0), 
                                    allocationPerNft, startTime, endTime);

        vm.stopPrank();

        // mint nfts
        nft.mint(userA, 0);
        nft.mint(userB, 1);
        nft.mint(userC, 2);
        nft.mint(userC, 3);
      
        // mint tokens
        token.mint(depositor, totalAllocation);

        // allowances
        vm.prank(depositor);
        token.approve(address(streaming), totalAllocation);

    }
}

//Note: t = 0
contract StateDeployTest is StateDeploy {

    function testEmissionPerSecond() public {
        
        uint256 period = endTime - startTime; 
        uint256 calculatedEPS = (allocationPerNft / period);

        assertEq(calculatedEPS, streaming.emissionPerSecond());
    }

    function testCanDeposit() public {
        vm.prank(depositor);
        streaming.deposit(totalAllocation);
    }
}

//Note: t = 1
abstract contract StateDeposited is StateDeploy {

    function setUp() public override virtual {
        super.setUp();

        // time
        vm.warp(1);

        vm.prank(depositor);
        streaming.deposit(totalAllocation);
    }
}

contract StateDepositedTest is StateDeposited {

    function testUserACannotClaim() public {

        vm.expectRevert(abi.encodeWithSelector(NotStarted.selector));

        vm.prank(userA);
        streaming.claimSingle(0);     
    }
}


//Note: t = 2
abstract contract StateStreamingStarted is StateDeposited {

    function setUp() public override virtual {
        super.setUp(); 

        // time
        vm.warp(2);
    }
}

contract StateStreamingStartedTest is StateStreamingStarted {

    function testCannotClaimOnStart() public {

        vm.expectRevert(abi.encodeWithSelector(NotStarted.selector));

        vm.prank(userA);
        streaming.claimSingle(0);     
    }

}


//Note: t = 3
abstract contract StateT03 is StateDeposited {

    function setUp() public override virtual {
        super.setUp(); 

        // time
        vm.warp(3);
    }
}

contract StateT03Test is StateT03 {

    //can call claim; 1 second of emissions claimable
    function testUserACanClaim_T03() public {

        // check events
        vm.expectEmit(true, true, false, false);
        emit Claimed(userA, 0);


        uint256 userATokenBalance_before = token.balanceOf(userA);

        vm.prank(userA);
        streaming.claimSingle(0);     

        uint256 userATokenBalance_after = token.balanceOf(userA);
        uint256 epsClaimable = streaming.emissionPerSecond();

        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), totalAllocation - epsClaimable);
        assertEq(userATokenBalance_before + epsClaimable, userATokenBalance_after);

        // check streaming contract: user
        (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(0);
        assertEq(claimed, token.balanceOf(userA));
        assertEq(lastClaimedTimestamp, block.timestamp);

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), epsClaimable);
    }
}

//Note: t = 5 | 3 eps streamed in total
abstract contract StateT05 is StateT03 {

    function setUp() public override virtual {
        super.setUp(); 

        // userA claims @ t3
        vm.prank(userA);
        streaming.claimSingle(0);     
        
        // record
        totalClaimed += streaming.emissionPerSecond();

        // time
        vm.warp(5);
    }
}  

contract StateT05Test is StateT05 {

    //2 seconds of emissions claimable | 1 eps claimed
    function testUserACanClaim_T05() public {

        uint256 userATokenBalance_before = token.balanceOf(userA);

        vm.prank(userA);
        streaming.claimSingle(0);     

        uint256 userATokenBalance_after = token.balanceOf(userA);
        
        // eps
        uint256 epsClaimable = 2 * streaming.emissionPerSecond();
        
        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), (totalAllocation - totalClaimed - epsClaimable));
        assertEq(userATokenBalance_before + epsClaimable, userATokenBalance_after);

        // check streaming contract: user
        (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(0);
        assertEq(claimed, token.balanceOf(userA));  // 6 ether 
        assertEq(lastClaimedTimestamp, block.timestamp);

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));

    }
}


//Note: t = 12
abstract contract StateStreamEnded is StateT05 {

    function setUp() public override virtual {
        super.setUp(); 
        
        // userA claimed: t2 - t5
        vm.prank(userA);
        streaming.claimSingle(0);  
        
        // record
        totalClaimed += 2 * streaming.emissionPerSecond();

        // time
        vm.warp(12);
    }
} 

contract StateStreamEndedTest is StateStreamEnded {

    function testUserACanClaim_T12() public {

        uint256 userATokenBalance_before = token.balanceOf(userA);

        vm.prank(userA);
        streaming.claimSingle(0);     

        uint256 userATokenBalance_after = token.balanceOf(userA);
        
        // eps
        uint256 epsClaimable = 7 * streaming.emissionPerSecond();
        
        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), (totalAllocation - totalClaimed - epsClaimable));
        assertEq(userATokenBalance_before + epsClaimable, userATokenBalance_after);

        // check streaming contract
        (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(0);
        assertEq(claimed, token.balanceOf(userA));
        assertEq(lastClaimedTimestamp, block.timestamp);
        assertEq(streaming.totalClaimed(), allocationPerNft);

    }
}
