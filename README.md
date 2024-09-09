# NFT Streaming

NFT holders are beneficiaries of some token rewards that will be streamed to them over the course of a defined period.

- Token and NFT addresses are to be defined.
- Period is defined by startTime and endTime variables.
- NFTs can be delegated via https://delegate.xyz 

## Roles

- users
- depositor
- owner

## Claiming of Streams

Claim functions will be segregated as per NFT location. E.g.:

- claim: if NFTs are held by calling EOA (i.e. msg.sender)
- claimDelegated: if NFTs are delegated
- claimViaModule: if NFTs are on some other contract like staking pro

User will call a different fn based on where his NFTs are located. All functions will allow for claiming on multiple NFTs at once.
However, a user cannot claim across multiple venues at once.

### Pausing a stream

Contract allows a specific stream to be paused indefinitely.

- Useful in scenarios where some users' NFTs have been compromised and extracted.
- Pausing prevents the hacker from benefitting from the stream.
- Indefinitely paused streams would subsequently be unclaimable once the deadline (if defined) has been exceeded.

> consider if implementing pausing is really necessary

## Modules

Modules allow integrations with contracts that might be deployed in the future, which would involve the NFTs in some fashion.
For example, an NFT staking contract.

By adding either that contract or a intermediate helper contract, users can claim the streams they are owed, although they may have committed their NFT to a staking pool.

- Users will claim via `claimViaModule`
- Owner can allow/block modules via `updateModule`

Module contracts are expected to implement the function `streamingOwnerCheck(address user, uint256[] tokenIds)`, which will be called via staticCall.

The data passed via staticcall will be:

```solidity
        bytes memory data = abi.encodeWithSignature("streamingOwnerCheck(address,uint256[])", msg.sender, tokenIds);
        
        (bool success, /*bytes memory result*/) = module.staticcall(data);
        if(!success) revert ModuleCheckFailed();       
```

`streamingOwnerCheck` in a module is expected to revert if the msg.sender address that was passed does not match any of the tokenIds registered owner addresses.

Since low-level calls fail silently, we have to check that `success` is not false.

## Financing

### Deposit

- The specified depositor address can call `deposit` to finance the needed tokens for streaming.
- Depositor cannot deposit in excess of totalAllocation, as that would be surplus.
- Depositor can deposit tokens incrementally over some period (i.e. monthly), to ensure contract is well supplied with needed tokens for stream claims.
-- Not required to deposit in full for the entire period upfront.

Only the contract can change this depositor address; if needed.

### Withdraw

- Depositor is able to withdraw unclaimed tokens once the specified deadline has been exceeded; `withdraw`.
- If deadline has not been defined, withdrawal is disabled.
- Withdraw amount is calculated as per storage variables: `totalDeposited - totalClaimed`, to disregard random transfers.

## Owner functions

- updateDeadline: to specify and update the `deadline` variable
- updateDepositor: to update the depositor address
- updateModule: to update a module's permission
- pauseStreams: to pause an array of streams
- pause: pause contract; all claims paused
- unpause: unpause contract

> Add operator role? 

## Emergency 

**Admin:**

*(pause → freeze → emergency withdraw)*

- Admin can `pause` the token claims
    - *Implies that it can be unpaused and everything continue normally*
- Admin can `freeze` the token contract
    - *Implies a one-way action - cannot be reversed*
- Admin can `(emergency) withdraw` $MOCA tokens from the token distributor contract
- Admin can `withdraw unclaimed` $MOCA tokens from the token distributor contract `60 days` after end timestamp
- Admin can `top up` $MOCA tokens to the token distributor contract

**Moca NFT Holder:**

- Ability to claim vested $MOCA against Moca NFTs that are staked in Staking Pro
- Ability to claim vested $MOCA from `single NFT / multiple NFTs / All NFTs` in a single transaction
    - Claim based on where the NFT is residing (staking OR hot wallet)
- Ability to claim vested $MOCA using delegated wallets
    - *delegate.xyz*
- Vested tokens will be streamed every second and available for claiming

Points to consider:

- Limits on claiming from x NFTs (due to batching)???
- Claiming from hot wallet, staking and delegation together??

## Delegation of NFTs

- Expect users to be delegating via the function: `delegateAll(hotWallet, bytes32(0), true)`
- Hence, the delegation check is done via: `checkDelegateForERC721(hw1, cw, nftAddress, tokenId, "")`
