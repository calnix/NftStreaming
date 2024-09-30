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

        streaming = new NftStreaming(address(nft), address(token), owner, depositor, operator, address(0), 
                                    uint128(allocationPerNft), startTime, endTime);

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
        streaming.claimViaModule(address(mockModule), tokenIds);
    }

    function testUserCannotSetModule() public {

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, userA));

        vm.prank(userA);
        streaming.updateModule(address(mockModule), true);
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

    function testZeroAddressCannotClaimViaModule() public {
        uint256[] memory tokenIds = new uint256[](2);
            tokenIds[0] = 2;
            tokenIds[1] = 3;

        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));

        vm.prank(userC);
        streaming.claimViaModule(address(0), tokenIds);
    }

    function testEmptyArrayCannotClaimViaModule() public {
        uint256[] memory tokenIds = new uint256[](0);

        vm.expectRevert(abi.encodeWithSelector(EmptyArray.selector));

        vm.prank(userC);
        streaming.claimViaModule(address(mockModule), tokenIds);
    }

    function testWrongUserCannotClaimViaModule() public {
        uint256[] memory tokenIds = new uint256[](2);
            tokenIds[0] = 2;
            tokenIds[1] = 3;

        vm.expectRevert("Incorrect Owner");

        vm.prank(userB);
        streaming.claimViaModule(address(mockModule), tokenIds);
    }

    //can call claim; 1 second of emissions claimable
    function testUserACanClaim_T03() public {

        uint256 userATokenBalance_before = token.balanceOf(userA);

        // check events
        vm.expectEmit(true, true, true, true);
        emit ClaimedSingle(userA, 0, 1 ether);

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

//Note: t = 5 | 3 eps streamed in total
abstract contract StateT05 is StateT03 {

    function setUp() public override virtual {
        super.setUp(); 

        // userA claims @ t3
        vm.prank(userA);
        streaming.claimSingle(0);     

        // userC claims @ t3
        vm.prank(userC);
            uint256[] memory tokenIds = new uint256[](2);
            tokenIds[0] = 2;
            tokenIds[1] = 3;
        streaming.claim(tokenIds);   
        
        // record: 1 unit of eps claimed by each nft
        totalClaimed += 3 * streaming.emissionPerSecond();

        //------ userC locks an nft on a module contract
        vm.prank(userC);

            uint256[] memory userCtokenId = new uint256[](1);
            userCtokenId[0] = 3;

        mockModule.lock(userCtokenId);
        // ----------------------------------------------

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

    function testUserCCanClaimMultiple_T05() public {

        uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = 2;

        uint256[] memory amounts = new uint256[](1);
            amounts[0] = 2 * streaming.emissionPerSecond();

        // before
        uint256 userCTokenBalance_before = token.balanceOf(userC);

        // check events
        vm.expectEmit(true, true, true, true);
        emit Claimed(userC, tokenIds, amounts);

        vm.prank(userC);
        streaming.claim(tokenIds);     

        uint256 userCTokenBalance_after = token.balanceOf(userC);
        uint256 epsClaimable = amounts[0];   // 1 nfts

        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), totalAllocation - totalClaimed - epsClaimable);
        assertEq(userCTokenBalance_before + epsClaimable, userCTokenBalance_after);

        // check streaming contract: tokenIds
        for (uint256 i = tokenIds[0]; i < tokenIds.length; ++i) {

            (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(i);

            assertEq(claimed, epsClaimable/tokenIds.length);
            assertEq(lastClaimedTimestamp, block.timestamp);
        }

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }


    function testUserCCanClaimViaModule_T05() public {
        
        // verify userC's nft on module contract
        assertEq(nft.ownerOf(3), address(mockModule));
        assertEq(mockModule.nfts(3), userC);
        assertEq(streaming.modules(address(mockModule)), true);

        uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = 3;

        uint256[] memory amounts = new uint256[](1);
            amounts[0] = 2 * streaming.emissionPerSecond();

        // before
        uint256 userCTokenBalance_before = token.balanceOf(userC);

        // check events
        vm.expectEmit(true, true, true, true);
        emit ClaimedByModule(address(mockModule), userC, tokenIds, amounts);

        vm.prank(userC);
        streaming.claimViaModule(address(mockModule), tokenIds);

        uint256 userCTokenBalance_after = token.balanceOf(userC);
        uint256 epsClaimable = amounts[0];   // 1 nfts

        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), totalAllocation - totalClaimed - epsClaimable);
        assertEq(userCTokenBalance_before + epsClaimable, userCTokenBalance_after);

        // check streaming contract: tokenIds
        for (uint256 i = tokenIds[0]; i < tokenIds.length; ++i) {

            (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(i);

            assertEq(claimed, epsClaimable/tokenIds.length);
            assertEq(lastClaimedTimestamp, block.timestamp);
        }

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }

    function testCannotClaimViaModuleRepeatedly() public {
        
        // verify userC's nft on module contract
        assertEq(nft.ownerOf(3), address(mockModule));
        assertEq(mockModule.nfts(3), userC);
        assertEq(streaming.modules(address(mockModule)), true);

        uint256[] memory tokenIds = new uint256[](2);
            tokenIds[0] = 3;
            tokenIds[1] = 3;

        uint256[] memory amounts = new uint256[](2);
            amounts[0] = 2 * streaming.emissionPerSecond();
            amounts[1] = 0;

        // before
        uint256 userCTokenBalance_before = token.balanceOf(userC);

        // check events
        vm.expectEmit(true, true, true, true);
        emit ClaimedByModule(address(mockModule), userC, tokenIds, amounts);

        vm.prank(userC);
        streaming.claimViaModule(address(mockModule), tokenIds);

        uint256 userCTokenBalance_after = token.balanceOf(userC);
        uint256 epsClaimable = amounts[0];   // 1 nfts

        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), totalAllocation - totalClaimed - epsClaimable);
        assertEq(userCTokenBalance_before + epsClaimable, userCTokenBalance_after);

        // check streaming contract: tokenIds
        for (uint256 i = tokenIds[0]; i < tokenIds.length; ++i) {

            (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(i);

            assertEq(claimed, amounts[0]);
            assertEq(lastClaimedTimestamp, block.timestamp);
        }

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }
}

