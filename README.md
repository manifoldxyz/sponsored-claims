# Sponsored Claims

*Note: This is a late-night rambling trying to explain the concept. Please forgive me lol.*

Allow for creators to set up claims and sell their work without having to ever touch the blockchain. In order to accomplish this there are two parts to this approach:
1. Get the creator a Manifold Creator contract
2. Set up a claim on that contract

Because we are operating under the assumption the creator does not have a wallet, the creator MUST be given a reserved ownership account via [EIP-6981](https://eips.ethereum.org/EIPS/eip-6981) that will be used as their on-chain identifier. This will allow them to claim ownership of their creator contract at any point in the future.

At a high level, we use CREATE2 to generate deterministic contract addresses tied to the creator's ROA. Anyone can deploy this contract without harm, however in most cases a specific third-party should deploy this contract -- the sponsor. The sponsor's role is to be the bridge by taking creators' off-chain works and initializing claims on-chain. With this process, the sponsor will be entitled to a specific percentage of the claim sales via a royalty splitter contract.

The main goal of sponsored claims is to reduce the friction to onboard new creators by not requiring wallets. Sponsors should be incentivized to bring these configurations on-chain if they believe they can turn a profit on it: `Gas cost < Expected Mints * Mint Cost * Sponsor Fee`. The sponsor fee can be configurable by the creator, so that a higher fee can be used as an incentive to put it on-chain.
