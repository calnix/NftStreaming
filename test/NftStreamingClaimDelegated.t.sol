// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2, stdStorage, StdStorage } from "forge-std/Test.sol";

import {NftStreaming} from "./../src/NftStreaming.sol";
import "./../src/Errors.sol";
import "./../src/Events.sol";

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {IDelegateRegistry} from "./../src/IDelegateRegistry.sol";
import {IERC721} from "./../lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol";

abstract contract ForkMainnet is Test {
    
    // chain to fork
    uint256 public mainnetFork;   
    string public MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    // contracts to fork
    IDelegateRegistry public delegateV2;
    IERC721 public mocaNft;

    // create fork
    function setUp() public virtual {

        // fork
        mainnetFork = vm.createSelectFork(MAINNET_RPC_URL);

        // https://docs.delegate.xyz/technical-documentation/delegate-registry/contract-addresses
        delegateV2 = IDelegateRegistry(0x00000000000000447e69651d841bD8D104Bed493);

        // https://etherscan.io/address/0x59325733eb952a92e069c87f0a6168b29e80627f
        mocaNft = IERC721(0x59325733eb952a92e069C87F0A6168b29E80627f);
    }
}

//Note: Forking sanity checks
contract ForkMainnetTest is ForkMainnet {
    
    function testForkSelected() public {
        
        // confirm fork selected
        assertEq(vm.activeFork(), mainnetFork);
    }

    function testContractForked() public {
   
        /**
            ref txn: https://etherscan.io/address/0x00000000000000447e69651d841bD8D104Bed493#readContract

            In the above txn, msg.sender calls `delegateAll` on delegateV2, passing the following inputs:
            - to: 	0x7C1d54cdF93998dD55900e4e2FAFC555DFe2cB3a
            - rights: 0x0000000000000000000000000000000000000000000000000000000000000000
            - enable: true

            We verify our fork, by calling the view fn `getOutgoingDelegations` on both etherscan and here
            - the outputs should match
            - output is an array of struct Delegation
            - array has only 1 member
        */
        
        // txn executed as per block 20773809
        vm.rollFork(20_773_809);  
        assertEq(block.number, 20_773_809);

        //Note: we lock-in the block.number to ensure that future txns do not alter our asserts below

        IDelegateRegistry.Delegation[] memory delegations = delegateV2.getOutgoingDelegations(0xf280f36f0e8FE65eaA6d24B4D4204Ec73e9C1A29);

        assertEq(uint8(delegations[0].type_), 1);  // enum DelegationType

        assertEq(delegations[0].to, 0x7C1d54cdF93998dD55900e4e2FAFC555DFe2cB3a);
        assertEq(delegations[0].from, 0xf280f36f0e8FE65eaA6d24B4D4204Ec73e9C1A29);
        assertEq(delegations[0].rights, bytes32(0));
        
        assertEq(delegations[0].contract_, address(0));
        
        assertEq(delegations[0].tokenId, 0);
        assertEq(delegations[0].amount, 0);
    }

    function testMocaForked() public {
        // ref txn: https://etherscan.io/tx/0x739f705d933d2571d9155369983bc32d9205941f4c018806897f28d5ae75e3ce

        // txn executed as per block 20771533
        vm.rollFork(20771533);  
        assertEq(block.number, 20771533);

        address owner = mocaNft.ownerOf(7336);
        
        // check new owner
        assertEq(owner, 0x839c159bABA1bfD3f9585A93f5C4677EE8e59a8c);
    }
}

