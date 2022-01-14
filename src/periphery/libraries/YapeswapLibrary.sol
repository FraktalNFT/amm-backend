// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../core/interfaces/IYapeswapPair.sol";
import "openzeppelin/utils/math/SafeMath.sol";

library YapeswapLibrary {
    using SafeMath for uint256;

    function alphabetical(
        address tokenA,
        uint256 tokenAsub,
        address tokenB,
        uint256 tokenBsub
    ) private pure returns (bool is_alphabetical) {
        // Take the sum of token a and b for deciding ordering
        uint256 tokenAsum = uint256(uint160(tokenA)) + tokenAsub;
        uint256 tokenBsum = uint256(uint160(tokenB)) + tokenBsub;
        if (tokenAsum < tokenBsum) {
            is_alphabetical = true;
        } else {
            is_alphabetical = false;
        }
    }

    function ordered(
        address tokenA,
        uint256 tokenAsub,
        address tokenB,
        uint256 tokenBsub
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
            tokenAsub,
            tokenB,
            tokenBsub
        )
            ? (tokenA, tokenAsub, tokenB, tokenBsub)
            : (tokenB, tokenBsub, tokenA, tokenAsub);
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(
        address tokenA,
        uint256 tokenAsub,
        address tokenB,
        uint256 tokenBsub
    )
        public
        pure
        returns (
            address token0,
            uint256 token0sub,
            address token1,
            uint256 token1sub
        )
    {
        // We have to check both token here because of erc-1155 subids
        require(tokenA != address(0), "Yapeswap: ZERO_ADDRESS");
        require(tokenB != address(0), "Yapeswap: ZERO_ADDRESS");

        // Ensure the token are not identical
        if (tokenAsub == tokenBsub) {
            require(tokenA != tokenB, "Yapeswap: IDENTICAL_TOKENS");
        }

        // Ternary operator for ordering
        (token0, token0sub, token1, token1sub) = ordered(
            tokenA,
            tokenAsub,
            tokenB,
            tokenBsub
        );
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(
        address factory,
        address tokenA,
        uint256 tokenAsub,
        address tokenB,
        uint256 tokenBsub
    ) internal pure returns (address pair) {
        (
            address token0,
            uint256 token0sub,
            address token1,
            uint256 token1sub
        ) = sortTokens(tokenA, tokenAsub, tokenB, tokenBsub);
        // TODO(Recalculate pair init code)
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(
                                abi.encodePacked(
                                    token0,
                                    token0sub,
                                    token1,
                                    token1sub
                                )
                            ),
                            hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f" // init code hash
                        )
                    )
                )
            )
        );
    }

    // fetches and sorts the reserves for a pair
    function getReserves(
        address factory,
        address tokenA,
        uint256 tokenAsub,
        address tokenB,
        uint256 tokenBsub
    ) internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0, , , ) = sortTokens(
            tokenA,
            tokenAsub,
            tokenB,
            tokenBsub
        );
        (uint256 reserve0, uint256 reserve1, ) = IYapeswapPair(
            pairFor(factory, tokenA, tokenAsub, tokenB, tokenBsub)
        ).getReserves();
        (reserveA, reserveB) = tokenA == token0
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 amountB) {
        require(amountA > 0, "YapeswapLibrary: INSUFFICIENT_AMOUNT");
        require(
            reserveA > 0 && reserveB > 0,
            "YapeswapLibrary: INSUFFICIENT_LIQUIDITY"
        );
        amountB = amountA.mul(reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "YapeswapLibrary: INSUFFICIENT_INPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "YapeswapLibrary: INSUFFICIENT_LIQUIDITY"
        );
        uint256 amountInWithFee = amountIn.mul(997);
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "YapeswapLibrary: INSUFFICIENT_OUTPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "YapeswapLibrary: INSUFFICIENT_LIQUIDITY"
        );
        uint256 numerator = reserveIn.mul(amountOut).mul(1000);
        uint256 denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(
        address factory,
        uint256 amountIn,
        address[] memory tokenPath,
        uint256[] memory subid_path
    ) internal view returns (uint256[] memory amounts) {
        require(tokenPath.length >= 2, "YapeswapLibrary: INVALID_PATH");
        require(tokenPath.length == subid_path.length);
        amounts = new uint256[](tokenPath.length);
        amounts[0] = amountIn;
        for (uint256 i; i < tokenPath.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(
                factory,
                tokenPath[i],
                subid_path[i],
                tokenPath[i + 1],
                subid_path[i + 1]
            );
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(
        address factory,
        uint256 amountOut,
        address[] memory tokenPath,
        uint256[] memory subid_path
    ) internal view returns (uint256[] memory amounts) {
        require(tokenPath.length >= 2, "YapeswapLibrary: INVALID_PATH");
        require(tokenPath.length == subid_path.length);
        amounts = new uint256[](tokenPath.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = tokenPath.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(
                factory,
                tokenPath[i - 1],
                subid_path[i - 1],
                tokenPath[i],
                subid_path[i]
            );
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}
