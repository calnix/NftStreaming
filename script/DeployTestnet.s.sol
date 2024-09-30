// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {NftStreaming} from "../src/NftStreaming.sol";

import {MockNFT} from "../test/MockNFT.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract DeployTestnet is Script {
    
    NftStreaming public streaming;
    MockNFT public mockNft;
    ERC20Mock public mockToken;

    function setUp() public {}

    function run() public {
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_TEST");
        address deployerAddress = vm.envAddress("PUBLIC_KEY_TEST");

        vm.startBroadcast(deployerPrivateKey);    

        mockNft = new MockNFT();
        mockToken = new ERC20Mock();

        address owner = deployerAddress;
        address depositor = deployerAddress;
        address operator = deployerAddress;
        
        address delegateRegistry = address(0);
        
        uint256 allocationPerNft = 47_554.52 ether;
        
        // now + 1 hour
        uint256 startTime = block.timestamp + 3600; 
        // now + 10 days
        uint256 endTime = startTime + 864000; 

        // calculate total allocation
        uint256 totalAllocation = allocationPerNft * 8_888;


        // deploy streaming
        streaming = new NftStreaming(address(mockNft), address(mockToken), owner, depositor, operator, delegateRegistry,
                    uint128(allocationPerNft), startTime, endTime);

        // mint + deposit all tokens
        mockToken.mint(depositor, totalAllocation);
        mockToken.approve(address(streaming), totalAllocation);
        streaming.deposit(totalAllocation);

        vm.stopBroadcast();
    }
}

// forge script script/DeployTestnet.s.sol:DeployTestnet --rpc-url arbitrum_sepolia --broadcast --verify -vvvvv --etherscan-api-key arbitrum_sepolia

contract PoorMansBundle {
    
    NftStreaming public streaming;
    MockNFT public mockNft;
    ERC20Mock public mockToken;
    
    address public constant deployerAddress = 0x8C9C001F821c04513616fd7962B2D8c62f925fD2;

        address owner = deployerAddress;
        address depositor = deployerAddress;
        address operator = deployerAddress;

    // deploy params    
    address public constant delegateRegistry = address(0);
    uint256 public constant allocationPerNft = 47_554.52 ether;

    // now + 1 hour
    uint256 public startTime = block.timestamp + 3600; 
    // now + 10 days
    uint256 public endTime = startTime + 864000; 

    // calculate total allocation
    uint256 public constant totalAllocation = allocationPerNft * 8_888;

    constructor() {
        
        // deploy mock contracts
        mockNft = new MockNFT();
        mockToken = new ERC20Mock();

        streaming = new NftStreaming(address(mockNft), address(mockToken), owner, depositor, operator, delegateRegistry,
                    uint128(allocationPerNft), startTime, endTime);

        // mint tokens
        mockToken.mint(depositor, totalAllocation);

    }
}

contract BatchDeploy is Script {

    function setUp() public {}


    function run() public {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_TEST");
        address deployerAddress = vm.envAddress("PUBLIC_KEY_TEST");

        vm.startBroadcast(deployerPrivateKey);    

        // batch deploy
        new PoorMansBundle();

        // deposit all tokens
        //mockToken.approve(address(streaming), PoorMansBundle.totalAllocation());
        //streaming.deposit(PoorMansBundle.totalAllocation());

        vm.stopBroadcast();
    }
}

// forge script script/DeployTestnet.s.sol:BatchDeploy --rpc-url arbitrum_sepolia --broadcast --verify -vvvvv --etherscan-api-key arbitrum_sepolia --legacy