abstract contract SimulateUsersAndDelegations is ForkMainnet {
    using stdStorage for StdStorage;

    // users: cold wallets
    address public userA_cw;
    address public userB_cw;
    address public userC_cw;
    
    // users: hot wallets
    address public userA;
    address public userB;
    address public userC;

    function setUp() public virtual override{
        super.setUp();

        // users: hot wallets
        userA_cw = makeAddr("userA_cw");
        userB_cw = makeAddr("userB_cw");
        userC_cw = makeAddr("userC_cw");

        // users: hot wallets
        userA = makeAddr("userA");
        userB = makeAddr("userB");
        userC = makeAddr("userC");

        // transfers nfts     
        vm.startPrank(mocaNft.ownerOf(0));    
        mocaNft.safeTransferFrom(mocaNft.ownerOf(0), userA_cw, 0);
        vm.stopPrank();

        vm.startPrank(mocaNft.ownerOf(1));    
        mocaNft.transferFrom(mocaNft.ownerOf(1), userB_cw, 1);
        vm.stopPrank();

        vm.startPrank(mocaNft.ownerOf(2));    
        mocaNft.transferFrom(mocaNft.ownerOf(2), userC_cw, 2);
        vm.stopPrank();

        vm.startPrank(mocaNft.ownerOf(3));    
        mocaNft.transferFrom(mocaNft.ownerOf(3), userC_cw, 3);
        vm.stopPrank();

        // delegate cold wallet to hot wallet
        vm.prank(userA_cw);    
        //delegateV2.delegateAll(userA, bytes32(0), true);
        delegateV2.delegateERC721(userA, address(mocaNft), 0, bytes32(0), true);
        
        vm.prank(userB_cw);    
        //delegateV2.delegateAll(userB, bytes32(0), true);
        delegateV2.delegateERC721(userB, address(mocaNft), 1, bytes32(0), true);

        vm.startPrank(userC_cw);    
        //delegateV2.delegateAll(userC, bytes32(0), true);
        delegateV2.delegateERC721(userC, address(mocaNft), 2, bytes32(0), true);
        delegateV2.delegateERC721(userC, address(mocaNft), 3, bytes32(0), true);
        vm.stopPrank();

    }
}

contract SimulateUsersAndDelegationsTest is SimulateUsersAndDelegations {

    function testUserColdWalletOwnership() public {

        address[] memory users = new address[](4);
            users[0] = userA_cw;
            users[1] = userB_cw;
            users[2] = userC_cw;
            users[3] = userC_cw;

        for (uint256 i = 0; i < 4; ++i) {
            
            // check new owner
            address owner = mocaNft.ownerOf(i);
            assertEq(owner, users[i]);
        }
    }

    function testUserHotWalletDelegations() public {
        bool isDelegated;

        isDelegated = delegateV2.checkDelegateForERC721(userA, userA_cw, address(mocaNft), 0, bytes32(0));
        assertTrue(isDelegated);

        isDelegated = delegateV2.checkDelegateForERC721(userB, userB_cw, address(mocaNft), 1, bytes32(0));
        assertTrue(isDelegated);

        isDelegated = delegateV2.checkDelegateForERC721(userC, userC_cw, address(mocaNft), 2, bytes32(0));
        assertTrue(isDelegated);
    }

}

