# Yapeswap Contracts

This repo comprises the contracts and tests for Yapeswap.

Testing is done with dapptools. Prettier, solhint, slither, can be used to perform further static analysis on the 
project, but are not implemented in the CI pipeline.

# Design

This is a fork of Uniswap v2, updated to solidity 8, which supports pairings of ERC-1155 token ids with other ERC-1155 
token ids, or ERC20s, in addition to ERC-20 to ERC-20 pairings.

# Note

The core contracts are heavily tested, the periphery could benefit from additional testing and audit.