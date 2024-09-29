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
        startTime = 2;
        endTime = 12;
        allocationPerNft = 10 ether;
        totalAllocation = 10 ether * 4;

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
// users can call claim; 1 second of emissions claimable
abstract contract StateT03 is StateStreamingStarted {

    function setUp() public override virtual {
        super.setUp(); 

        // time
        vm.warp(3);
    }
}

contract StateT03Test is StateT03 {
   
    function testUserCCanClaimMultiple_T03() public {

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

    function testUsersCannotPauseStream() public {
        uint256[] memory tokenIds = new uint256[](2);
            tokenIds[0] = 1;

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, userB));

        vm.prank(userB);
        streaming.pauseStreams(tokenIds);
    }

    function testOperatorCanPauseStream() public {
        uint256[] memory tokenIds = new uint256[](3);
            tokenIds[0] = 1;    //userB
            tokenIds[1] = 2;    //userC
            tokenIds[2] = 3;    //userC

        // check events
        vm.expectEmit(true, true, true, true);
        emit StreamsPaused(tokenIds);

        vm.prank(operator);
        streaming.pauseStreams(tokenIds);

        // check streaming contract: tokenIds
        for (uint256 i = tokenIds[0]; i < tokenIds.length; ++i) {
            (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(i);

            assertEq(isPaused, true);
        }
    }

    function testOwnerCanPauseStream() public {
        uint256[] memory tokenIds = new uint256[](3);
            tokenIds[0] = 1;    //userB
            tokenIds[1] = 2;    //userC
            tokenIds[2] = 3;    //userC

        // check events
        vm.expectEmit(true, true, true, true);
        emit StreamsPaused(tokenIds);

        vm.prank(owner);
        streaming.pauseStreams(tokenIds);

        // check streaming contract: tokenIds
        for (uint256 i = tokenIds[0]; i < tokenIds.length; ++i) {
            (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(i);

            assertEq(isPaused, true);
        }
    }
}

//Note: t = 5 | 3 eps streamed in total
// pause userB and userC
abstract contract StateT05 is StateT03 {

    function setUp() public override virtual {
        super.setUp(); 

        // userA claims @ t3
        vm.prank(userA);
        streaming.claimSingle(0);     

        // userC claims @ t3
        vm.prank(userC);
        uint256[] memory userCTokenIds = new uint256[](2);
            userCTokenIds[0] = 2;    
            userCTokenIds[1] = 3; 
        streaming.claim(userCTokenIds);   

        // record: 1 unit of eps claimed by each nft
        totalClaimed += 3 * streaming.emissionPerSecond();

        // ------ Pausing Streams: userB and C ------------

        uint256[] memory tokenIds = new uint256[](3);
            tokenIds[0] = 1;    //userB
            tokenIds[1] = 2;    //userC
            tokenIds[2] = 3;    //userC

        vm.prank(owner);
        streaming.pauseStreams(tokenIds);
        
        // ------------------------------------------------

        // time
        vm.warp(5);
    }
}  

contract StateT05Test is StateT05 {

    // 2 seconds of emissions claimable | 1 eps claimed
    // userA unaffected by pausing of other streams
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

    function testUsersCannotClaimPausedStream() public {
        uint256[] memory userBtokenIds = new uint256[](1);
            userBtokenIds[0] = 1;    //userB

        uint256[] memory userCTokenIds = new uint256[](2);
            userCTokenIds[0] = 2;    
            userCTokenIds[1] = 3;    

        vm.expectRevert(abi.encodeWithSelector(StreamPaused.selector));

        vm.prank(userB);
        streaming.claim(userBtokenIds);     

        vm.expectRevert(abi.encodeWithSelector(StreamPaused.selector));

        vm.prank(userC);
        streaming.claim(userCTokenIds);      
    }

    function testOperatorCannotUnpauseStream() public {
        uint256[] memory tokenIds = new uint256[](3);
            tokenIds[0] = 1;    //userB
            tokenIds[1] = 2;    //userC
            tokenIds[2] = 3;    //userC
        
        vm.expectRevert(abi.encodeWithSelector((Ownable.OwnableUnauthorizedAccount.selector), operator));

        vm.prank(operator);
        streaming.unpauseStreams(tokenIds);

    }

    function testOwnerCanUnpauseStream() public {
        uint256[] memory tokenIds = new uint256[](3);
            tokenIds[0] = 1;    //userB
            tokenIds[1] = 2;    //userC
            tokenIds[2] = 3;    //userC

        // check events
        vm.expectEmit(true, true, true, true);
        emit StreamsUnpaused(tokenIds);


        vm.prank(owner);
        streaming.unpauseStreams(tokenIds);

        // check streaming contract: tokenIds
        for (uint256 i = tokenIds[0]; i < tokenIds.length; ++i) {

            (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(i);
            assertEq(isPaused, false);
        }
    }

}


//Note: t = 12
abstract contract StateStreamEnded is StateT05 {

    function setUp() public override virtual {
        super.setUp(); 
        
        // userA claimed: t3 - t5 -> 2s * eps = 2 units
        vm.prank(userA);
        streaming.claimSingle(0);  
        
        // record
        totalClaimed += 2 * streaming.emissionPerSecond();


        // ------ Pausing Streams: userB and C ------------

        uint256[] memory tokenIds = new uint256[](3);
            tokenIds[0] = 1;    //userB
            tokenIds[1] = 2;    //userC
            tokenIds[2] = 3;    //userC

        vm.prank(owner);
        streaming.unpauseStreams(tokenIds);
        
        // ------------------------------------------------

        // time
        vm.warp(12);
    }
} 

// userA prev. claimed: 3s * eps = 3 units
contract StateStreamEndedTest is StateStreamEnded {

    function testUserACanClaim_StreamEnded() public {

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

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }

    // userB has claimed nothing to date
    // userB has 10 units of EPS that is claimable
    function testUserBCanClaim_StreamEnded() public {

        uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = 1;

        uint256[] memory amounts = new uint256[](1);
            amounts[0] = 10 * streaming.emissionPerSecond();
            
        // before
        uint256 userBTokenBalance_before = token.balanceOf(userB);

        // check events
        vm.expectEmit(true, true, true, true);
        emit Claimed(userB, tokenIds, amounts);

        vm.prank(userB);
        streaming.claim(tokenIds);     

        uint256 userBTokenBalance_after = token.balanceOf(userB);
        uint256 epsClaimable = amounts[0];

        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), totalAllocation - totalClaimed - epsClaimable);
        assertEq(userBTokenBalance_before + epsClaimable, userBTokenBalance_after);

        // check streaming contract: tokenIds
        (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams( tokenIds[0] );

        assertEq(claimed, epsClaimable/tokenIds.length);
        assertEq(lastClaimedTimestamp, block.timestamp);
        assertEq(isPaused, false);

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }

    // userC only claimed 1 unit of EPS to date
    // 9 units remaining to be claimed
    function testUserCCanClaimMultiple_StreamEnded() public {

        uint256[] memory tokenIds = new uint256[](2);
            tokenIds[0] = 2;
            tokenIds[1] = 3;
        uint256[] memory amounts = new uint256[](2);
            amounts[0] = 9 * streaming.emissionPerSecond();
            amounts[1] = 9 * streaming.emissionPerSecond();

        // before
        uint256 userCTokenBalance_before = token.balanceOf(userC);

        // check events
        vm.expectEmit(true, true, true, true);
        emit Claimed(userC, tokenIds, amounts);

        vm.prank(userC);
        streaming.claim(tokenIds);     

        uint256 userCTokenBalance_after = token.balanceOf(userC);
        uint256 epsClaimable = amounts[0] + amounts[1];   

        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), totalAllocation - totalClaimed - epsClaimable);
        assertEq(userCTokenBalance_before + epsClaimable, userCTokenBalance_after);

        // check streaming contract: tokenIds
        for (uint256 i = tokenIds[0]; i < tokenIds.length; ++i) {

            (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(i);

            assertEq(claimed, epsClaimable/tokenIds.length);
            assertEq(lastClaimedTimestamp, block.timestamp);
            assertEq(isPaused, false);

        }

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }

}
