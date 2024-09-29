// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2, stdStorage, StdStorage } from "forge-std/Test.sol";

import {NftStreaming} from "./../src/NftStreaming.sol";
import "./../src/Errors.sol";
import "./../src/Events.sol";

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
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
        // start: Oct 11 2024 17:00:00 HKT -> 1728637200
        startTime = 1728637200;
        // end: Oct 11 2025, 17:00:00 HKT -> 1760173200 
        endTime = 1760173200;
        allocationPerNft = 47_554.52 ether;
        totalAllocation = allocationPerNft * 4;

        // contracts
        vm.startPrank(owner);

        token = new ERC20Mock();       
        nft = new MockNFT();

        streaming = new NftStreaming(address(nft), address(token), owner, depositor, operator, address(0), 
                                    uint128(allocationPerNft), startTime, endTime);

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

    function testUsersCannotDeposit() public {
        
        vm.expectRevert(abi.encodeWithSelector(OnlyDepositor.selector));

        vm.prank(userA);
        streaming.deposit(totalAllocation);
    }

    function testDepositorCanDeposit() public {

        assertEq(streaming.totalDeposited(), 0);

        vm.expectEmit(true, true, true, true);
        emit Deposited(depositor, totalAllocation);

        vm.prank(depositor);
        streaming.deposit(totalAllocation);

        assertEq(streaming.totalDeposited(), totalAllocation);
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
        uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = 0;

        vm.expectRevert(abi.encodeWithSelector(NotStarted.selector));

        vm.prank(userA);
        streaming.claimSingle(0);     
    }

}

//Note: t = 2
// module enabled
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

//Note: t = startTime + 1
// users can call claim; 1 second of emissions claimable
abstract contract StateStartTimePlusOne is StateStreamingStarted {

    function setUp() public override virtual {
        super.setUp(); 

        // time
        vm.warp( streaming.startTime() + 1);
    }
}

contract StateStartTimePlusOneTest is StateStartTimePlusOne {

    //can call claim; 1 second of emissions claimable
    function testUserACanClaim() public {

        uint256 userATokenBalance_before = token.balanceOf(userA);

        // check events
        vm.expectEmit(true, true, true, true);
        emit ClaimedSingle(userA, 0, streaming.emissionPerSecond());

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

    function testUserCCanClaimMultiple() public {

        uint256[] memory tokenIds = new uint256[](2);
            tokenIds[0] = 2;
            tokenIds[1] = 3;
        uint256[] memory amounts = new uint256[](2);
            amounts[0] = streaming.emissionPerSecond();
            amounts[1] = streaming.emissionPerSecond();

        // before
        uint256 userCTokenBalance_before = token.balanceOf(userC);

        // check events
        vm.expectEmit(true, true, true, true);
        emit Claimed(userC, tokenIds, amounts);

        vm.prank(userC);
        streaming.claim(tokenIds);     

        uint256 userCTokenBalance_after = token.balanceOf(userC);
        uint256 epsClaimable = 2 * streaming.emissionPerSecond();   // 2 nfts

        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), totalAllocation - epsClaimable);
        assertEq(userCTokenBalance_before + epsClaimable, userCTokenBalance_after);

        // check streaming contract: tokenIds
        for (uint256 i = tokenIds[0]; i < tokenIds.length; ++i) {

            (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(i);

            assertEq(claimed, epsClaimable/tokenIds.length);
            assertEq(lastClaimedTimestamp, block.timestamp);
        }

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), epsClaimable);
    }

}


abstract contract StateStreamEnded is StateStartTimePlusOne {

    function setUp() public override virtual {
        super.setUp(); 

        vm.warp(streaming.endTime());
    }
}

contract StateStreamEndedTest is StateStreamEnded {

    function testUserACanClaim_AfterStreamEnded() public {

        uint256 userATokenBalance_before = token.balanceOf(userA);

        vm.prank(userA);
        streaming.claimSingle(0);     

        uint256 userATokenBalance_after = token.balanceOf(userA);
        
        // eps
        uint256 epsClaimable = allocationPerNft;
        
        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), (totalAllocation - totalClaimed - epsClaimable));
        assertEq(userATokenBalance_before + epsClaimable, userATokenBalance_after);

        // check streaming contract
        (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(0);
        assertEq(claimed, token.balanceOf(userA));
        assertEq(lastClaimedTimestamp, streaming.endTime());

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }
}