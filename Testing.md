Operator role
- risky eoa wallet
- pause contract
- pause specific stream

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

- t3: users can call claim functions;
        - 1 second of emissions claimable per nft.
        - 3 units of eps streamed in total.

- t5: 2 units of eps streamed per nft, since t3.
        - 2 units claimable by userA
        - 4 units claimable by userC
        - 6 claimable in total

- t12: streaming ended; endTime = 12.
        - userA has previously claimed: 3 units
        - userC has previously claimed: 6 units
        - each nft has 7 units of eps claimable
        - userA can claim 7 eps on tokenId 0
        - userC can claim 7 eps on tokenId 2,3; total of 14

- t12 + 2 days: 2 days after endTime
        - users should be able to still claim after streaming has ended.
        - withdraw is not possible, as deadline as not been defined.
        - deadline can only be updated such that its a future date, minimally 14 days from now or endTime; whichever more recent.
        - only owner can update the deadline
        - *deadline updated to endTime + 17 days*

- t12 + 17 days: 17 days after endTime *[on deadline]*
        - deadline check ensures that no claiming can be done **after** the deadline.
        - on the deadline time itself, claiming it possible.

- t12 + 18 days: 18 days after endTime *[deadline exceeded]*
        - since deadline has been exceeded, no claiming is possible.
        - early withdrawal before deadline is not possible, but once exceeded is allowed.

## NftStreaming.t.sol

Tests core functionality through `claimSingle` and `claim`. Uses mocks for nft and tokens.

## NftStreamingClaimDelegated.t.sol

Tests core functionality through `claimDelegated`.

## NftStreamingClaimModule.t.sol

Tests core functionality through `claimViaModule`.

## NftStreamingPausingStreams.t.sol

Tests functionality of pausing individual streams by owner.