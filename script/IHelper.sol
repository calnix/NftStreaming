// SPDX-License-Identifier: MIT 
pragma solidity >=0.8.13;
interface IHelper {

    function isOwnerOf(address msgSender, uint256 tokenId) external;

    function isOwnerOfAll(address msgSender, uint256[] calldata tokenIds) external;


} 
