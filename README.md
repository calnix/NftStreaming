# NFT Streaming

NFT holders are beneficiaries of some token rewards that will be streamed to them over the course of a defined period.

- Token and NFT addresses are to be defined.
- Period is defined by startTime and endTime variables.
- NFTs can be delegated via https://delegate.xyz

All NFTs get the same amount streamed.

## Delegation of NFTs

- Expect users to be delegating via the function: `delegateAll(hotWallet, bytes32(0), true)` or `delegateERC721(hotWallet, address(mocaNft), tokenId, bytes32(0), true)`
- Hence, the delegation check is done via: `checkDelegateForERC721(hw, cw, nftAddress, tokenId, "")`

## Roles

- users
- depositor
- owner
- operator

### Operator role

- risky eoa wallet
- pause contract
- pause specific stream

Operator can pause, but not unpause. This is to prevent malicious unpausing, in the event the owner initially paused the contract.
Pausing the contract or specific streams will not affect the amount streamed, so as long users can claim before the deadline is exceeded.

## Claiming of Streams

Claim functions will be segregated as per NFT location. E.g.:

- `claim`: if NFTs are held by calling EOA (i.e. msg.sender)
- `claimSingle`: if msg.sender has only 1 NFT
- `claimDelegated`: if NFTs are delegated
- `claimViaModule`: if NFTs are on some other contract like staking pro

User will call a different fn based on where his NFTs are located. However, a user cannot claim across multiple venues at once.

All the claims are multiple claims except for the `claimSingle`; which is offered as ~50% of user base have 1 NFT.

### Pausing a stream

Contract allows a specific stream to be paused indefinitely.

- Useful in scenarios where some users' NFTs have been compromised and extracted.
- Pausing prevents the hacker from benefitting from the stream.
- Indefinitely paused streams would subsequently be unclaimable once the deadline (if defined) has been exceeded.

## Modules

Modules allow integrations with contracts that might be deployed in the future, which would involve the NFTs in some fashion.
For example, an NFT staking contract.

By adding either that contract or a intermediate helper contract, users can claim the streams they are owed, although they may have committed their NFT to a staking pool.

- Users will claim via `claimViaModule`
- Owner can allow/block modules via `updateModule`

Module contracts are expected to implement the view function `streamingOwnerCheck(address user, uint256[] tokenIds)`.
The IModule interface enforces it to be a view function.

## Financing

### Deposit

- The specified depositor address can call `deposit` to finance the needed tokens for streaming.
- Depositor cannot deposit in excess of totalAllocation, as that would be surplus.
- Depositor can deposit tokens incrementally over some period (i.e. monthly), to ensure contract is well supplied with needed tokens for stream claims.
-- Not required to deposit in full for the entire period upfront.

Only the contract owner can change this depositor address; if needed.

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

### updateDeadline

The deadline variable can only be minimally a value 14 days past the defined endTime.

```solidity
        if (newDeadline < endTime + 14 days) revert InvalidNewDeadline();
```

## Emergency

1. Pause and ascertain situation
2. If contract proved to be vulnerable, freeze it.
3. Owner to call `emergencyExit`

Owner can set a target address to receive the emergency withdrawal of tokens.

Withdrawal amount is reference via token contract's balanceOf method as we cannot be sure if `totalDeposited` and `totalClaimed` remain accurate at such a time.

## Others

1. `_updateLastClaimed`

- downcasts currentTimestamp and claimable to uint128 without SafeCast
- uint128 max value: 340,282,366,920,938,463,463,374,607,431,768,211,455 [340 undecillion]
- expectation is that that neither token supply nor timestamp will exceed this value