//Note: Deployment of streaming and supporting contracts
abstract contract StateDeploy is SimulateUsersAndDelegations {    
    using stdStorage for StdStorage;

    NftStreaming public streaming;
    ERC20Mock public token;

    // entities
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

    function setUp() public virtual override {
        super.setUp();

        // starting point: T0
        vm.warp(0 days); 

        // users
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

        streaming = new NftStreaming(address(mocaNft), address(token), owner, depositor, address(delegateV2), 
                                    allocationPerNft, startTime, endTime);

        vm.stopPrank();
    
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

        uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = 0;
            
        vm.expectRevert(abi.encodeWithSelector(NotStarted.selector));

        vm.prank(userA);
        streaming.claimDelegated(tokenIds);

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

    // check that DELEGATE_REGISTRY.multicall(data) reverts
    function testIncorrectDelegateCanClaim() public {
        //claimable
        uint256 epsClaimable = streaming.emissionPerSecond();

        //------------ arrays        
        uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = 0;

        address[] memory owners = new address[](tokenIds.length);
            owners[0] = userA_cw;

        uint256[] memory amounts = new uint256[](tokenIds.length);
            amounts[0] = epsClaimable;

        // ---------------------------------------------------

        vm.expectRevert(abi.encodeWithSelector(InvalidDelegate.selector));

        vm.prank(userB);
        streaming.claimDelegated(tokenIds);

    }

    //can call claim; 1 second of emissions claimable
    function testUserACanClaim_T03() public {
        //claimable
        uint256 epsClaimable = streaming.emissionPerSecond();

        //------------ arrays        
        uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = 0;

        address[] memory owners = new address[](tokenIds.length);
            owners[0] = userA_cw;

        uint256[] memory amounts = new uint256[](tokenIds.length);
            amounts[0] = epsClaimable;

        // ---------------------------------------------------

        // before balance
        uint256 userATokenBalance_before = token.balanceOf(userA);
        uint256 userACwTokenBalance_before = token.balanceOf(userA_cw);

        // check events
        vm.expectEmit(true, true, true, true);
        emit ClaimedByDelegate(userA, owners, tokenIds, amounts);

        vm.prank(userA);
        streaming.claimDelegated(tokenIds);

        // after balances
        uint256 userATokenBalance_after = token.balanceOf(userA);
        uint256 userACwTokenBalance_after = token.balanceOf(userA_cw);

        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), totalAllocation - epsClaimable);
        assertEq(userATokenBalance_before, userATokenBalance_after);
        assertEq(userACwTokenBalance_before + epsClaimable, userACwTokenBalance_after);

        // check streaming contract: user
        (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(0);
        assertEq(claimed, token.balanceOf(userA_cw));
        assertEq(lastClaimedTimestamp, block.timestamp);

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }

    function testUserCCanClaimMultiple_T03() public {
        // claimable
        uint256 epsClaimable = 2 * streaming.emissionPerSecond();   // 2 nfts

        //------------ arrays        
        uint256[] memory tokenIds = new uint256[](2);
            tokenIds[0] = 2;
            tokenIds[1] = 3;

        address[] memory owners = new address[](tokenIds.length);
            owners[0] = userC_cw;
            owners[1] = userC_cw;

        uint256[] memory amounts = new uint256[](2);
            amounts[0] = streaming.emissionPerSecond();
            amounts[1] = streaming.emissionPerSecond();

        // ---------------------------------------------------

        // before balance
        uint256 userCTokenBalance_before = token.balanceOf(userC);
        uint256 userCCwTokenBalance_before = token.balanceOf(userC_cw);

        // check events
        vm.expectEmit(true, true, true, true);
        emit ClaimedByDelegate(userC, owners, tokenIds, amounts);

        vm.prank(userC);
        streaming.claimDelegated(tokenIds);

        // after balances
        uint256 userCTokenBalance_after = token.balanceOf(userC);
        uint256 userCCwTokenBalance_after = token.balanceOf(userC_cw);

        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), totalAllocation - epsClaimable);
        assertEq(userCTokenBalance_before, userCTokenBalance_after);
        assertEq(userCCwTokenBalance_before + epsClaimable, userCCwTokenBalance_after);

        // check streaming contract: tokenIds
        for (uint256 i = tokenIds[0]; i < tokenIds.length; ++i) {

            (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(i);

            assertEq(claimed, epsClaimable/tokenIds.length);
            assertEq(lastClaimedTimestamp, block.timestamp);
        }

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }

}


//Note: t = 5 | 3 eps streamed in total
abstract contract StateT05 is StateT03 {

    function setUp() public override virtual {
        super.setUp(); 

        // userA claims @ t3
        uint256[] memory userATokenIds = new uint256[](1);
            userATokenIds[0] = 0;

        vm.prank(userA);
        streaming.claimDelegated(userATokenIds);

        // userC claims @ t3
        uint256[] memory userCTokenIds = new uint256[](2);
            userCTokenIds[0] = 2;
            userCTokenIds[1] = 3;
        
        vm.prank(userC);
        streaming.claimDelegated(userCTokenIds);
        
        // record: 1 unit of eps claimed by each nft
        totalClaimed += 3 * streaming.emissionPerSecond();

        // time
        vm.warp(5);
    }
} 


