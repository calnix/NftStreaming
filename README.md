## On-Chain Considerations

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


https://www.notion.so/animocabrands/Moca-NFT-Token-Vesting-f0dda74929c1438baa75c0e62ea5f9cd?pvs=4