//Note: t = 12
abstract contract StateStreamEnded is StateT05 {

    function setUp() public override virtual {
        super.setUp(); 
        
        // userA claimed: t3 - t5 -> 2s * eps = 2 units
        vm.prank(userA);
        streaming.claimSingle(0);  

        // userC claimed: t3 - t5 -> 2s * 2eps = 4 units
        vm.startPrank(userC);
            // claim from streaming
            uint256[] memory tokenIds_1 = new uint256[](1);
            tokenIds_1[0] = 2;
            streaming.claim(tokenIds_1);   

            //claim via module
            uint256[] memory tokenIds_2 = new uint256[](1);
            tokenIds_2[0] = 3;
            streaming.claimViaModule(address(mockModule), tokenIds_2);
        vm.stopPrank();

        // record
        totalClaimed += 6 * streaming.emissionPerSecond();
        
        // unlock nft, return to owner
        vm.prank(userC);
        mockModule.unlock(tokenIds_2);

        // time
        vm.warp(12);
    }
} 

// userA prev. claimed: 3s * eps = 3 units
// userC prev. claimed: 3s * 2eps = 6 units
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

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }

    function testUserCCanClaimMultiple_T12() public {
        
        // verify userC has both nfts
        assertEq(nft.ownerOf(2), userC);
        assertEq(nft.ownerOf(3), userC);

        uint256[] memory tokenIds = new uint256[](2);
            tokenIds[0] = 2;
            tokenIds[1] = 3;
        uint256[] memory amounts = new uint256[](2);
            amounts[0] = 7 * streaming.emissionPerSecond();
            amounts[1] = 7 * streaming.emissionPerSecond();

        // before
        uint256 userCTokenBalance_before = token.balanceOf(userC);

        // check events
        vm.expectEmit(true, true, true, true);
        emit Claimed(userC, tokenIds, amounts);

        vm.prank(userC);
        streaming.claim(tokenIds);     

        uint256 userCTokenBalance_after = token.balanceOf(userC);
        uint256 epsClaimable = (7 * streaming.emissionPerSecond()) * 2;   // 2 nfts

        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), totalAllocation - totalClaimed - epsClaimable);
        assertEq(userCTokenBalance_before + epsClaimable, userCTokenBalance_after);

        // check streaming contract: tokenIds
        for (uint256 i = tokenIds[0]; i < tokenIds.length; ++i) {

            (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(i);

            assertEq(claimed, epsClaimable/tokenIds.length);
            assertEq(lastClaimedTimestamp, block.timestamp);
        }

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }

    function testUserBCanClaimViaModule_T12() public {
        // verify userB locked nft
        assertEq(nft.ownerOf(1), address(mockModule));

        uint256 tokenBalance_before = token.balanceOf(userB);

        vm.prank(userB);
            uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = 1;
            streaming.claimViaModule(address(mockModule), tokenIds);

        uint256 tokenBalance_after = token.balanceOf(userB);
        
        // eps
        uint256 epsClaimable = 10 * streaming.emissionPerSecond();
        
        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), (totalAllocation - totalClaimed - epsClaimable));
        assertEq(tokenBalance_before + epsClaimable, tokenBalance_after);

        // check streaming contract
        (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(1);
        assertEq(claimed, token.balanceOf(userB));
        assertEq(lastClaimedTimestamp, block.timestamp);

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));

    }

}

