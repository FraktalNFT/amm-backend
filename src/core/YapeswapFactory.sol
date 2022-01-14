// SPDX-License-Identifier: GPL

pragma solidity ^0.8.0;

import "./interfaces/IYapeswapFactory.sol";
import "./YapeswapPair.sol";
import "openzeppelin/interfaces/IERC1155.sol";

contract YapeswapFactory is IYapeswapFactory {
    address public override(IYapeswapFactory) feeTo;
    address public override(IYapeswapFactory) feeToSetter;

    mapping(bytes32 => address) pairMap;
    address[] public override(IYapeswapFactory) allPairs;

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength()
        external
        view
        override(IYapeswapFactory)
        returns (uint256)
    {
        return allPairs.length;
    }

    function alphabetical(
        address tokenA,
        uint256 tokenASubId,
        address tokenB,
        uint256 tokenBSubId
    ) private pure returns (bool is_alphabetical) {
        // Take the sum of token a and b for deciding ordering
        uint256 tokenAsum = uint256(uint160(tokenA)) + tokenASubId;
        uint256 tokenBsum = uint256(uint160(tokenB)) + tokenBSubId;
        if (tokenAsum < tokenBsum) {
            is_alphabetical = true;
        } else {
            is_alphabetical = false;
        }
    }

    function ordered(
        address tokenA,
        uint256 tokenASubId,
        address tokenB,
        uint256 tokenBSubId
    )
        private
        pure
        returns (
            address token0,
            uint256 token0sub,
            address token1,
            uint256 token1sub
        )
    {
        (token0, token0sub, token1, token1sub) = alphabetical(
            tokenA,
            tokenASubId,
            tokenB,
            tokenBSubId
        )
            ? (tokenA, tokenASubId, tokenB, tokenBSubId)
            : (tokenB, tokenBSubId, tokenA, tokenASubId);
    }

    function getPair(
        address tokenA,
        uint256 tokenASubId,
        address tokenB,
        uint256 tokenBSubId
    ) external view override(IYapeswapFactory) returns (address pair) {
        (
            address token0,
            uint256 token0sub,
            address token1,
            uint256 token1sub
        ) = ordered(tokenA, tokenASubId, tokenB, tokenBSubId);
        pair = pairMap[
            keccak256(abi.encodePacked(token0, token0sub, token1, token1sub))
        ];
    }

    function createPair(
        address tokenA,
        uint256 tokenASubId,
        address tokenB,
        uint256 tokenBSubId
    ) external override(IYapeswapFactory) returns (address pair) {
        // We have to check both token here because of erc-1155 subids
        require(tokenA != address(0), "Yapeswap: ZERO_ADDRESS");
        require(tokenB != address(0), "Yapeswap: ZERO_ADDRESS");

        // Ensure the token are not identical
        if (tokenASubId == tokenBSubId) {
            require(tokenA != tokenB, "Yapeswap: IDENTICAL_TOKENS");
        }

        // Ternary operator for ordering
        (
            address token0,
            uint256 token0sub,
            address token1,
            uint256 token1sub
        ) = ordered(tokenA, tokenASubId, tokenB, tokenBSubId);

        // Generate a salt
        bytes32 salt = keccak256(
            abi.encodePacked(token0, token0sub, token1, token1sub)
        );

        // Ensure that the pair doesn't already exist
        require(pairMap[salt] == address(0), "Yapeswap: PAIR_EXISTS");

        // Create pair
        bytes memory bytecode = type(YapeswapPair).creationCode;
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IYapeswapPair(pair).initialize(token0, token0sub, token1, token1sub);
        pairMap[salt] = pair;
        allPairs.push(pair);
        emit PairCreated(
            token0,
            token0sub,
            token1,
            token1sub,
            pair,
            allPairs.length
        );
    }

    function setFeeTo(address _feeTo) external override(IYapeswapFactory) {
        require(msg.sender == feeToSetter, "Yapeswap: FORBIDDEN");
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter)
        external
        override(IYapeswapFactory)
    {
        require(msg.sender == feeToSetter, "Yapeswap: FORBIDDEN");
        feeToSetter = _feeToSetter;
    }
}
