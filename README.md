## NFT Streaming

NFT holders are beneficiaries of some token rewards that will be streamed to them over the course of a defined period.

## Claiming of Streams

Claim functions will be segregated as per NFT location. E.g.

- claim: if NFT is held within wallet
- claimDelegated: if NFTs are delegated
- claimViaModule: if NFTs are on some other contract like staking pro

User will call a different fn based on where his NFTs are located. All functions will allow for claiming of multiple NFTs at once.
However, a user cannot claim across multiple venues at once.


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

- We expect users are delegating via the function: `delegateAll(hotWallet, bytes32(0), true)`
- Therefore frm the contract perspective we'll just check via `checkDelegateForERC721(hw1, cw, nftAddress, tokenId, "")`