//Note: t = endTime + 2 days: 14 days
abstract contract StateStreamEndedPlusTwoDays is StateStreamEnded {
    function setUp() public override virtual {
        super.setUp(); 

        vm.warp((endTime + 2 days));
    }
}

contract StateStreamEndedPlusTwoDaysTest is StateStreamEndedPlusTwoDays {
    
    function testUserACanClaim_AfterStreamEnded() public {

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
        assertEq(lastClaimedTimestamp, streaming.endTime());

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }

    function testUserCCanClaimMultiple_AfterStreamEnded() public {
        
        // verify userC has both nfts
        assertEq(nft.ownerOf(2), userC);
        assertEq(nft.ownerOf(3), userC);

        uint256[] memory tokenIds = new uint256[](2);
            tokenIds[0] = 2;
            tokenIds[1] = 3;
        uint256[] memory amounts = new uint256[](2);
            amounts[0] = 7 * streaming.emissionPerSecond();
            amounts[1] = 7 * streaming.emissionPerSecond();

        // before
        uint256 userCTokenBalance_before = token.balanceOf(userC);

        // check events
        vm.expectEmit(true, true, true, true);
        emit Claimed(userC, tokenIds, amounts);

        vm.prank(userC);
        streaming.claim(tokenIds);     

        uint256 userCTokenBalance_after = token.balanceOf(userC);
        uint256 epsClaimable = (7 * streaming.emissionPerSecond()) * 2;   // 2 nfts

        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), totalAllocation - totalClaimed - epsClaimable);
        assertEq(userCTokenBalance_before + epsClaimable, userCTokenBalance_after);

        // check streaming contract: tokenIds
        for (uint256 i = tokenIds[0]; i < tokenIds.length; ++i) {

            (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(i);

            assertEq(claimed, epsClaimable/tokenIds.length);
            assertEq(lastClaimedTimestamp, streaming.endTime());
        }

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }

    function testUserBCanClaimViaModule_AfterStreamEnded() public {
        // verify userB locked nft
        assertEq(nft.ownerOf(1), address(mockModule));

        uint256 tokenBalance_before = token.balanceOf(userB);

        vm.prank(userB);
            uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = 1;
            streaming.claimViaModule(address(mockModule), tokenIds);

        uint256 tokenBalance_after = token.balanceOf(userB);
        
        // eps
        uint256 epsClaimable = 10 * streaming.emissionPerSecond();
        
        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), (totalAllocation - totalClaimed - epsClaimable));
        assertEq(tokenBalance_before + epsClaimable, tokenBalance_after);

        // check streaming contract
        (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(1);
        assertEq(claimed, token.balanceOf(userB));
        assertEq(lastClaimedTimestamp, streaming.endTime());

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));

    }

}

