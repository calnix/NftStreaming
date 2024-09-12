// SPDX-License-Identifier: MIT 
pragma solidity 0.8.24;

import {IERC721} from "./../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

import {SafeERC20, IERC20} from "./../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";

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
    IDelegateRegistry public DELEGATE_REGISTRY;  // https://docs.delegate.xyz/technical-documentation/delegate-registry/contract-addresses

    // total supply of NFTs
    uint256 public constant totalSupply = 8_888;
    
    // stream period
    uint256 public immutable startTime;
    uint256 public immutable endTime;
    
    // allocation
    uint256 public immutable allocationPerNft;
    uint256 public immutable emissionPerSecond; // per NFT
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
     * @param isPaused Is the stream paused 
     */
    struct Stream {
        // slot0
        uint128 claimed;
        uint128 lastClaimedTimestamp;
        // slot 1
        bool isPaused;
    }

    mapping(uint256 tokenId => Stream stream) public streams;
    mapping(address module => bool isRegistered) public modules;    // Trusted contracts to call

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
        uint256 period = endTime_ - startTime_; 
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

    function claimSingle(uint256 tokenId) external payable whenStartedAndBeforeDeadline whenNotPaused {
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
        
        uint256 claimable = _updateLastClaimed(tokenId);

        // update totalClaimed
        totalClaimed += claimable;

        emit Claimed(msg.sender, claimable);
 
        //transfer 
        TOKEN.safeTransfer(msg.sender, claimable);        
    }

    // if nfts in wallet
    function claim(uint256[] calldata tokenIds) external payable whenStartedAndBeforeDeadline whenNotPaused {
        
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

    // if nft is delegated
    function claimDelegated(uint256[] calldata tokenIds) external payable whenStartedAndBeforeDeadline whenNotPaused {
        
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
        
        // update totalClaimed
        totalClaimed += totalAmount;

        // claimed per tokenId
        emit ClaimedByDelegate(msg.sender, owners, tokenIds, amounts);
 
        // transfer 
        for (uint256 i = 0; i < tokenIdsLength; ++i) {
            
            address owner = owners[i];    
            uint256 amount = amounts[i];

            TOKEN.safeTransfer(owner, amount);      
        }

    }

/*
    // note: remove and update NftLocker.sol
    function claimLocked(uint256[] calldata tokenIds) external payable whenStartedAndBeforeDeadline whenNotPaused {
        
        // array validation
        uint256 tokenIdsLength = tokenIds.length;
        if(tokenIdsLength == 0) revert EmptyArray(); 

        // check if locked by msg.sender
        for (uint256 i = 0; i < tokenIdsLength; ++i) {

            uint256 tokenId = tokenIds[i];

            // note: modify NftLocker - add a view function that takes in `uint256[] tokenIds` as param
            // view function will verify ownership
            // save on x-contract calls
            // if(locker.nfts(tokenId) != msg.sender) revert InvalidOwner(); 
        }



    }
*/
    // if nft is on some contract (e.g. staking pro)
    function claimViaModule(address module, uint256[] calldata tokenIds) external payable whenStartedAndBeforeDeadline whenNotPaused {
        if(module == address(0)) revert ZeroAddress();      // in-case someone fat-fingers and allows zero address in modules mapping

        // array validation
        uint256 tokenIdsLength = tokenIds.length;
        if(tokenIdsLength == 0) revert EmptyArray(); 

        // ensure valid module
        if(!modules[module]) revert UnregisteredModule(); 

        // check ownership via moduleCall
        bytes memory data = abi.encodeWithSignature("streamingOwnerCheck(address,uint256[])", msg.sender, tokenIds);
        (bool success, /*bytes memory result*/) = module.staticcall(data);

        // if not msg.sender is not owner, execution expected to revert within module;
        // success == false
        if(!success) revert ModuleCheckFailed();       

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

    function _updateLastClaimed(uint256 tokenId) internal returns(uint256) {
        
        // get data
        Stream memory stream = streams[tokenId];

        // stream previously updated: return
        if(stream.lastClaimedTimestamp == block.timestamp) return(0);

        // stream ended: return
        if(stream.lastClaimedTimestamp == endTime) return(0);

        //note: check paused
        if(stream.isPaused) revert StreamPaused();

        //calc claimable
        (uint256 claimable, uint256 currentTimestamp) = _calculateClaimable(stream.lastClaimedTimestamp);

        // sanity check: ensure does not exceed max
        if(claimable > allocationPerNft) revert IncorrectClaimable();

        // update timestamp + claimed
        stream.lastClaimedTimestamp = uint128(currentTimestamp);
        stream.claimed += uint128(claimable);

        // update storage
        streams[tokenId] = stream;

        return claimable;
    }

    function _calculateClaimable(uint128 lastClaimedTimestamp) internal view returns(uint256, uint256) {
        
        // currentTimestamp <= endTime
        uint256 currentTimestamp = block.timestamp > endTime ? endTime : block.timestamp;
        // lastClaimedTimestamp >= startTime
        uint256 lastClaimedTimestamp = lastClaimedTimestamp < startTime ? startTime : lastClaimedTimestamp;


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

    /**
     * @notice
     * @dev Add or remove a module
     */ 
    function updateModule(address module, bool set) external onlyOwner {
        
        modules[module] = set;

        emit ModuleUpdated(module, set);
    }

    function pauseStreams(uint256[] calldata tokenIds) external onlyOwner {
        
        // array validation
        uint256 tokenIdsLength = tokenIds.length;
        if(tokenIdsLength == 0) revert EmptyArray(); 

        // pause streams
        for (uint256 i = 0; i < tokenIdsLength; ++i) {

            uint256 tokenId = tokenIds[i];

            Stream memory stream = streams[tokenId];
            stream.isPaused = true;
        }

        emit StreamsPaused(tokenIds);
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
    function deposit(uint256 amount) external {
        if(msg.sender != depositor) revert OnlyDepositor(); 

        // surplus check
        if((totalDeposited + amount) > totalAllocation) revert ExcessDeposit(); 

        totalDeposited += amount;

        emit Deposited(msg.sender, amount);

        TOKEN.safeTransferFrom(msg.sender, address(this), amount);
    }


    /**
     * @notice Depositor to withdraw all unclaimed tokens past the specified deadline
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



}
