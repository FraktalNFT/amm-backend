// SPDX-License-Identifier: GPL

pragma solidity ^0.8.0;

import "./YapeswapERC20.sol";
import "openzeppelin/utils/ERC20TransferHelper.sol";
import "openzeppelin/utils/introspection/ERC165Checker.sol";
import "openzeppelin/utils/math/Math.sol";
import "../math/Sqrt.sol";
import "../math/UQ112x112.sol";
import "openzeppelin/interfaces/IERC20.sol";
import "openzeppelin/interfaces/IERC1155.sol";
import "./interfaces/IYapeswapFactory.sol";
import "./interfaces/IYapeswapCallee.sol";
import "./interfaces/IYapeswapPair.sol";
import "openzeppelin/token/ERC1155/utils/ERC1155Holder.sol";
import "openzeppelin/utils/math/SafeMath.sol";

contract YapeswapPair is IYapeswapPair, YapeswapERC20, ERC1155Holder {
    // TODO(Optimize gas by using a memory struct for token info)
    using SafeMath for uint256;
    using UQ112x112 for uint224;

    uint256 public constant override(IYapeswapPair) MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR =
        bytes4(keccak256(bytes("transfer(address,uint256)")));

    address public override(IYapeswapPair) factory;

    address public override(IYapeswapPair) token0;
    bool private token0is1155;
    address public override(IYapeswapPair) token1;
    bool private token1is1155;

    uint256 public override(IYapeswapPair) token0sub;
    uint256 public override(IYapeswapPair) token1sub;

    uint112 private reserve0; // uses single storage slot, accessible via getReserves
    uint112 private reserve1; // uses single storage slot, accessible via getReserves
    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint256 public override(IYapeswapPair) price0CumulativeLast;
    uint256 public override(IYapeswapPair) price1CumulativeLast;
    uint256 public override(IYapeswapPair) kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "Yapeswap: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function getReserves()
        public
        view
        override(IYapeswapPair)
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        )
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    constructor() {
        factory = msg.sender;
    }

    // called once by the factory at time of deployment
    function initialize(
        address _token0,
        uint256 _token0sub,
        address _token1,
        uint256 _token1sub
    ) external override(IYapeswapPair) {
        require(msg.sender == factory, "Yapeswap: FORBIDDEN");
        // sufficient check
        token0 = _token0;
        token0sub = _token0sub;
        token0is1155 = ERC165Checker.supportsInterface(token0, 0xd9b67a26);
        token1 = _token1;
        token1is1155 = ERC165Checker.supportsInterface(token1, 0xd9b67a26);
        token1sub = _token1sub;
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1
    ) private {
        require(
            balance0 <= type(uint112).max && balance1 <= type(uint112).max,
            "Yapeswap: OVERFLOW"
        );
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;
        // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast +=
                uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) *
                timeElapsed;
            price1CumulativeLast +=
                uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) *
                timeElapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _mintFee(uint112 _reserve0, uint112 _reserve1)
        private
        returns (bool feeOn)
    {
        address feeTo = IYapeswapFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint256 _kLast = kLast;
        // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = Sqrt.sqrt(uint256(_reserve0).mul(_reserve1));
                uint256 rootKLast = Sqrt.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint256 numerator = totalSupply.mul(rootK.sub(rootKLast));
                    uint256 denominator = rootK.mul(5).add(rootKLast);
                    uint256 liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to)
        external
        override(IYapeswapPair)
        lock
        returns (uint256 liquidity)
    {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        // gas savings
        uint256 balance0 = token0is1155
            ? IERC1155(token0).balanceOf(address(this), token0sub)
            : IERC20(token0).balanceOf(address(this));
        uint256 balance1 = token1is1155
            ? IERC1155(token1).balanceOf(address(this), token1sub)
            : IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0.sub(_reserve0);
        uint256 amount1 = balance1.sub(_reserve1);

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply;
        // TODO(This seems like a bad idea for token fractions)
        // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Sqrt.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
            _mint(address(0), MINIMUM_LIQUIDITY);
            // permanently lock the first MINIMUM_LIQUIDITY token
        } else {
            liquidity = Math.min(
                amount0.mul(_totalSupply) / _reserve0,
                amount1.mul(_totalSupply) / _reserve1
            );
        }
        require(liquidity > 0, "Yapeswap: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0).mul(reserve1);
        // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to)
        external
        override(IYapeswapPair)
        lock
        returns (uint256 amount0, uint256 amount1)
    {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        // gas savings from loading repeat storage access to stack
        address _token0 = token0;
        address _token1 = token1;

        // Get balances
        uint256 balance0 = token0is1155
            ? IERC1155(_token0).balanceOf(address(this), token0sub)
            : IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = token1is1155
            ? IERC1155(_token1).balanceOf(address(this), token1sub)
            : IERC20(_token1).balanceOf(address(this));

        // Get liquidity
        uint256 liquidity = balanceOf[address(this)];

        // Accrue fees
        bool feeOn = _mintFee(_reserve0, _reserve1);

        // Get totalSupply
        uint256 _totalSupply = totalSupply;
        // gas savings, must be defined here since totalSupply can update in _mintFee

        // Get liquidity amounts
        amount0 = liquidity.mul(balance0) / _totalSupply;
        // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(balance1) / _totalSupply;
        // using balances ensures pro-rata distribution

        // Burn liquidity
        require(
            amount0 > 0 && amount1 > 0,
            "Yapeswap: INSUFFICIENT_LIQUIDITY_BURNED"
        );
        _burn(address(this), liquidity);

        // Transfer to tokens
        token0is1155
            ? IERC1155(_token0).safeTransferFrom(
                address(this),
                to,
                token0sub,
                amount0,
                new bytes(0)
            )
            : ERC20TransferHelper.safeTransfer(_token0, to, amount0);
        token1is1155
            ? IERC1155(_token1).safeTransferFrom(
                address(this),
                to,
                token1sub,
                amount1,
                new bytes(0)
            )
            : ERC20TransferHelper.safeTransfer(_token1, to, amount1);

        // Update balances
        balance0 = token0is1155
            ? IERC1155(_token0).balanceOf(address(this), token0sub)
            : IERC20(_token0).balanceOf(address(this));
        balance1 = token1is1155
            ? IERC1155(_token1).balanceOf(address(this), token1sub)
            : IERC20(_token1).balanceOf(address(this));

        // Update liquidity and fees
        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0).mul(reserve1);
        // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // TODO(From here down, all token transfer and balance operations need to condition on is1155 per token)

    // this low-level function should be called from a contract which performs important safety checks
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external override(IYapeswapPair) lock {
        require(
            amount0Out > 0 || amount1Out > 0,
            "Yapeswap: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        // gas savings
        require(
            amount0Out < _reserve0 && amount1Out < _reserve1,
            "Yapeswap: INSUFFICIENT_LIQUIDITY"
        );

        uint256 balance0;
        uint256 balance1;
        {
            // scope for _token{0,1}, avoids stack too deep errors
            // gas savings from loading repeat storage access to stack
            address _token0 = token0;
            address _token1 = token1;

            require(to != _token0 && to != _token1, "Yapeswap: INVALID_TO");
            // optimistically transfer token
            if (amount0Out > 0) {
                token0is1155
                    ? IERC1155(_token0).safeTransferFrom(
                        address(this),
                        to,
                        token0sub,
                        amount0Out,
                        new bytes(0)
                    )
                    : ERC20TransferHelper.safeTransfer(_token0, to, amount0Out);
            }
            // optimistically transfer token
            if (amount1Out > 0) {
                token1is1155
                    ? IERC1155(_token1).safeTransferFrom(
                        address(this),
                        to,
                        token1sub,
                        amount1Out,
                        new bytes(0)
                    )
                    : ERC20TransferHelper.safeTransfer(_token1, to, amount1Out);
            }
            // flash swap callback
            if (data.length > 0)
                IYapeswapCallee(to).yapeswapCall(
                    msg.sender,
                    amount0Out,
                    amount1Out,
                    data
                );
            // Update balances
            balance0 = token0is1155
                ? IERC1155(_token0).balanceOf(address(this), token0sub)
                : IERC20(_token0).balanceOf(address(this));
            balance1 = token1is1155
                ? IERC1155(_token1).balanceOf(address(this), token1sub)
                : IERC20(_token1).balanceOf(address(this));
        }
        uint256 amount0In = balance0 > _reserve0 - amount0Out
            ? balance0 - (_reserve0 - amount0Out)
            : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out
            ? balance1 - (_reserve1 - amount1Out)
            : 0;
        require(
            amount0In > 0 || amount1In > 0,
            "Yapeswap: INSUFFICIENT_INPUT_AMOUNT"
        );
        {
            // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            uint256 balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
            uint256 balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
            require(
                balance0Adjusted.mul(balance1Adjusted) >=
                    uint256(_reserve0).mul(_reserve1).mul(1000**2),
                "Yapeswap: K"
            );
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    function skim(address to) external override(IYapeswapPair) lock {
        address _token0 = token0;
        bool _token0is1155 = token0is1155;
        // gas savings
        address _token1 = token1;
        bool _token1is1155 = token1is1155;
        // transfer excess
        uint256 transfer0 = _token0is1155
            ? IERC1155(token0).balanceOf(address(this), token0sub).sub(reserve0)
            : IERC20(token0).balanceOf(address(this)).sub(reserve0);
        _token0is1155
            ? IERC1155(token0).safeTransferFrom(
                address(this),
                to,
                token0sub,
                transfer0,
                new bytes(0)
            )
            : ERC20TransferHelper.safeTransfer(_token0, to, transfer0);
        uint256 transfer1 = token1is1155
            ? IERC1155(token1).balanceOf(address(this), token1sub).sub(reserve1)
            : IERC20(token1).balanceOf(address(this)).sub(reserve1);
        _token1is1155
            ? IERC1155(token1).safeTransferFrom(
                address(this),
                to,
                token0sub,
                transfer1,
                new bytes(0)
            )
            : ERC20TransferHelper.safeTransfer(_token1, to, transfer1);
    }

    // force reserves to match balances
    function sync() external override(IYapeswapPair) lock {
        _update(
            token0is1155
                ? IERC1155(token0).balanceOf(address(this), token0sub)
                : IERC20(token0).balanceOf(address(this)),
            token1is1155
                ? IERC1155(token1).balanceOf(address(this), token1sub)
                : IERC20(token1).balanceOf(address(this)),
            reserve0,
            reserve1
        );
    }
}
