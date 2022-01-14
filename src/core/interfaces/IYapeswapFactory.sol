// SPDX-License-Identifier: GPL

pragma solidity ^0.8.0;

interface IYapeswapFactory {
    event PairCreated(
        address indexed token0,
        uint256 token0sub,
        address indexed token1,
        uint256 token1sub,
        address pair,
        uint256
    );

    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);

    function getPair(
        address tokenA,
        uint256 tokenAsub,
        address tokenB,
        uint256 tokenBsub
    ) external view returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(
        address tokenA,
        uint256 tokenAsub,
        address tokenB,
        uint256 tokenBsub
    ) external returns (address pair);

    function setFeeTo(address) external;

    function setFeeToSetter(address) external;
}