contract StateT05Test is StateT05 {

    //2 seconds of emissions claimable | 1 eps claimed
    function testUserACanClaim_T05() public {

        //claimable
        uint256 epsClaimable = 2 * streaming.emissionPerSecond();

        //------------ arrays        
        uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = 0;

        address[] memory owners = new address[](tokenIds.length);
            owners[0] = userA_cw;

        uint256[] memory amounts = new uint256[](tokenIds.length);
            amounts[0] = epsClaimable;

        // ---------------------------------------------------

        // before balance
        uint256 userATokenBalance_before = token.balanceOf(userA);
        uint256 userACwTokenBalance_before = token.balanceOf(userA_cw);

        // check events
        vm.expectEmit(true, true, true, true);
        emit ClaimedByDelegate(userA, owners, tokenIds, amounts);

        vm.prank(userA);
        streaming.claimDelegated(tokenIds);

        // after balances
        uint256 userATokenBalance_after = token.balanceOf(userA);
        uint256 userACwTokenBalance_after = token.balanceOf(userA_cw);

        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), totalAllocation - totalClaimed - epsClaimable);
        assertEq(userATokenBalance_before, userATokenBalance_after);
        assertEq(userACwTokenBalance_before + epsClaimable, userACwTokenBalance_after);

        // check streaming contract: user
        (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(0);
        assertEq(claimed, token.balanceOf(userA_cw));
        assertEq(lastClaimedTimestamp, block.timestamp);

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }

    function testUserCCanClaimMultiple_T05() public {
        // claimable
        uint256 epsClaimable = (2 * streaming.emissionPerSecond()) * 2;   // 2 nfts

        //------------ arrays        
        uint256[] memory tokenIds = new uint256[](2);
            tokenIds[0] = 2;
            tokenIds[1] = 3;

        address[] memory owners = new address[](tokenIds.length);
            owners[0] = userC_cw;
            owners[1] = userC_cw;

        uint256[] memory amounts = new uint256[](2);
            amounts[0] = 2 * streaming.emissionPerSecond();
            amounts[1] = 2 * streaming.emissionPerSecond();

        // ---------------------------------------------------

        // before balance
        uint256 userCTokenBalance_before = token.balanceOf(userC);
        uint256 userCCwTokenBalance_before = token.balanceOf(userC_cw);

        // check events
        vm.expectEmit(true, true, true, true);
        emit ClaimedByDelegate(userC, owners, tokenIds, amounts);

        vm.prank(userC);
        streaming.claimDelegated(tokenIds);

        // after balances
        uint256 userCTokenBalance_after = token.balanceOf(userC);
        uint256 userCCwTokenBalance_after = token.balanceOf(userC_cw);

        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), totalAllocation - totalClaimed - epsClaimable);
        assertEq(userCTokenBalance_before, userCTokenBalance_after);
        assertEq(userCCwTokenBalance_before + epsClaimable, userCCwTokenBalance_after);

        // check streaming contract: tokenIds
        for (uint256 i = tokenIds[0]; i < tokenIds.length; ++i) {

            (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(i);

            assertEq(claimed, epsClaimable/tokenIds.length);
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
        uint256[] memory userATokenIds = new uint256[](1);
            userATokenIds[0] = 0;

        vm.prank(userA);
        streaming.claimDelegated(userATokenIds);

        // userC claimed: t3 - t5 -> 2s * 2eps = 4 units
        uint256[] memory userCTokenIds = new uint256[](2);
            userCTokenIds[0] = 2;
            userCTokenIds[1] = 3;
        
        vm.prank(userC);
        streaming.claimDelegated(userCTokenIds);
        
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
        //claimable
        uint256 epsClaimable = 7 * streaming.emissionPerSecond();

        //------------ arrays        
        uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = 0;

        address[] memory owners = new address[](tokenIds.length);
            owners[0] = userA_cw;

        uint256[] memory amounts = new uint256[](tokenIds.length);
            amounts[0] = epsClaimable;

        // ---------------------------------------------------

        // before balance
        uint256 userATokenBalance_before = token.balanceOf(userA);
        uint256 userACwTokenBalance_before = token.balanceOf(userA_cw);

        // check events
        vm.expectEmit(true, true, true, true);
        emit ClaimedByDelegate(userA, owners, tokenIds, amounts);

        vm.prank(userA);
        streaming.claimDelegated(tokenIds);

        // after balances
        uint256 userATokenBalance_after = token.balanceOf(userA);
        uint256 userACwTokenBalance_after = token.balanceOf(userA_cw);

        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), totalAllocation - totalClaimed - epsClaimable);
        assertEq(userATokenBalance_before, userATokenBalance_after);
        assertEq(userACwTokenBalance_before + epsClaimable, userACwTokenBalance_after);

        // check streaming contract: user
        (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(0);
        assertEq(claimed, token.balanceOf(userA_cw));
        assertEq(lastClaimedTimestamp, block.timestamp);

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }

    function testUserCCanClaimMultiple_T12() public {
        // claimable
        uint256 epsClaimable = (2 * streaming.emissionPerSecond()) * 7;   // 2 nfts

        //------------ arrays        
        uint256[] memory tokenIds = new uint256[](2);
            tokenIds[0] = 2;
            tokenIds[1] = 3;

        address[] memory owners = new address[](tokenIds.length);
            owners[0] = userC_cw;
            owners[1] = userC_cw;

        uint256[] memory amounts = new uint256[](2);
            amounts[0] = 7 * streaming.emissionPerSecond();
            amounts[1] = 7 * streaming.emissionPerSecond();

        // ---------------------------------------------------

        // before balance
        uint256 userCTokenBalance_before = token.balanceOf(userC);
        uint256 userCCwTokenBalance_before = token.balanceOf(userC_cw);

        // check events
        vm.expectEmit(true, true, true, true);
        emit ClaimedByDelegate(userC, owners, tokenIds, amounts);

        vm.prank(userC);
        streaming.claimDelegated(tokenIds);

        // after balances
        uint256 userCTokenBalance_after = token.balanceOf(userC);
        uint256 userCCwTokenBalance_after = token.balanceOf(userC_cw);

        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), totalAllocation - totalClaimed - epsClaimable);
        assertEq(userCTokenBalance_before, userCTokenBalance_after);
        assertEq(userCCwTokenBalance_before + epsClaimable, userCCwTokenBalance_after);

        // check streaming contract: tokenIds
        for (uint256 i = tokenIds[0]; i < tokenIds.length; ++i) {

            (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(i);

            assertEq(claimed, epsClaimable/tokenIds.length);
            assertEq(lastClaimedTimestamp, block.timestamp);
        }

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }

}

