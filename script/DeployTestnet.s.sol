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
        
        // Oct 11 2024 17:00:00 HKT
        uint256 startTime = 1728637200; 
        // Oct 11 2025, 17:00:00 HKT
        uint256 endTime = 1760173200; 

        streaming = new NftStreaming(address(mockNft), address(mockToken), owner, depositor, operator, delegateRegistry,
                    uint128(allocationPerNft), startTime, endTime);

        vm.stopBroadcast();
    }
}
