// SPDX-License-Identifier: MIT 
pragma solidity 0.8.24;

import {IERC721} from "./../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

import {SafeERC20, IERC20} from "./../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";

import {IModule} from "./IModule.sol";
import {IDelegateRegistry} from "./IDelegateRegistry.sol";

import "./Events.sol";
import "./Errors.sol";

/**
 * @title NftStreaming
 * @custom:version 1.0
 * @custom:author Calnix(@cal_nix)
 * @notice Contract to stream token rewards to NFT holders 
 */

contract NftStreaming is Pausable, Ownable2Step {
    using SafeERC20 for IERC20;

    // assets
    IERC721 public immutable NFT;
    IERC20 public immutable TOKEN;

    // external 
    IDelegateRegistry public immutable DELEGATE_REGISTRY;  // https://docs.delegate.xyz/technical-documentation/delegate-registry/contract-addresses

    // total supply of NFTs
    uint256 public constant totalSupply = 8_888;
    
    // stream period
    uint256 public immutable startTime;
    uint256 public immutable endTime;
    
    // allocation
    uint256 public immutable allocationPerNft;    // expressed together with appropriate decimal precision [1 ether -> 1e18]
    uint256 public immutable emissionPerSecond;   // per NFT
    uint256 public immutable totalAllocation;

    // financing
    address public depositor;
    uint256 public totalClaimed;
    uint256 public totalDeposited;
    
    // optional: Users can claim until this timestamp
    uint256 public deadline;    

    // operator role: can pause, cannot unpause
    address public operator;            

    // emergency state: 1 is Frozed. 0 is not.
    uint256 public isFrozen;

    /**
     * @notice Struct encapsulating the claimed and refunded amounts, all denoted in units of the asset's decimals.
     * @dev Because the claimed amount and lastTimestamp are often read together, declaring them in the same slot saves gas.
     * @param claimed The cumulative amount withdrawn from the stream.
     * @param lastClaimedTimestamp Last claim time
     * @param isPaused Is the stream paused 
     */
    struct Stream {
        // slot0
        uint128 claimed;
        uint128 lastClaimedTimestamp;
        // slot 1
        bool isPaused;
    }

    // Streams 
    mapping(uint256 tokenId => Stream stream) public streams;
    
    // Trusted contracts to call
    mapping(address module => bool isRegistered) public modules;    

    // note: uint128(allocationPerNft) is used to ensure downstream calculations involving claimable do not overflow
    constructor(
        address nft, address token, address owner, address depositor_, address operator_, address delegateRegistry,
        uint128 allocationPerNft_, uint256 startTime_, uint256 endTime_) Ownable(owner) {
             
        // check inputs 
        if(startTime_ <= block.timestamp) revert InvalidStartime();
        if(endTime_ <= startTime_) revert InvalidEndTime(); 
        if(allocationPerNft_ == 0) revert InvalidAllocation();

        // calculate emissionPerSecond
        uint256 period = endTime_ - startTime_;       
        uint256 emissionPerSecond_ = allocationPerNft_ / period; 
        if(emissionPerSecond_ == 0) revert InvalidEmission();

        /**
            Note:
                Solidity rounds down on division, 
                so there could be disregarded remainder on calc. emissionPerSecond

                Therefore, the remainder is distributed on the last tick,
                as seen in the if statement in _calculateClaimable()
         */

        // update storage
        NFT = IERC721(nft);
        TOKEN = IERC20(token);
        DELEGATE_REGISTRY = IDelegateRegistry(delegateRegistry);

        depositor = depositor_;
        operator = operator_;

        startTime = startTime_;
        endTime = endTime_;
        emissionPerSecond = emissionPerSecond_;

        allocationPerNft = uint256(allocationPerNft_);        
        totalAllocation = allocationPerNft_ * totalSupply;
    }

    /*//////////////////////////////////////////////////////////////
                                 USERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Users to claim for a single Nft
     * @dev msg.sender must be owner of Nft
     * @param tokenId Nft's tokenId
     */
    function claimSingle(uint256 tokenId) external whenStartedAndBeforeDeadline whenNotPaused {

        // validate ownership
        address ownerOf = NFT.ownerOf(tokenId);
        if(msg.sender != ownerOf) revert InvalidOwner();  
        
        uint256 claimable = _updateLastClaimed(tokenId);

        // update totalClaimed
        totalClaimed += claimable;

        emit ClaimedSingle(msg.sender, tokenId, claimable);
 
        //transfer 
        TOKEN.safeTransfer(msg.sender, claimable);        
    }

    /**
     * @notice Users to claim for multiple Nfts
     * @dev msg.sender must be owner of all Nfts
     * @param tokenIds Nfts' tokenId
     */    
    function claim(uint256[] calldata tokenIds) external whenStartedAndBeforeDeadline whenNotPaused {
        
        // array validation
        uint256 tokenIdsLength = tokenIds.length;
        if(tokenIdsLength == 0) revert EmptyArray(); 


        uint256 totalAmount;
        uint256[] memory amounts = new uint256[](tokenIdsLength);
        for (uint256 i = 0; i < tokenIdsLength; ++i) {

            uint256 tokenId = tokenIds[i];

            // validate ownership: msg.sender == ownerOf
            address ownerOf = NFT.ownerOf(tokenId);
            if(msg.sender != ownerOf) revert InvalidOwner();  

            // update claims
            uint256 claimable = _updateLastClaimed(tokenId);
            
            amounts[i] = claimable;
            totalAmount += claimable;
        }
        
        // update totalClaimed
        totalClaimed += totalAmount;

        // claimed per tokenId
        emit Claimed(msg.sender, tokenIds, amounts);
 
        // transfer all
        TOKEN.safeTransfer(msg.sender, totalAmount);      
    }

    /**
     * @notice Users to claim via delegated hot wallets
     * @dev msg.sender is designated delegate of nfts
     * @param tokenIds Nfts' tokenId
     */  
    function claimDelegated(uint256[] calldata tokenIds) external whenStartedAndBeforeDeadline whenNotPaused {
        
        // array validation
        uint256 tokenIdsLength = tokenIds.length;
        if(tokenIdsLength == 0) revert EmptyArray(); 

        // check delegation on msg.sender
        bytes[] memory data = new bytes[](tokenIdsLength);
        address[] memory owners = new address[](tokenIdsLength);
        for (uint256 i = 0; i < tokenIdsLength; ++i) {
            
            uint256 tokenId = tokenIds[i];

            // get and store nft Owner
            address nftOwner = NFT.ownerOf(tokenId);          
            owners[i] = nftOwner;

            // data for multicall
            data[i] = abi.encodeCall(DELEGATE_REGISTRY.checkDelegateForERC721, 
                        (msg.sender, nftOwner, address(NFT), tokenId, ""));
        }
        
        // if a tokenId is not delegated will return false; as a bool
        bytes[] memory results = DELEGATE_REGISTRY.multicall(data);

        uint256 totalAmount;
        uint256[] memory amounts = new uint256[](tokenIdsLength);

        for (uint256 i = 0; i < tokenIdsLength; ++i) {
            
            // multiCall uses delegateCall: decode return data
            bool isDelegated = abi.decode(results[i], (bool));
            if(!isDelegated) revert InvalidDelegate();

            // update tokenId: storage is updated
            uint256 tokenId = tokenIds[i];
            uint256 claimable = _updateLastClaimed(tokenId);
            
            totalAmount += claimable;
            amounts[i] = claimable;

            // transfer
            TOKEN.safeTransfer(owners[i], claimable);      
        }
       
        // update totalClaimed
        totalClaimed += totalAmount;

        // claimed per tokenId
        emit ClaimedByDelegate(msg.sender, owners, tokenIds, amounts);
 
    }

    /**
     * @notice Users to claim, if nft is locked on some contract (e.g. staking pro)
     * @dev Owner must have enabled module address
     * @param module Nfts' tokenId
     * @param tokenIds Nfts' tokenId
     */  
    function claimViaModule(address module, uint256[] calldata tokenIds) external whenStartedAndBeforeDeadline whenNotPaused {
        if(module == address(0)) revert ZeroAddress();      // in-case someone fat-fingers and allows zero address in modules mapping

        // array validation
        uint256 tokenIdsLength = tokenIds.length;
        if(tokenIdsLength == 0) revert EmptyArray(); 

        // ensure valid module
        if(!modules[module]) revert UnregisteredModule(); 

        // check ownership via moduleCall
        // if not msg.sender is not owner, execution expected to revert within module;
        IModule(module).streamingOwnerCheck(msg.sender, tokenIds);

        uint256 totalAmount;
        uint256[] memory amounts = new uint256[](tokenIdsLength);
        
        for (uint256 i = 0; i < tokenIdsLength; ++i) {

                uint256 tokenId = tokenIds[i];
                uint256 claimable = _updateLastClaimed(tokenId);
                
                totalAmount += claimable;
                amounts[i] = claimable;
        }

        // update totalClaimed
        totalClaimed += totalAmount;

        // claimed per tokenId
        emit ClaimedByModule(module, tokenIds, amounts);

        // transfer 
        TOKEN.safeTransfer(msg.sender, totalAmount);    
    }


    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    //note: safeCast not used in downcasting, since overflowing uint128 is not expected
    function _updateLastClaimed(uint256 tokenId) internal returns(uint256) {
        
        // get data
        Stream memory stream = streams[tokenId];

        // stream previously updated: return
        if(stream.lastClaimedTimestamp == block.timestamp) return(0);

        // stream ended: return
        if(stream.lastClaimedTimestamp == endTime) return(0);

        // stream paused: revert
        if(stream.isPaused) revert StreamPaused();

        // calc claimable
        (uint256 claimable, uint256 currentTimestamp) = _calculateClaimable(stream.lastClaimedTimestamp, stream.claimed);

        /** Note: 
            uint128 max value: 340,282,366,920,938,463,463,374,607,431,768,211,455 [340 undecillion]
            If token supply is >= 340 undecillion, SafeCast should be used
         */

        // update timestamp + claimed        
        stream.lastClaimedTimestamp = uint128(currentTimestamp);
        stream.claimed += uint128(claimable);

        // sanity check: ensure does not exceed max
        if(stream.claimed > allocationPerNft) revert IncorrectClaimable();

        // update storage
        streams[tokenId] = stream;

        return claimable;
    }

    function _calculateClaimable(uint128 lastClaimedTimestamp, uint128 claimed) internal view returns(uint256, uint256) {
        
        // currentTimestamp <= endTime
        uint256 currentTimestamp = block.timestamp > endTime ? endTime : block.timestamp;

        // last tick distributes any remainder, above the usual emissionPerSecond
        if (currentTimestamp == endTime) {

            return (allocationPerNft - claimed, currentTimestamp);

        } else {

            // lastClaimedTimestamp >= startTime
            uint256 lastClaimedTimestamp = lastClaimedTimestamp < startTime ? startTime : lastClaimedTimestamp;

            uint256 timeDelta = currentTimestamp - lastClaimedTimestamp;
            uint256 claimable = emissionPerSecond * timeDelta;

            return (claimable, currentTimestamp);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 OWNER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Owner to update deadline variable
     * @dev By default deadline = 0 
     * @param newDeadline must be after last claim round + 14 days
     */
    function updateDeadline(uint256 newDeadline) external onlyOwner {

        // allow for 14 days buffer: prevent malicious premature ending
        // if the newDeadline is in the past: can insta-withdraw w/o informing users
        uint256 latestTime = block.timestamp > endTime ? block.timestamp : endTime;
        if (newDeadline < (latestTime + 14 days)) revert InvalidNewDeadline();

        deadline = newDeadline;
        emit DeadlineUpdated(newDeadline);
    }

    /**
     * @notice Owner to update depositor address
     * @dev Depositor role allows calling of deposit and withdraw fns
     * @param newDepositor new address
     */
    function updateDepositor(address newDepositor) external onlyOwner {
        
        address oldDepositor = depositor;
        depositor = newDepositor;

        emit DepositorUpdated(oldDepositor, newDepositor);
    }

    /**
     * @notice Enable or disable a module. Only Owner.
     * @dev Module is expected to implement fn 'streamingOwnerCheck(address,uint256[])'
     * @param module Address of contract
     * @param set True - enable | False - disable
     */ 
    function updateModule(address module, bool set) external onlyOwner {
        
        modules[module] = set;

        emit ModuleUpdated(module, set);
    }

    /**
     * @notice Owner to update operator role
     * @dev Can be set to address(0) to eliminiate the role
     * @param newOperator new operator address
     */ 
    function updateOperator(address newOperator) external onlyOwner {
        
        address oldOperator = operator;
        operator = newOperator;

        emit OperatorUpdated(oldOperator, newOperator);
    }

    /**
     * @notice Owner or operator can pause streams
     * @param tokenIds Nfts' tokenId
     */ 
    function pauseStreams(uint256[] calldata tokenIds) external {
        
        // if not operator, check if owner; else revert
        if(msg.sender != operator) {
            _checkOwner();
        }


        // array validation
        uint256 tokenIdsLength = tokenIds.length;
        if(tokenIdsLength == 0) revert EmptyArray(); 

        // pause streams
        for (uint256 i = 0; i < tokenIdsLength; ++i) {

            uint256 tokenId = tokenIds[i];

            streams[tokenId].isPaused = true;
        }

        emit StreamsPaused(tokenIds);
    }

    /**
     * @notice Only owner can unpause streams
     */ 
    function unpauseStreams(uint256[] calldata tokenIds) external onlyOwner {

        // array validation
        uint256 tokenIdsLength = tokenIds.length;
        if(tokenIdsLength == 0) revert EmptyArray(); 

        // unpause streams
        for (uint256 i = 0; i < tokenIdsLength; ++i) {

            uint256 tokenId = tokenIds[i];

            delete streams[tokenId].isPaused;
        }        

        emit StreamsUnpaused(tokenIds);

    }

    /*//////////////////////////////////////////////////////////////
                               DEPOSITOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Depositor to deposit the tokens required for streaming
     * @dev Depositor can fund in totality at once or incrementally, 
            to avoid having to commit a large initial sum
     * @param amount Amount to deposit
     */
    function deposit(uint256 amount) external whenNotPaused {
        if(msg.sender != depositor) revert OnlyDepositor(); 

        // surplus check
        if((totalDeposited + amount) > totalAllocation) revert ExcessDeposit(); 

        totalDeposited += amount;

        emit Deposited(msg.sender, amount);

        TOKEN.safeTransferFrom(msg.sender, address(this), amount);
    }


    /**
     * @notice Depositor to withdraw all unclaimed tokens past the specified deadline
     * @dev Only possible if deadline is non-zero and exceeded
     */
    function withdraw() external whenNotPaused {
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
     * @notice Pause claiming, deposit and withdraw
     * @dev Either the operator or owner can call; no one else
     */
    function pause() external whenNotPaused {
        
        // if not operator, check if owner; else revert
        if(msg.sender != operator) {
            _checkOwner();
        }

        _pause();
    }

    /**
     * @notice Unpause claim. Cannot unpause once frozen
     * @dev Only owner can unpause
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


    modifier whenStartedAndBeforeDeadline() {

        if(block.timestamp <= startTime) revert NotStarted();

        // check that deadline as not been exceeded; if deadline has been defined
        if(deadline > 0) {
            if (block.timestamp > deadline) {
                revert DeadlineExceeded();
            }
        }

        _;
    }
  


    /*//////////////////////////////////////////////////////////////
                                  VIEW
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns claimable amount for specified tokenId
     * @param tokenId Nft's tokenId
     */ 
    function claimable(uint256 tokenId) external view returns(uint256) {
        
        // get data
        Stream memory stream = streams[tokenId];

        // nothing to claim
        if(stream.lastClaimedTimestamp == block.timestamp) return(0);

        // calc. claimable
        (uint256 claimable, /*uint256 currentTimestamp*/) = _calculateClaimable(stream.lastClaimedTimestamp, stream.claimed);

        return claimable;
    }

}
