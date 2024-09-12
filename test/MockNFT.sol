// SPDX-License-Identifier: MIT 
pragma solidity 0.8.24;

import {ERC721} from "./../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

contract MockNFT is ERC721 {

    constructor() ERC721("MockNFT","MockNFT"){}

    function mint(address to, uint256 tokenId) external {
        _safeMint(to, tokenId);
    }

}