//Note: t = endTime + 2 days
abstract contract StateStreamEndedPlusTwoDays is StateStreamEnded {
    function setUp() public override virtual {
        super.setUp(); 

        vm.warp((endTime + 2 days));
    }
}

contract StateStreamEndedPlusTwoDaysTest is StateStreamEndedPlusTwoDays {
    
    function testUserACanClaim_AfterStreamEnded() public {
        //claimable
        uint256 epsClaimable = 7 * streaming.emissionPerSecond();

        //------------ arrays        
        uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = 0;

        address[] memory owners = new address[](tokenIds.length);
            owners[0] = userA_cw;

        uint256[] memory amounts = new uint256[](tokenIds.length);
            amounts[0] = epsClaimable;

        // ---------------------------------------------------

        // before balance
        uint256 userATokenBalance_before = token.balanceOf(userA);
        uint256 userACwTokenBalance_before = token.balanceOf(userA_cw);

        // check events
        vm.expectEmit(true, true, true, true);
        emit ClaimedByDelegate(userA, owners, tokenIds, amounts);

        vm.prank(userA);
        streaming.claimDelegated(tokenIds);

        // after balances
        uint256 userATokenBalance_after = token.balanceOf(userA);
        uint256 userACwTokenBalance_after = token.balanceOf(userA_cw);

        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), totalAllocation - totalClaimed - epsClaimable);
        assertEq(userATokenBalance_before, userATokenBalance_after);
        assertEq(userACwTokenBalance_before + epsClaimable, userACwTokenBalance_after);

        // check streaming contract: user
        (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(0);
        assertEq(claimed, token.balanceOf(userA_cw));
        assertEq(lastClaimedTimestamp, streaming.endTime());

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }

    function testUserCCanClaimMultiple_AfterStreamEnded() public {
        // claimable
        uint256 epsClaimable = (2 * streaming.emissionPerSecond()) * 7;   // 2 nfts

        //------------ arrays        
        uint256[] memory tokenIds = new uint256[](2);
            tokenIds[0] = 2;
            tokenIds[1] = 3;

        address[] memory owners = new address[](tokenIds.length);
            owners[0] = userC_cw;
            owners[1] = userC_cw;

        uint256[] memory amounts = new uint256[](2);
            amounts[0] = 7 * streaming.emissionPerSecond();
            amounts[1] = 7 * streaming.emissionPerSecond();

        // ---------------------------------------------------

        // before balance
        uint256 userCTokenBalance_before = token.balanceOf(userC);
        uint256 userCCwTokenBalance_before = token.balanceOf(userC_cw);

        // check events
        vm.expectEmit(true, true, true, true);
        emit ClaimedByDelegate(userC, owners, tokenIds, amounts);

        vm.prank(userC);
        streaming.claimDelegated(tokenIds);

        // after balances
        uint256 userCTokenBalance_after = token.balanceOf(userC);
        uint256 userCCwTokenBalance_after = token.balanceOf(userC_cw);

        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), totalAllocation - totalClaimed - epsClaimable);
        assertEq(userCTokenBalance_before, userCTokenBalance_after);
        assertEq(userCCwTokenBalance_before + epsClaimable, userCCwTokenBalance_after);

        // check streaming contract: tokenIds
        for (uint256 i = tokenIds[0]; i < tokenIds.length; ++i) {

            (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(i);

            assertEq(claimed, epsClaimable/tokenIds.length);
            assertEq(lastClaimedTimestamp, streaming.endTime());
        }

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
        //claimable
        uint256 epsClaimable = 7 * streaming.emissionPerSecond();

        //------------ arrays        
        uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = 0;

        address[] memory owners = new address[](tokenIds.length);
            owners[0] = userA_cw;

        uint256[] memory amounts = new uint256[](tokenIds.length);
            amounts[0] = epsClaimable;

        // ---------------------------------------------------

        // before balance
        uint256 userATokenBalance_before = token.balanceOf(userA);
        uint256 userACwTokenBalance_before = token.balanceOf(userA_cw);

        // check events
        vm.expectEmit(true, true, true, true);
        emit ClaimedByDelegate(userA, owners, tokenIds, amounts);

        vm.prank(userA);
        streaming.claimDelegated(tokenIds);

        // after balances
        uint256 userATokenBalance_after = token.balanceOf(userA);
        uint256 userACwTokenBalance_after = token.balanceOf(userA_cw);

        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), totalAllocation - totalClaimed - epsClaimable);
        assertEq(userATokenBalance_before, userATokenBalance_after);
        assertEq(userACwTokenBalance_before + epsClaimable, userACwTokenBalance_after);

        // check streaming contract: user
        (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(0);
        assertEq(claimed, token.balanceOf(userA_cw));
        assertEq(lastClaimedTimestamp, block.timestamp);

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }

    function testUserCCanClaimMultiple_AfterStreamEnded() public {
        // claimable
        uint256 epsClaimable = (2 * streaming.emissionPerSecond()) * 7;   // 2 nfts

        //------------ arrays        
        uint256[] memory tokenIds = new uint256[](2);
            tokenIds[0] = 2;
            tokenIds[1] = 3;

        address[] memory owners = new address[](tokenIds.length);
            owners[0] = userC_cw;
            owners[1] = userC_cw;

        uint256[] memory amounts = new uint256[](2);
            amounts[0] = 7 * streaming.emissionPerSecond();
            amounts[1] = 7 * streaming.emissionPerSecond();

        // ---------------------------------------------------

        // before balance
        uint256 userCTokenBalance_before = token.balanceOf(userC);
        uint256 userCCwTokenBalance_before = token.balanceOf(userC_cw);

        // check events
        vm.expectEmit(true, true, true, true);
        emit ClaimedByDelegate(userC, owners, tokenIds, amounts);

        vm.prank(userC);
        streaming.claimDelegated(tokenIds);

        // after balances
        uint256 userCTokenBalance_after = token.balanceOf(userC);
        uint256 userCCwTokenBalance_after = token.balanceOf(userC_cw);

        // check tokens transfers
        assertEq(token.balanceOf(address(streaming)), totalAllocation - totalClaimed - epsClaimable);
        assertEq(userCTokenBalance_before, userCTokenBalance_after);
        assertEq(userCCwTokenBalance_before + epsClaimable, userCCwTokenBalance_after);

        // check streaming contract: tokenIds
        for (uint256 i = tokenIds[0]; i < tokenIds.length; ++i) {

            (uint128 claimed, uint128 lastClaimedTimestamp, bool isPaused) = streaming.streams(i);

            assertEq(claimed, epsClaimable/tokenIds.length);
            assertEq(lastClaimedTimestamp, block.timestamp);
        }

        // check streaming contract: storage variables
        assertEq(streaming.totalClaimed(), (totalClaimed + epsClaimable));
    }

}