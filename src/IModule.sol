// SPDX-License-Identifier: MIT 
pragma solidity 0.8.24;

interface IModule {
   
    /**
     * @notice Check if tokenIds owner matches supplied address
     * @dev If user is owner of all tokenIds, fn expected to revert
     * @param user Address to check against 
     * @param tokenIds TokenIds to check
     */
    function streamingOwnerCheck(address user, uint256[] calldata tokenIds) external view;
}