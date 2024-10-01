// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {NftStreaming} from "../src/NftStreaming.sol";

contract DeployMainnet is Script {
    
    NftStreaming public streaming;

    function setUp() public {}

    function run() public {
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_TEST");
        vm.startBroadcast(deployerPrivateKey);    

        
        address nft = 0x59325733eb952a92e069C87F0A6168b29E80627f;               // https://etherscan.io/address/0x59325733eb952a92e069c87f0a6168b29e80627f
        address token = 0xF944e35f95E819E752f3cCB5Faf40957d311e8c5;             // https://etherscan.io/address/0xf944e35f95e819e752f3ccb5faf40957d311e8c5
        address delegateRegistry = 0x00000000000000447e69651d841bD8D104Bed493;  // https://docs.delegate.xyz/technical-documentation/delegate-registry/contract-addresses
        
        address owner = address(0);                                 // note: Replace with actual depositor address
        address depositor = address(0);                             // note: Replace with actual depositor address
        address operator = 0x9e9f6b8CBAF89b0fF9EeF6573785741299BF62CB; 
        
        uint256 allocationPerNft = 47_554.52 ether;
        
        // Oct 11 2024 17:00:00 HKT
        uint256 startTime = 1728637200; 
        // Oct 11 2025, 17:00:00 HKT
        uint256 endTime = 1760173200; 

        
        streaming = new NftStreaming(nft, token, owner, depositor, operator, delegateRegistry,
                        uint128(allocationPerNft), startTime, endTime);

        
        vm.stopBroadcast();
    }
}
