// SPDX-License-Identifier: GPL

pragma solidity ^0.8.0;

interface IYapeswapCallee {
    function yapeswapCall(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}
