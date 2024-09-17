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
import "./MockModuleContract.sol";

abstract contract StateDeploy is Test {    
    using stdStorage for StdStorage;

    NftStreaming public streaming;
    ERC20Mock public token;
    MockNFT public nft;

    MockModuleContract public mockModule;

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

        mockModule = new MockModuleContract(address(nft));

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

        vm.prank(userB);
        nft.setApprovalForAll(address(mockModule), true);

        vm.prank(userC);
        nft.setApprovalForAll(address(mockModule), true);

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

    function testOwnerCanSetModule() public {

        assertEq(streaming.modules(address(mockModule)), false);

        // check events
        vm.expectEmit(true, true, true, true);
        emit ModuleUpdated(address(mockModule), true);

        vm.prank(owner);
        streaming.updateModule(address(mockModule), true);

        assertEq(streaming.modules(address(mockModule)), true);
    }
}

//Note: t = 2
// module enabled
abstract contract StateStreamingStarted is StateDeposited {

    function setUp() public override virtual {
        super.setUp(); 

        // ----- moduble enabled
        vm.prank(owner);
        streaming.updateModule(address(mockModule), true);
        assertEq(streaming.modules(address(mockModule)), true);
        //  --------------------------------------------------

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

        //---- userB locks nft on module contract
        vm.prank(userB);
            uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = 1;
        mockModule.lock(tokenIds);

        // time
        vm.warp(3);
    }
}


contract StateT03Test is StateT03 {

    //can call claim; 1 second of emissions claimable
    function testUserACanClaim_T03() public {

        uint256 userATokenBalance_before = token.balanceOf(userA);

        // check events
        vm.expectEmit(true, true, true, true);
        emit Claimed(userA, 1 ether);

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

}