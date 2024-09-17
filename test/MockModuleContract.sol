// SPDX-License-Identifier: MIT 
pragma solidity 0.8.24;

import {IERC721} from "./../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

contract MockModuleContract {

    IERC721 public immutable NFT;

    mapping(uint256 tokenId => address user) public nfts;

    constructor(address nft) {
        
        NFT = IERC721(nft);
    }


    function lock(uint256[] calldata tokenIds) external {

        uint256 length = tokenIds.length;
        require(length > 0, "Empty array");

        for (uint256 i; i < length; ++i) {
            
            uint256 tokenId = tokenIds[i];
            require(nfts[tokenId] == address(0), "Already locked");                
            
            // update storage
            nfts[tokenId] = msg.sender;

            // grab
            NFT.transferFrom(msg.sender, address(this), tokenId);
        }
    }

    function unlock(uint256[] calldata tokenIds) external {

        uint256 length = tokenIds.length;
        require(length > 0, "Empty array");

        for (uint256 i; i < length; ++i) {
            uint256 tokenId = tokenIds[i];

            require(nfts[tokenId] == msg.sender, "Incorrect owner");                

            // delete tagged address
            delete nfts[tokenId];

            // return
            NFT.transferFrom(address(this), msg.sender, tokenId);
        }
    }

    function streamingOwnerCheck(address user, uint256[] calldata tokenIds) public view {
        uint256 length = tokenIds.length;
        require(length > 0, "Empty array");

        for(uint256 i; i < tokenIds.length; ++i){
            
            uint256 tokenId = tokenIds[i];
            address owner = nfts[tokenId];

            require(owner == user, "Incorrect Owner");
        }

    }
}