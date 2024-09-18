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

    // users
    address public userA;
    address public userB;
    address public userC;

    function setUp() public virtual override{
        super.setUp();

        // users
        userA = makeAddr("userA");
        userB = makeAddr("userB");
        userC = makeAddr("userC");

        // edit storage 
        stdstore
            .target(address(mocaNft))
            .sig("ownerOf(uint256)")
            .with_key(1)
            .checked_write(userA);

        address owner = mocaNft.ownerOf(1);
        
        // check new owner
        assertEq(owner, userA);
    }
}

contract SimulateUsersAndDelegationsTest is SimulateUsersAndDelegations {

    function testUserOwnership() public {

                      
         // check new owner
        address owner = mocaNft.ownerOf(1);
        assertEq(owner, userA);
        
    }
}
/*
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

        vm.prank(userB);
        nft.setApprovalForAll(address(mockModule), true);

        vm.prank(userC);
        nft.setApprovalForAll(address(mockModule), true);

    }
}
*/
/*
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
*/