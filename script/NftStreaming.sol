// SPDX-License-Identifier: MIT 
pragma solidity 0.8.24;

import {IERC721} from "./../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

import {SafeERC20, IERC20} from "./../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";

import "./Events.sol";
import "./Errors.sol";
import {IDelegateRegistry} from "./IDelegateRegistry.sol";
import {IHelper} from "./IHelper.sol";

/**
 * @title MocaStreaming
 * @custom:version 1.0
 * @custom:author Calnix(@cal_nix)
 * @notice Contract to stream token rewards to Moca NFT holders 
 */

contract NftStreaming is Pausable, Ownable2Step {
    using SafeERC20 for IERC20;

    // assets
    IERC721 public immutable NFT;
    IERC20 public immutable TOKEN;

    // external 
    IDelegateRegistry public DELEGATE_REGISTRY;  // https://docs.delegate.xyz/technical-documentation/delegate-registry/contract-addresses

    // total supply of NFTs
    uint256 public constant totalSupply = 8_888;
    
    // stream period
    uint256 public immutable startTime;
    uint256 public immutable endTime;
    
    // allocation
    uint256 public immutable allocationPerNft;
    uint256 public immutable emissionPerSecond;
    uint256 public immutable totalAllocation;

    // financing
    address public depositor;
    uint256 public totalClaimed;
    uint256 public totalDeposited;
    
    // optional: Users can claim until this timestamp
    uint256 public deadline;                

    // emergency state: 1 is Frozed. 0 is not.
    uint256 public isFrozen;
    uint256 public setupComplete;

    /**
     * @notice Struct encapsulating the claimed and refunded amounts, all denoted in units of the asset's decimals.
     * @dev Because the claimed amount and lastTimestamp are often read together, declaring them in the same slot saves gas.
     * @param claimed The cumulative amount withdrawn from the stream.
     * @param lastClaimedTimestamp Last claim time
     * @param refunded The amount refunded to the sender. Unless the stream was canceLled, this is always zero.   
     */
    struct Stream {
        // slot0
        uint128 claimed;
        uint128 lastClaimedTimestamp;
        // slot 1
        uint128 refunded;
        bool wasCanceled;
    }

    mapping(uint256 tokenId => Stream stream) public streams;
    mapping(address module => bool isRegistered) public modules;    // Trusted contracts to call anything on

    /**
     * @notice Struct encapsulating the claimed and refunded amounts, all denoted in units of the asset's decimals.
     * @dev Because the deposited and the withdrawn amount are often read together, declaring them in the same slot saves gas.
     * @param claimed The cumulative amount withdrawn from the stream.
     * @param refunded The amount refunded to the sender. Unless the stream was canceled, this is always zero.   
     */
    struct Amounts {
        // slot 0
        uint128 claimed;
        uint128 refunded;
        // slot 1
        // bool isCancelable;
        // bool wasCanceled;
    }

    /**
     * @notice Enum representing the different statuses of a stream.
     * @custom:value0 PENDING Stream created but not started; assets are in a pending state.
     * @custom:value1 STREAMING Active stream where assets are currently being streamed.
     * @custom:value2 SETTLED All assets have been streamed; recipient is due to withdraw them.
     * @custom:value3 CANCELED Canceled stream; remaining assets await recipient's withdrawal.
     * @custom:value4 DEPLETED Depleted stream; all assets have been withdrawn and/or refunded.
    */ 
    enum Status {
        PENDING,
        STREAMING,
        SETTLED,
        CANCELED,
        DEPLETED
    }

    constructor(
        address nft, address token, address owner, address depositor_, address delegateRegistry,
        uint256 allocationPerNft_, uint256 startTime_, uint256 endTime_) Ownable(owner) {
        
        NFT = IERC721(nft);
        TOKEN = IERC20(token);

        DELEGATE_REGISTRY = IDelegateRegistry(delegateRegistry);
        
        depositor = depositor_;

        // check inputs 
        if(startTime_ <= block.timestamp) revert InvalidStartime();
        if(endTime_ <= startTime_) revert InvalidEndTime(); 
        if(allocationPerNft_ == 0) revert InvalidAllocation();

        // calculate emissionPerSecond
        uint256 period = endTime - startTime; 
        emissionPerSecond = allocationPerNft_ / period;
        if(emissionPerSecond == 0) revert InvalidEmission();

        // storage
        startTime = startTime_;
        endTime = endTime_;
        allocationPerNft = allocationPerNft_;        
        totalAllocation = allocationPerNft_ * totalSupply;

    }

    /*//////////////////////////////////////////////////////////////
                                 USERS
    //////////////////////////////////////////////////////////////*/

    // if nft in wallet
    function claimSingle(uint256 tokenId) external payable {
        if(block.timestamp < startTime) revert NotStarted();

        // check that deadline as not been exceeded; if deadline has been defined
        if(deadline > 0) {
            if (block.timestamp > deadline) {
                revert DeadlineExceeded();
            }
        }
        
        // validate ownership
        address ownerOf = NFT.ownerOf(tokenId);
        if(msg.sender != ownerOf) revert InvalidOwner();  
        //         if (msg.sender == nftOwner || DELEGATE_REGISTRY.checkDelegateForERC721(msg.sender, nftOwner, address(NFT), tokenId, "")) {
        
        uint256 claimable = _updateLastClaimed(tokenId);
        
        emit Claimed(msg.sender, claimable);
 
        //transfer 
        TOKEN.safeTransfer(msg.sender, claimable);        
    }

    function claimMultiple(uint256[] calldata tokenIds) external payable whenStartedAndNotEnded {
        
        // array validation
        uint256 tokenIdsLength = tokenIds.length;
        if(tokenIdsLength == 0) revert EmptyArray(); 

        uint128 totalAmount;
        for(uint256 i = 0; i < tokenIdsLength; ++i) {
        }

    }


    function claimDelegatedAndWallet(uint256[] calldata tokenIdsInWallet, uint256[] calldata tokenIdsDelegated) external payable whenStartedAndNotEnded whenNotPaused {

        // array validation
        uint256 tokenIdsLength = tokenIds.length;
        if(tokenIdsLength == 0) revert EmptyArray(); 



    }

//--------------

    // if nft in wallet or delegated
    function claimDelegated(uint256[] calldata tokenIds) external payable whenStartedAndNotEnded whenNotPaused {
        
        // array validation
        uint256 tokenIdsLength = tokenIds.length;
        if(tokenIdsLength == 0) revert EmptyArray(); 

        // check delegation 
        bytes[] memory data = new bytes[](tokenIdsLength);
        for (uint256 i = 0; i < tokenIdsLength; ++i) {
            
            // get nft Owner
            uint256 tokenId = tokenIds[i];
            address nftOwner = NFT.ownerOf(tokenId);          

            data[i] = abi.encodeWithSignature("delegateERC721(address,address,uint256,bytes32,bool)", 
                        msg.sender, nftOwner, address(NFT), tokenId, "");
        }

        // if a tokenId is not delegated will revert with: MulticallFailed()
        DELEGATE_REGISTRY.multicall(data);

        // update claims
        uint256 totalAmount;
        uint256[] memory amounts = new uint256[](tokenIdsLength);
        for (uint256 i = 0; i < tokenIdsLength; ++i) {
            
            uint256 tokenId = tokenIds[i];
                
            uint256 claimable = _updateLastClaimed(tokenId);
                
            totalAmount += claimable;
            amounts[i] = claimable;
        }
        
        // claimed per tokenId
        emit Claimed(msg.sender, tokenIds, amounts);
 
        // transfer 
        TOKEN.safeTransfer(msg.sender, totalAmount);      
    }


    function claimViaModule(address module, bytes calldata data, uint256[] calldata tokenIds) external payable whenStartedAndNotEnded whenNotPaused {
        
        // array validation
        uint256 tokenIdsLength = tokenIds.length;
        if(tokenIdsLength == 0) revert EmptyArray(); 

        // ensure valid module
        if(!modules[module]) revert UnregisteredModule(); 

        // check ownership via moduleCall
        // data: abi.encodeWithSignature("isOwnerOf(uint256[])", tokenIds)
        // if not owner, call should revert
        (bool success, bytes memory result) = module.staticcall(data);
        require(success);
        

        uint256 totalAmount;
        uint256[] memory amounts = new uint256[](tokenIdsLength);
        
        for (uint256 i = 0; i < tokenIdsLength; ++i) {
                uint256 claimable = _updateLastClaimed(tokenId);
                
                totalAmount += claimable;
                amounts[i] = claimable;
        }

        // claimed per tokenId
        emit Claimed(msg.sender, tokenIds, amounts);

        // transfer 
        TOKEN.safeTransfer(msg.sender, totalAmount);    
    }


    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _updateLastClaimed(uint256 tokenId) internal returns(uint256) {
        
        // get data
        Stream memory stream = streams[tokenId];

        // stream updated: return
        if(stream.lastClaimedTimestamp == block.timestamp) { 
            return(0);
        }

        // stream ended: return
        if(stream.lastClaimedTimestamp == endTime) { 
            return(0);
        }

        //note: cancelled/paused
        //if(claim.wasCancelled)

        //calc claimable
        (uint256 claimable, uint256 currentTimestamp) = _calculateClaimable(stream.lastClaimedTimestamp);

        // sanity check: ensure does not exceed max
        if(claimable > allocationPerNft) revert IncorrectClaimable();

        // update timestamp + claimed
        stream.lastClaimedTimestamp = uint128(currentTimestamp);
        stream.claimed += uint128(claimable);

        // storage
        streams[tokenId] = stream;

        return claimable;
    }

    function _calculateClaimable(uint128 lastClaimedTimestamp) internal view returns(uint256, uint256) {
        
        // currentTimestamp <= endTime
        uint256 currentTimestamp = block.timestamp > endTime ? endTime : block.timestamp;
        
        uint256 timeDelta = currentTimestamp - lastClaimedTimestamp;
        uint256 claimable = emissionPerSecond * timeDelta;

        return (claimable, currentTimestamp);
    }

    /*//////////////////////////////////////////////////////////////
                                 OWNER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Owner to update deadline variable
     * @dev By default deadline = 0 
     * @param newDeadline must be after last claim round + 14 days
     */
    function updateDeadline(uint256 newDeadline) external payable onlyOwner {

        // allow for 14 days buffer: prevent malicious premature ending
        if (newDeadline < endTime + 14 days) revert InvalidNewDeadline();

        deadline = newDeadline;
        emit DeadlineUpdated(newDeadline);
    }

    /**
     * @notice Owner to update depositor address
     * @dev Depositor role allows calling of deposit and withdraw fns
     * @param newDepositor new address
     */
    function updateDepositor(address newDepositor) external payable onlyOwner {
        address oldDepositor = depositor;

        depositor = newDepositor;

        emit DepositorUpdated(oldDepositor, newDepositor);
    }

    function updateHelper(address newHelper) external payable onlyOwner {
        address(HELPER) = oldHelper;

        HELPER = IHelper(newHelper);

        emit HelperUpdated(oldHelper, newHelper);        
    }

    /**
     * @notice
     * @dev Add or remove a module
     */ 
    function updateModule(address module, bool set) external onlyOwner {
        
        modules[module] = set;

        emit ModuleUpdated(module, set);
    }

    /*//////////////////////////////////////////////////////////////
                               DEPOSITOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Depositor to deposit the total tokens required
     * @dev Depositor can fund in totality at once or incrementally, 
            so to avoid having to commit a large initial sum
     * @param amount Amount to deposit
     */
    function deposit(uint256 amount) external {
        if(msg.sender != depositor) revert OnlyDepositor(); 

        // surplus check?
        if(totalAllocation > (totalDeposited + amount)) revert ExcessDeposit(); 

        emit Deposited(msg.sender);
        TOKEN.safeTransferFrom(msg.sender, address(this), amount);
    }


    /**
     * @notice Operator to withdraw all unclaimed tokens past the specified deadline
     * @dev Only possible if deadline has been defined and exceeded
     */
    function withdraw() external {
        if(msg.sender != depositor) revert OnlyDepositor(); 

        // if deadline is not defined; cannot withdraw
        if(deadline == 0) revert WithdrawDisabled();
        
        // can only withdraw after deadline
        if(block.timestamp <= deadline) revert PrematureWithdrawal();

        // only can withdraw what was deposited. disregards random transfers
        uint256 available = totalDeposited - totalClaimed;

        emit Withdrawn(msg.sender, available);

        TOKEN.safeTransfer(msg.sender, available);       

    }


    /*//////////////////////////////////////////////////////////////
                                PAUSABLE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pause claim
     */
    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    /**
     * @notice Unpause claim. Cannot unpause once frozen
     */
    function unpause() external onlyOwner whenPaused {
        if(isFrozen == 1) revert IsFrozen(); 

        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                                RECOVERY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Freeze the contract in the event of something untoward occuring
     * @dev Only callable from a paused state, affirming that distribution should not resume
     *      Nothing to be updated. Freeze as is.
            Enables emergencyExit() to be called.
     */
    function freeze() external whenPaused onlyOwner {
        if(isFrozen == 1) revert IsFrozen(); 
        
        isFrozen = 1;

        emit Frozen(block.timestamp);
    }  


    /**
     * @notice Recover assets in a black swan event. 
               Assumed that this contract will no longer be used. 
     * @dev Transfers all tokens to specified address 
     * @param receiver Address of beneficiary of transfer
     */
    function emergencyExit(address receiver) external whenPaused onlyOwner {
        if(isFrozen == 0) revert NotFrozen();

        uint256 balance = TOKEN.balanceOf(address(this));

        emit EmergencyExit(receiver, balance);

        TOKEN.safeTransfer(receiver, balance);
    }


    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/


    modifier whenStartedAndNotEnded() {

        if(block.timestamp < startTime) revert NotStarted();

        // check that deadline as not been exceeded; if deadline has been defined
        if(deadline > 0) {
            if (block.timestamp > deadline) {
                revert DeadlineExceeded();
            }
        }

        _;
    }



}
