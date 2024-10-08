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

    function testInvalidStartTime() public {

        // stream params
        startTime = block.timestamp;
        endTime = 12;
        allocationPerNft = 10 ether;
        totalAllocation = 10 ether * 4;

        // contracts
        vm.startPrank(owner);

        token = new ERC20Mock();       
        nft = new MockNFT();

        vm.expectRevert(abi.encodeWithSelector(InvalidStartime.selector));

        streaming = new NftStreaming(address(nft), address(token), owner, depositor, operator, address(0), 
                                    uint128(allocationPerNft), startTime, endTime);

    }

    function testInvalidEndtime() public {
        // stream params
        startTime = 2;
        endTime = 1;
        allocationPerNft = 10 ether;
        totalAllocation = 10 ether * 4;

        // contracts
        vm.startPrank(owner);

        token = new ERC20Mock();       
        nft = new MockNFT();

        vm.expectRevert(abi.encodeWithSelector(InvalidEndTime.selector));

        streaming = new NftStreaming(address(nft), address(token), owner, depositor, operator, address(0), 
                                    uint128(allocationPerNft), startTime, endTime);
    }

    function testInvalidAllocation() public {
        // stream params
        startTime = 2;
        endTime = 12;
        allocationPerNft = 0 ether;
        totalAllocation = 10 ether * 4;

        // contracts
        vm.startPrank(owner);

        token = new ERC20Mock();       
        nft = new MockNFT();

        vm.expectRevert(abi.encodeWithSelector(InvalidAllocation.selector));

        streaming = new NftStreaming(address(nft), address(token), owner, depositor, operator, address(0), 
                                    uint128(allocationPerNft), startTime, endTime);
    }

    function testInvalidEmission() public {
        // stream params
        startTime = 1;
        endTime = 12000 ether;
        allocationPerNft = 10 ether;
        totalAllocation = 10 ether * 4;

        // contracts
        vm.startPrank(owner);

        token = new ERC20Mock();       
        nft = new MockNFT();

        vm.expectRevert(abi.encodeWithSelector(InvalidEmission.selector));

        streaming = new NftStreaming(address(nft), address(token), owner, depositor, operator, address(0), 
                                    uint128(allocationPerNft), startTime, endTime);
    }

    function testConstructorParameters() public {
        // Check NFT address
        assertEq(address(streaming.NFT()), address(nft));
        
        // Check TOKEN address
        assertEq(address(streaming.TOKEN()), address(token));
        
        // Check owner
        assertEq(streaming.owner(), owner);
        
        // Check depositor
        assertEq(streaming.depositor(), depositor);
        
        // Check operator
        assertEq(streaming.operator(), operator);
        
        // Check DELEGATE_REGISTRY
        assertEq(address(streaming.DELEGATE_REGISTRY()), address(0));
        
        // Check allocationPerNft
        assertEq(streaming.allocationPerNft(), allocationPerNft);
        
        // Check startTime
        assertEq(streaming.startTime(), startTime);
        
        // Check endTime
        assertEq(streaming.endTime(), endTime);
        
        // Check totalAllocation
        assertEq(streaming.totalAllocation(), allocationPerNft * streaming.totalSupply());
        
        // Check emissionPerSecond
        uint256 expectedEmissionPerSecond = allocationPerNft / (endTime - startTime);
        assertEq(streaming.emissionPerSecond(), expectedEmissionPerSecond);
    }

    function testUsersCannotDeposit() public {
        
        vm.expectRevert(abi.encodeWithSelector(OnlyDepositor.selector));

        vm.prank(userA);
        streaming.deposit(totalAllocation);
    }

    function testUserCannotUpdateDepositor() public {

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, userA));

        vm.prank(userA);
        streaming.updateDepositor(userA);
    }

    function testOwnerCanUpdateDepositor() public {

        vm.expectEmit(true, true, true, true);
        emit DepositorUpdated(depositor, userA);

        vm.prank(owner);
        streaming.updateDepositor(userA);   

        assertEq(streaming.depositor(), userA);
    }

    function testDepositorCannotDepositExcessAllocation() public {
        
        assertEq(streaming.totalDeposited(), 0);

        uint256 totalAllocation = streaming.totalAllocation();

        vm.expectRevert(abi.encodeWithSelector(ExcessDeposit.selector));

        vm.prank(depositor);
        streaming.deposit(totalAllocation + 1);
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

        vm.expectRevert(abi.encodeWithSelector(NotStarted.selector));

        vm.prank(userA);
        streaming.claimSingle(0);     
    }

    function testUserCannotUpdateOperator() public {

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, userA));

        vm.prank(userA);
        streaming.updateOperator(userA);
    }

    function testOwnerCanUpdateOperator() public {

        vm.expectEmit(true, true, true, true);
        emit OperatorUpdated(operator, userA);

        vm.prank(owner);
        streaming.updateOperator(userA);
        
        assertEq(streaming.operator(), userA);
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

    function testCannnotClaimMultipleOnStart() public {

        uint256[] memory tokenIds = new uint256[](2);
            tokenIds[0] = 2;
            tokenIds[1] = 3;
        
        vm.expectRevert(abi.encodeWithSelector(NotStarted.selector));

        vm.prank(userC);
        streaming.claim(tokenIds);     
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
    using stdStorage for StdStorage;

    function testWrongUserCannotClaimSingle() public {

        vm.expectRevert(abi.encodeWithSelector(InvalidOwner.selector));

        vm.prank(userB);
        streaming.claimSingle(0);   
    }

    function testWrongUserCannotClaimMultiple() public {
        uint256[] memory tokenIds = new uint256[](2);
            tokenIds[0] = 2;
            tokenIds[1] = 3;

        vm.expectRevert(abi.encodeWithSelector(InvalidOwner.selector));

        vm.prank(userB);
        streaming.claim(tokenIds);     
    }

    function testCannotClaimInExcessOfAllocation() public {
        
        // modify streams(0).claim
        stdstore
            .target(address(streaming))
            .sig("streams(uint256)")
            .with_key(uint256(0))
            .depth(0)
            .checked_write(uint256(100 ether)); 

        vm.expectRevert(abi.encodeWithSelector(IncorrectClaimable.selector));

        vm.prank(userA);
        streaming.claimSingle(0);   
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

    function testCannotClaimMultiple_EmptyArray_T03() public {

        uint256[] memory tokenIds;

        vm.expectRevert(abi.encodeWithSelector(EmptyArray.selector));

        vm.prank(userC);
        streaming.claim(tokenIds);     
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
        for (uint256 i = 0; i < tokenIds.length; ++i) {

            (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(tokenIds[i]);

            assertEq(claimed, token.balanceOf(userC)/2);
            assertEq(lastClaimedTimestamp, block.timestamp);
        }

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), epsClaimable);
    }

    function testCannotClaimMultipleRepeatedly() public {

        uint256[] memory tokenIds = new uint256[](3);
            tokenIds[0] = 2;
            tokenIds[1] = 3;
            tokenIds[2] = 2;    //note: repeated

        uint256[] memory amounts = new uint256[](3);
            amounts[0] = streaming.emissionPerSecond();
            amounts[1] = streaming.emissionPerSecond();
            amounts[2] = 0;

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
        for (uint256 i = 0; i < tokenIds.length; ++i) {

            (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(tokenIds[i]);

            assertEq(claimed, streaming.emissionPerSecond());
            assertEq(lastClaimedTimestamp, block.timestamp);
        }

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), epsClaimable); 

    }

    function testClaimableViewFunctionUserB_T03() public {
        
        uint256 claimable = streaming.claimable(1);

        assertEq(claimable, streaming.emissionPerSecond());
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

        uint256[] memory tokenIds = new uint256[](2);
            tokenIds[0] = 2;
            tokenIds[1] = 3;
        uint256[] memory amounts = new uint256[](2);
            amounts[0] = 2 * streaming.emissionPerSecond();
            amounts[1] = 2 * streaming.emissionPerSecond();

        // before
        uint256 userCTokenBalance_before = token.balanceOf(userC);

        // check events
        vm.expectEmit(true, true, true, true);
        emit Claimed(userC, tokenIds, amounts);

        vm.prank(userC);
        streaming.claim(tokenIds);     

        uint256 userCTokenBalance_after = token.balanceOf(userC);
        uint256 epsClaimable = (2 * streaming.emissionPerSecond()) * 2;   // 2 nfts

        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), totalAllocation - totalClaimed - epsClaimable);
        assertEq(userCTokenBalance_before + epsClaimable, userCTokenBalance_after);

        // check streaming contract: tokenIds
        for (uint256 i = 0; i < tokenIds.length; ++i) {

            (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(tokenIds[i]);

            assertEq(claimed, token.balanceOf(userC)/2);
            assertEq(lastClaimedTimestamp, block.timestamp);
        }

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }

    //2 seconds of emissions claimable | 1 eps claimed
    function testClaimableUserA_T05() public {

        uint256 claimable = streaming.claimable(0);

        assertEq(claimable, 2*streaming.emissionPerSecond());
    }


    //3 seconds of emissions claimable
    function testClaimableUserB_T05() public {
        
        uint256 claimable = streaming.claimable(1);

        assertEq(claimable, 3*streaming.emissionPerSecond());
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
        vm.prank(userC);
            uint256[] memory tokenIds = new uint256[](2);
            tokenIds[0] = 2;
            tokenIds[1] = 3;
        streaming.claim(tokenIds);   
        
        // record
        totalClaimed += 6 * streaming.emissionPerSecond();

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
        for (uint256 i = 0; i < tokenIds.length; ++i) {

            (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(tokenIds[i]);

            assertEq(claimed, token.balanceOf(userC)/2);
            assertEq(lastClaimedTimestamp, block.timestamp);
        }

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }

    // userA prev. claimed: 3eps | 7 eps claimable
    function testClaimableUserA_T05() public {

        uint256 claimable = streaming.claimable(0);

        assertEq(claimable, 7*streaming.emissionPerSecond());
    }


    // 10 eps claimable
    function testClaimableUserB_T05() public {
        
        uint256 claimable = streaming.claimable(1);

        assertEq(claimable, 10*streaming.emissionPerSecond());
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
        for (uint256 i = 0; i < tokenIds.length; ++i) {

            (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(tokenIds[i]);

            assertEq(claimed, token.balanceOf(userC)/2);
            assertEq(lastClaimedTimestamp, streaming.endTime());
        }

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }

    function testOnlyDepositorCanWithdraw() public {

        vm.expectRevert(abi.encodeWithSelector(OnlyDepositor.selector));
       
        vm.prank(userA);
        streaming.withdraw();   
    }

    function testCannotWithdrawIfDeadlineNotDefined() public {

        vm.expectRevert(abi.encodeWithSelector(WithdrawDisabled.selector));
       
        vm.prank(depositor);
        streaming.withdraw();   
    }

    function testUserCannotUpdateDeadline() public {
        uint256 newDeadline = endTime + 20 days;

        vm.expectRevert(abi.encodeWithSelector((Ownable.OwnableUnauthorizedAccount.selector), userA));

        vm.prank(userA);
        streaming.updateDeadline(newDeadline);

        // Verify deadline hasn't changed
        assertEq(streaming.deadline(), 0);
    }

    function testCannotUpdateDeadlineUnderEndTimeBuffer() public {
        
        uint256 newDeadline = (endTime + 13 days);

        vm.expectRevert(abi.encodeWithSelector(InvalidNewDeadline.selector));

        vm.prank(owner);
        streaming.updateDeadline(newDeadline);
    }

    function testCannotUpdateDeadlineUnderCurrentTimestampBuffer() public {
          
        vm.expectRevert(abi.encodeWithSelector(InvalidNewDeadline.selector));

        vm.prank(owner);
        streaming.updateDeadline(block.timestamp + 13 days);
    }

    function testOwnerCanUpdateDeadline() public {

        // verify before
        assertEq(streaming.endTime(), endTime);

        uint256 newDeadline = (endTime + 17 days);

        // check events
        vm.expectEmit(true, true, true, true);
        emit DeadlineUpdated(newDeadline);

        vm.prank(owner);
        streaming.updateDeadline(newDeadline);

        // verify after
        assertEq(streaming.deadline(), newDeadline);
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
        for (uint256 i = 0; i < tokenIds.length; ++i) {

            (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(tokenIds[i]);

            assertEq(claimed, token.balanceOf(userC)/2);
            assertEq(lastClaimedTimestamp, streaming.endTime());
        }

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

    function testCannotClaimSingleAfterDeadline() public {
        vm.expectRevert(abi.encodeWithSelector(DeadlineExceeded.selector));

        vm.prank(userA);
        streaming.claimSingle(0);
    }

    function testCannotClaimAfterDeadline() public {
        vm.expectRevert(abi.encodeWithSelector(DeadlineExceeded.selector));

        uint256[] memory tokenIds = new uint256[](2);
            tokenIds[0] = 2;
            tokenIds[1] = 3;

        vm.prank(userC);
        streaming.claim(tokenIds);  
    }

    function testCannotWithdrawEarly() public {

        vm.warp(streaming.deadline() - 1 days);

        vm.expectRevert(abi.encodeWithSelector(PrematureWithdrawal.selector));
       
        vm.prank(depositor);
        streaming.withdraw();   
    }

    function testUserCannotPause() public {
        
        vm.expectRevert(abi.encodeWithSelector((Ownable.OwnableUnauthorizedAccount.selector), userA));

        vm.prank(userA);
        streaming.pause();
    }

    function testWithdraw() public {

        uint256 remaining = totalAllocation - totalClaimed;

        // pre-checks
        assertEq(token.balanceOf(depositor), 0);
        assertEq(token.balanceOf(address(streaming)), remaining);

        // check events
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(depositor,  remaining);

        vm.prank(depositor);
        streaming.withdraw();

        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), 0);
        assertEq(token.balanceOf(depositor), remaining);

    }

    function testOperatorCanPause() public {

        assertEq(streaming.paused(), false);

        vm.prank(operator);
        streaming.pause();

        assertEq(streaming.paused(), true);
    }

    function testOwnerCanPause() public {

        assertEq(streaming.paused(), false);

        vm.prank(owner);
        streaming.pause();

        assertEq(streaming.paused(), true);
    }

}


abstract contract StatePaused is StateAfterDeadline {

    function setUp() public override virtual {
        super.setUp();

        vm.prank(owner);
        streaming.pause();
    }    
}

contract StatePausedTest is StatePaused {

    function testCannotClaimSingleWhenPaused() public {
        
        vm.warp(streaming.endTime() - 1);
        
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));

        vm.prank(userA);
        streaming.claimSingle(0);         
    }

    function testCannotClaimWhenPaused() public {
        
        vm.warp(streaming.endTime() - 1);
        
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));

        uint256[] memory tokenIds = new uint256[](2);
            tokenIds[0] = 2;
            tokenIds[1] = 3;

        vm.prank(userC);
        streaming.claim(tokenIds);      
    }

    function testUserCannotUnpause() public {

        vm.expectRevert(abi.encodeWithSelector((Ownable.OwnableUnauthorizedAccount.selector), userA));

        vm.prank(userA);
        streaming.unpause();
    }

    function testOperatorCannotUnpause() public {
                
        vm.expectRevert(abi.encodeWithSelector((Ownable.OwnableUnauthorizedAccount.selector), operator));

        vm.prank(operator);
        streaming.unpause();
    }

    function testCannotEmergencyExitIfNotFrozen() public {

        vm.expectRevert(abi.encodeWithSelector(NotFrozen.selector));
     
        vm.prank(owner);
        streaming.emergencyExit(owner);
    }

    function testOwnerCanUnpauseIfNotFrozen() public {
        vm.prank(owner);
        streaming.unpause();

        assertEq(streaming.paused(), false);        
    }

    function testOwnerCanFreezeContract() public {

        assertEq(streaming.isFrozen(), 0);

        // check events
        vm.expectEmit(true, true, true, true);
        emit Frozen(block.timestamp);

        vm.prank(owner);
        streaming.freeze();

        assertEq(streaming.isFrozen(), 1);
    }
}

abstract contract StateFrozen is StatePaused {

    function setUp() public override virtual {
        super.setUp();
        
        vm.prank(owner);
        streaming.freeze();
    }    
}

contract StateFrozenTest is StateFrozen {

    function testCannotFreezeTwice() public {

        vm.expectRevert(abi.encodeWithSelector(IsFrozen.selector));

        vm.prank(owner);
        streaming.freeze();
    }

    function testCannotUnpauseIfFrozen() public {

        vm.expectRevert(abi.encodeWithSelector(IsFrozen.selector));

        vm.prank(owner);
        streaming.unpause();
    }

    function testEmergencyExit() public {
        
        uint256 balance = token.balanceOf(address(streaming));

        // check events
        vm.expectEmit(true, false, false, false);
        emit EmergencyExit(owner, balance);

        vm.prank(owner);
        streaming.emergencyExit(owner);

        assertEq(token.balanceOf(owner), balance);
    }
}
