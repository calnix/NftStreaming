# Testing Suite

## Nft holders

- userA: tokenId 0
- userB: tokenId 1
- userC: tokenId 2,3

## Stream params

        startTime = 2;
        endTime = 12;
        allocationPerNft = 10 ether;
        totalAllocation = 10 ether * 4;

40 ether deposited into contract by depositor address.

## Timeline

- t0: streaming contract is deployed and tested.

- t1: depositor calls `deposit` on streaming contract; deposits required tokens.

- t2: streaming started; startTime=2. However, users cannot call claim or claimMultiple.

- t3: users call claim functions;
        - 1 second of emissions claimable per nft.
        - 3 units of eps streamed in total.

- t5: 2 units of eps streamed per nft, since t3.
        - 2 units claimable by userA
        - 4 units claimable by userC
        - 6 claimable in total

- t12: streaming ended; endTime = 12 *[StateStreamEnded]*
        - userA has previously claimed: 3 units
        - userC has previously claimed: 6 units
        - each nft has 7 units of eps claimable
        - userA can claim 7 eps on tokenId 0
        - userC can claim 7 eps on tokenId 2,3; total of 14

- t12 + 2 days: 2 days after endTime *[StateStreamEndedPlusTwoDays]*
        - users should be able to still claim after streaming has ended.
        - withdraw is not possible, as deadline as not been defined.
        - deadline can only be updated such that its a future date, minimally 14 days from now or endTime; whichever more recent.
        - only owner can update the deadline
        - *deadline updated to endTime + 17 days*

- t12 + 17 days: 17 days after endTime *[StateBeforeDeadline]*
        - deadline check ensures that no claiming can be done **after** the deadline.
        - on the deadline time itself, claiming it possible.

- t12 + 18 days: 18 days after endTime *[StateAfterDeadline]*
        - since deadline has been exceeded, no claiming is possible.
        - early withdrawal before deadline is not possible, but once exceeded is allowed.

## NftStreaming.t.sol

Tests core functionality through `claimSingle` and `claim`. Uses mocks for nft and tokens.

## NftStreamingClaimModule.t.sol

Builds on NftStreaming.t.sol to test core functionality through `claimViaModule`. Uses mocks for nft and tokens.

UserB locks their nfts at t3 and only claims via `claimViaModule` from t12 onwards.
UserC lock 1 of 2 nfts at t3, claiming of the locked nft at t5, and then subsequently unlocking it.

- t3: both userA and C claim through `claimSingle` and `claim`.
        - userB locks their nft on module. does not claim.
        - userC locks an nft on a module contract, retaining 1 nft on self; after claiming.

- t5: userC has 1 nft on self, another nft on an external module contract
        - test that userA is unaffected by any module related operations.
        - test that userC can claim the same, for both nfts.
        - after claiming userC unlocks his nft; hereinafter both nfts are on self.

- t12: streaming ended; endTime = 12 *[StateStreamEnded]*
        - test that userA is unaffected by any module related operations.
        - test that userC can claim for both nfts on self via `claimMultiple`
        - test that userB can claim full amount via `claimViaModule`

- t12 + 2 days: 2 days after endTime *[StateStreamEndedPlusTwoDays]*
        - test that userA is unaffected by any module related operations.
        - test that userC can claim for both nfts on self via `claimMultiple`
        - test that userB can claim full amount via `claimViaModule`

- t12 + 17 days: 17 days after endTime *[StateBeforeDeadline]*
        - test that userA is unaffected by any module related operations.
        - test that userC can claim for both nfts on self via `claimMultiple`
        - test that userB can claim full amount via `claimViaModule`

- t12 + 18 days: 18 days after endTime *[StateAfterDeadline]*
        - test `claimViaModule` reverts

## NftStreamingClaimDelegated.t.sol

Builds on NftStreaming.t.sol to test core functionality through `claimDelegated`.
Forks mainnet for delegationV2 and mocaNft. Tokens are mocked.

## NftStreamingPausingStreams.t.sol

Tests functionality of pausing individual streams.

- t5: tokenIds 1,2,3 are paused; corresponding to userB and userC
- t12: tokenIds 1,2,3 are unpaused