//Note: deadline is set -> endTime + 17 days
abstract contract StateBeforeDeadline is StateStreamEndedPlusTwoDays {
    
    function setUp() public override virtual {
        super.setUp(); 

        vm.prank(owner);
        streaming.updateDeadline(endTime + 17 days);
    }
}


contract StateBeforeDeadlineTest is StateBeforeDeadline {

    function testUserACanClaim_AfterStreamEnded() public {

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
        assertEq(lastClaimedTimestamp, streaming.endTime());

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }

    function testUserCCanClaimMultiple_AfterStreamEnded() public {
        
        // verify userC has both nfts
        assertEq(nft.ownerOf(2), userC);
        assertEq(nft.ownerOf(3), userC);

        uint256[] memory tokenIds = new uint256[](2);
            tokenIds[0] = 2;
            tokenIds[1] = 3;
        uint256[] memory amounts = new uint256[](2);
            amounts[0] = 7 * streaming.emissionPerSecond();
            amounts[1] = 7 * streaming.emissionPerSecond();

        // before
        uint256 userCTokenBalance_before = token.balanceOf(userC);

        // check events
        vm.expectEmit(true, true, true, true);
        emit Claimed(userC, tokenIds, amounts);

        vm.prank(userC);
        streaming.claim(tokenIds);     

        uint256 userCTokenBalance_after = token.balanceOf(userC);
        uint256 epsClaimable = (7 * streaming.emissionPerSecond()) * 2;   // 2 nfts

        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), totalAllocation - totalClaimed - epsClaimable);
        assertEq(userCTokenBalance_before + epsClaimable, userCTokenBalance_after);

        // check streaming contract: tokenIds
        for (uint256 i = tokenIds[0]; i < tokenIds.length; ++i) {

            (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(i);

            assertEq(claimed, epsClaimable/tokenIds.length);
            assertEq(lastClaimedTimestamp, streaming.endTime());
        }

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }

    function testUserBCanClaimViaModule_AfterStreamEnded() public {
        // verify userB locked nft
        assertEq(nft.ownerOf(1), address(mockModule));

        uint256 tokenBalance_before = token.balanceOf(userB);

        vm.prank(userB);
            uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = 1;
            streaming.claimViaModule(address(mockModule), tokenIds);

        uint256 tokenBalance_after = token.balanceOf(userB);
        
        // eps
        uint256 epsClaimable = 10 * streaming.emissionPerSecond();
        
        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), (totalAllocation - totalClaimed - epsClaimable));
        assertEq(tokenBalance_before + epsClaimable, tokenBalance_after);

        // check streaming contract
        (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(1);
        assertEq(claimed, token.balanceOf(userB));
        assertEq(lastClaimedTimestamp, streaming.endTime());

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));

    }

}


//Note: warp to after deadline
abstract contract StateAfterDeadline is StateBeforeDeadline {
    
    function setUp() public override virtual {
        super.setUp(); 

        vm.warp((endTime + 18 days));
    }
}

contract StateAfterDeadlineTest is StateAfterDeadline {

    function testCannotClaimViaModulefterDeadline() public {
        
        vm.expectRevert(abi.encodeWithSelector(DeadlineExceeded.selector));

        vm.prank(userB);
            uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = 1;
        streaming.claimViaModule(address(mockModule), tokenIds);
    }

}