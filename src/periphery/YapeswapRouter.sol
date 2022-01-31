// SPDX-License-Identifier: GPL
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../IWETH9.sol";
import "@openzeppelin/contracts/interfaces/IERC1155.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "../core/interfaces/IYapeswapFactory.sol";
import "../ERC20TransferHelper.sol";
import "./interfaces/IYapeswapRouter.sol";
import "./libraries/YapeswapLibrary.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract YapeswapRouter is IYapeswapRouter {
    using SafeMath for uint256;

    address public immutable override factory;
    address public immutable override WETH;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "YapeswapRouter: EXPIRED");
        _;
    }

    constructor(address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    function getToken0(
        address tokenA,
        uint256 tokenAsub,
        address tokenB,
        uint256 tokenBsub
    ) private pure returns (address token0) {
        (token0, , , ) = YapeswapLibrary.sortTokens(
            tokenA,
            tokenAsub,
            tokenB,
            tokenBsub
        );
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        uint256 tokenAsub,
        address tokenB,
        uint256 tokenBsub,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn't exist yet
        if (
            IYapeswapFactory(factory).getPair(
                tokenA,
                tokenAsub,
                tokenB,
                tokenBsub
            ) == address(0)
        ) {
            IYapeswapFactory(factory).createPair(
                tokenA,
                tokenAsub,
                tokenB,
                tokenBsub
            );
        }
        (uint256 reserveA, uint256 reserveB) = YapeswapLibrary.getReserves(
            factory,
            tokenA,
            tokenAsub,
            tokenB,
            tokenBsub
        );
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = YapeswapLibrary.quote(
                amountADesired,
                reserveA,
                reserveB
            );
            if (amountBOptimal <= amountBDesired) {
                require(
                    amountBOptimal >= amountBMin,
                    "YapeswapRouter: INSUFFICIENT_B_AMOUNT"
                );
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = YapeswapLibrary.quote(
                    amountBDesired,
                    reserveB,
                    reserveA
                );
                assert(amountAOptimal <= amountADesired);
                require(
                    amountAOptimal >= amountAMin,
                    "YapeswapRouter: INSUFFICIENT_A_AMOUNT"
                );
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(AddLiquidityInfo calldata addInfo)
        external
        virtual
        override
        ensure(addInfo.deadline)
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        (amountA, amountB) = _addLiquidity(
            addInfo.tokenA,
            addInfo.tokenAsub,
            addInfo.tokenB,
            addInfo.tokenBsub,
            addInfo.amountADesired,
            addInfo.amountBDesired,
            addInfo.amountAMin,
            addInfo.amountBMin
        );
        address pair = YapeswapLibrary.pairFor(
            factory,
            addInfo.tokenA,
            addInfo.tokenAsub,
            addInfo.tokenB,
            addInfo.tokenBsub
        );
        ERC165Checker.supportsInterface(addInfo.tokenA, 0xd9b67a26)
            ? IERC1155(addInfo.tokenA).safeTransferFrom(
                msg.sender,
                pair,
                addInfo.tokenAsub,
                amountA,
                new bytes(0)
            )
            : ERC20TransferHelper.safeTransferFrom(
                addInfo.tokenA,
                msg.sender,
                pair,
                amountA
            );
        ERC165Checker.supportsInterface(addInfo.tokenB, 0xd9b67a26)
            ? IERC1155(addInfo.tokenB).safeTransferFrom(
                msg.sender,
                pair,
                addInfo.tokenBsub,
                amountB,
                new bytes(0)
            )
            : ERC20TransferHelper.safeTransferFrom(
                addInfo.tokenB,
                msg.sender,
                pair,
                amountB
            );
        liquidity = IYapeswapPair(pair).mint(addInfo.to);
    }

    function addLiquidityETH(
        address token,
        uint256 tokensub,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        )
    {
        (amountToken, amountETH) = _addLiquidity(
            token,
            tokensub,
            WETH,
            0,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pair = YapeswapLibrary.pairFor(
            factory,
            token,
            tokensub,
            WETH,
            0
        );
        ERC165Checker.supportsInterface(token, 0xd9b67a26)
            ? IERC1155(token).safeTransferFrom(
                msg.sender,
                pair,
                tokensub,
                amountToken,
                new bytes(0)
            )
            : ERC20TransferHelper.safeTransferFrom(
                token,
                msg.sender,
                pair,
                amountToken
            );
        IWETH9(WETH).deposit{value: amountETH}();
        assert(IWETH9(WETH).transfer(pair, amountETH));
        liquidity = IYapeswapPair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH)
            ERC20TransferHelper.safeTransferETH(
                msg.sender,
                msg.value - amountETH
            );
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(removeLiquidityInfo memory info)
        public
        virtual
        override
        ensure(info.deadline)
        returns (uint256 amountA, uint256 amountB)
    {
        address pair = YapeswapLibrary.pairFor(
            factory,
            info.tokenA,
            info.tokenAsub,
            info.tokenB,
            info.tokenBsub
        );
        IYapeswapPair(pair).transferFrom(msg.sender, pair, info.liquidity); // send liquidity to pair
        bool order;
        {
            address token0 = getToken0(
                info.tokenA,
                info.tokenAsub,
                info.tokenB,
                info.tokenBsub
            );
            order = (info.tokenA == token0);
        }
        {
            (uint256 amount0, uint256 amount1) = IYapeswapPair(pair).burn(
                info.to
            );
            if (order) {
                (amountA, amountB) = (amount0, amount1);
            } else {
                (amountA, amountB) = (amount1, amount0);
            }
        }
        require(
            amountA >= info.amountAMin,
            "YapeswapRouter: INSUFFICIENT_A_AMOUNT"
        );
        require(
            amountB >= info.amountBMin,
            "YapeswapRouter: INSUFFICIENT_B_AMOUNT"
        );
    }

    function removeLiquidityETH(removeLiquidityETHInfo memory info)
        public
        virtual
        override
        ensure(info.deadline)
        returns (uint256 amountToken, uint256 amountETH)
    {
        removeLiquidityInfo memory liqInfo;
        liqInfo.tokenA = info.token;
        liqInfo.tokenAsub = info.tokensub;
        liqInfo.tokenB = WETH;
        liqInfo.tokenBsub = 0;
        liqInfo.liquidity = info.liquidity;
        liqInfo.amountAMin = info.amountTokenMin;
        liqInfo.amountBMin = info.amountETHMin;
        liqInfo.to = address(this);
        liqInfo.deadline = info.deadline;
        (amountToken, amountETH) = removeLiquidity(liqInfo);
        ERC165Checker.supportsInterface(info.token, 0xd9b67a26)
            ? IERC1155(info.token).safeTransferFrom(
                address(this),
                info.to,
                info.tokensub,
                amountToken,
                new bytes(0)
            )
            : ERC20TransferHelper.safeTransfer(
                info.token,
                info.to,
                amountToken
            );
        IWETH9(WETH).withdraw(amountETH);
        ERC20TransferHelper.safeTransferETH(info.to, amountETH);
    }

    function permit(
        removeLiquidityInfo memory info,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) private {
        uint256 value = approveMax ? type(uint256).max : info.liquidity;
        IYapeswapPair(
            YapeswapLibrary.pairFor(
                factory,
                info.tokenA,
                info.tokenAsub,
                info.tokenB,
                info.tokenBsub
            )
        ).permit(msg.sender, address(this), value, info.deadline, v, r, s);
    }

    function removeLiquidityWithPermit(
        removeLiquidityInfo memory info,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountA, uint256 amountB) {
        permit(
            info,
            approveMax,
            v,
            r,
            s
        );
        (amountA, amountB) = removeLiquidity(info);
    }

    function removeLiquidityETHWithPermit(
        removeLiquidityETHInfo memory info,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        virtual
        override
        returns (uint256 amountToken, uint256 amountETH)
    {
        address pair = YapeswapLibrary.pairFor(
            factory,
            info.token,
            info.tokensub,
            WETH,
            0
        );
        uint256 value = approveMax ? type(uint256).max : info.liquidity;
        IYapeswapPair(pair).permit(
            msg.sender,
            address(this),
            value,
            info.deadline,
            v,
            r,
            s
        );
        (amountToken, amountETH) = removeLiquidityETH(info);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        removeLiquidityETHInfo memory info
    )
        public
        virtual
        override
        ensure(info.deadline)
        returns (uint256 amountETH)
    {
        removeLiquidityInfo memory liqInfo;
        liqInfo.tokenA = info.token;
        liqInfo.tokenAsub = info.tokensub;
        liqInfo.tokenB = WETH;
        liqInfo.tokenBsub = 0;
        liqInfo.liquidity = info.liquidity;
        liqInfo.amountAMin = info.amountTokenMin;
        liqInfo.amountBMin = info.amountETHMin;
        liqInfo.to = address(this);
        liqInfo.deadline = info.deadline;
        (, amountETH) = removeLiquidity(liqInfo);
        ERC165Checker.supportsInterface(info.token, 0xd9b67a26)
            ? IERC1155(info.token).safeTransferFrom(
                address(this),
                info.to,
                info.tokensub,
                IERC1155(info.token).balanceOf(address(this), info.tokensub),
                new bytes(0)
            )
            : ERC20TransferHelper.safeTransfer(
                info.token,
                info.to,
                IERC20(info.token).balanceOf(address(this))
            );
        IWETH9(WETH).withdraw(amountETH);
        ERC20TransferHelper.safeTransferETH(info.to, amountETH);
    }

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        removeLiquidityETHInfo memory info,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountETH) {
        address pair = YapeswapLibrary.pairFor(
            factory,
            info.token,
            info.tokensub,
            WETH,
            0
        );
        uint256 value = approveMax ? type(uint256).max : info.liquidity;
        IYapeswapPair(pair).permit(
            msg.sender,
            address(this),
            value,
            info.deadline,
            v,
            r,
            s
        );
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(info);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(
        uint256[] memory amounts,
        address[] memory tokenPath,
        uint256[] memory subPath,
        address _to
    ) internal virtual {
        for (uint256 i; i < tokenPath.length - 1; i++) {
            swapInfo memory swap;
            (swap.input, swap.output) = (tokenPath[i], tokenPath[i + 1]);
            (swap.inputsub, swap.outputsub) = (subPath[i], subPath[i + 1]);
            (address token0, , , ) = YapeswapLibrary.sortTokens(
                swap.input,
                swap.inputsub,
                swap.output,
                swap.outputsub
            );
            swap.amountOutput = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = swap.input == token0
                ? (uint256(0), swap.amountOutput)
                : (swap.amountOutput, uint256(0));
            address to = i < tokenPath.length - 2
                ? YapeswapLibrary.pairFor(
                    factory,
                    swap.output,
                    swap.outputsub,
                    tokenPath[i + 2],
                    subPath[i + 2]
                )
                : _to;
            IYapeswapPair(
                YapeswapLibrary.pairFor(
                    factory,
                    swap.input,
                    swap.inputsub,
                    swap.output,
                    swap.outputsub
                )
            ).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata tokenPath,
        uint256[] calldata subPath,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(tokenPath.length == subPath.length);
        amounts = YapeswapLibrary.getAmountsOut(
            factory,
            amountIn,
            tokenPath,
            subPath
        );
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "YapeswapRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        address pair = YapeswapLibrary.pairFor(
            factory,
            tokenPath[0],
            subPath[0],
            tokenPath[1],
            subPath[1]
        );
        ERC165Checker.supportsInterface(tokenPath[0], 0xd9b67a26)
            ? IERC1155(tokenPath[0]).safeTransferFrom(
                msg.sender,
                pair,
                subPath[0],
                amounts[0],
                new bytes(0)
            )
            : ERC20TransferHelper.safeTransferFrom(
                tokenPath[0],
                msg.sender,
                pair,
                amounts[0]
            );
        _swap(amounts, tokenPath, subPath, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata tokenPath,
        uint256[] calldata subPath,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(tokenPath.length == subPath.length);
        amounts = YapeswapLibrary.getAmountsIn(
            factory,
            amountOut,
            tokenPath,
            subPath
        );
        require(
            amounts[0] <= amountInMax,
            "YapeswapRouter: EXCESSIVE_INPUT_AMOUNT"
        );

        address pair = YapeswapLibrary.pairFor(
            factory,
            tokenPath[0],
            subPath[0],
            tokenPath[1],
            subPath[1]
        );

        ERC165Checker.supportsInterface(tokenPath[0], 0xd9b67a26)
            ? IERC1155(tokenPath[0]).safeTransferFrom(
                msg.sender,
                pair,
                subPath[0],
                amounts[0],
                new bytes(0)
            )
            : ERC20TransferHelper.safeTransferFrom(
                tokenPath[0],
                msg.sender,
                pair,
                amounts[0]
            );
        _swap(amounts, tokenPath, subPath, to);
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata tokenPath,
        uint256[] calldata subPath,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(tokenPath.length == subPath.length);
        require(tokenPath[0] == WETH, "YapeswapRouter: INVALID_PATH");
        amounts = YapeswapLibrary.getAmountsOut(
            factory,
            msg.value,
            tokenPath,
            subPath
        );
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "YapeswapRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        IWETH9(WETH).deposit{value: amounts[0]}();
        assert(
            IWETH9(WETH).transfer(
                YapeswapLibrary.pairFor(
                    factory,
                    tokenPath[0],
                    subPath[0],
                    tokenPath[1],
                    subPath[1]
                ),
                amounts[0]
            )
        );
        _swap(amounts, tokenPath, subPath, to);
    }

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata tokenPath,
        uint256[] calldata subPath,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(tokenPath.length == subPath.length);
        require(
            tokenPath[tokenPath.length - 1] == WETH,
            "YapeswapRouter: INVALID_PATH"
        );
        amounts = YapeswapLibrary.getAmountsIn(
            factory,
            amountOut,
            tokenPath,
            subPath
        );
        require(
            amounts[0] <= amountInMax,
            "YapeswapRouter: EXCESSIVE_INPUT_AMOUNT"
        );

        address pair = YapeswapLibrary.pairFor(
            factory,
            tokenPath[0],
            subPath[0],
            tokenPath[1],
            subPath[1]
        );

        ERC165Checker.supportsInterface(tokenPath[0], 0xd9b67a26)
            ? IERC1155(tokenPath[0]).safeTransferFrom(
                msg.sender,
                pair,
                subPath[0],
                amounts[0],
                new bytes(0)
            )
            : ERC20TransferHelper.safeTransferFrom(
                tokenPath[0],
                msg.sender,
                pair,
                amounts[0]
            );
        _swap(amounts, tokenPath, subPath, address(this));
        IWETH9(WETH).withdraw(amounts[amounts.length - 1]);
        ERC20TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata tokenPath,
        uint256[] calldata subPath,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(tokenPath.length == subPath.length);
        require(
            tokenPath[tokenPath.length - 1] == WETH,
            "YapeswapRouter: INVALID_PATH"
        );
        amounts = YapeswapLibrary.getAmountsOut(
            factory,
            amountIn,
            tokenPath,
            subPath
        );
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "YapeswapRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );

        address pair = YapeswapLibrary.pairFor(
            factory,
            tokenPath[0],
            subPath[0],
            tokenPath[1],
            subPath[1]
        );

        ERC165Checker.supportsInterface(tokenPath[0], 0xd9b67a26)
            ? IERC1155(tokenPath[0]).safeTransferFrom(
                msg.sender,
                pair,
                subPath[0],
                amounts[0],
                new bytes(0)
            )
            : ERC20TransferHelper.safeTransferFrom(
                tokenPath[0],
                msg.sender,
                pair,
                amounts[0]
            );
        _swap(amounts, tokenPath, subPath, address(this));
        IWETH9(WETH).withdraw(amounts[amounts.length - 1]);
        ERC20TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata tokenPath,
        uint256[] calldata subPath,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(tokenPath.length == subPath.length);
        require(tokenPath[0] == WETH, "YapeswapRouter: INVALID_PATH");
        amounts = YapeswapLibrary.getAmountsIn(
            factory,
            amountOut,
            tokenPath,
            subPath
        );
        require(
            amounts[0] <= msg.value,
            "YapeswapRouter: EXCESSIVE_INPUT_AMOUNT"
        );
        IWETH9(WETH).deposit{value: amounts[0]}();
        assert(
            IWETH9(WETH).transfer(
                YapeswapLibrary.pairFor(
                    factory,
                    tokenPath[0],
                    subPath[0],
                    tokenPath[1],
                    subPath[1]
                ),
                amounts[0]
            )
        );
        _swap(amounts, tokenPath, subPath, to);
        // refund dust eth, if any
        if (msg.value > amounts[0])
            ERC20TransferHelper.safeTransferETH(
                msg.sender,
                msg.value - amounts[0]
            );
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(
        address[] memory tokenPath,
        uint256[] memory subPath,
        address _to
    ) internal virtual {
        for (uint256 i; i < tokenPath.length - 1; i++) {
            swapInfo memory swap;
            (swap.input, swap.output) = (tokenPath[i], tokenPath[i + 1]);
            (swap.inputsub, swap.outputsub) = (subPath[i], subPath[i + 1]);
            (address token0, , , ) = YapeswapLibrary.sortTokens(
                swap.input,
                swap.inputsub,
                swap.output,
                swap.outputsub
            );
            IYapeswapPair pair = IYapeswapPair(
                YapeswapLibrary.pairFor(
                    factory,
                    swap.input,
                    swap.inputsub,
                    swap.output,
                    swap.outputsub
                )
            );
            {
                // scope to avoid stack too deep errors
                (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
                (uint256 reserveInput, uint256 reserveOutput) = swap.input ==
                    token0
                    ? (reserve0, reserve1)
                    : (reserve1, reserve0);
                swap.amountInput = (
                    ERC165Checker.supportsInterface(swap.input, 0xd9b67a26)
                        ? IERC1155(swap.input).balanceOf(
                            address(pair),
                            swap.inputsub
                        )
                        : IERC20(swap.input).balanceOf(address(pair))
                ).sub(reserveInput);
                swap.amountOutput = YapeswapLibrary.getAmountOut(
                    swap.amountInput,
                    reserveInput,
                    reserveOutput
                );
            }
            (uint256 amount0Out, uint256 amount1Out) = swap.input == token0
                ? (uint256(0), swap.amountOutput)
                : (swap.amountOutput, uint256(0));
            address to = i < tokenPath.length - 2
                ? YapeswapLibrary.pairFor(
                    factory,
                    swap.output,
                    swap.outputsub,
                    tokenPath[i + 2],
                    subPath[i + 2]
                )
                : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata tokenPath,
        uint256[] calldata subPath,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        require(tokenPath.length == subPath.length);
        address pair = YapeswapLibrary.pairFor(
            factory,
            tokenPath[0],
            subPath[0],
            tokenPath[1],
            subPath[1]
        );
        ERC165Checker.supportsInterface(tokenPath[0], 0xd9b67a26)
            ? IERC1155(tokenPath[0]).safeTransferFrom(
                msg.sender,
                pair,
                subPath[0],
                amountIn,
                new bytes(0)
            )
            : ERC20TransferHelper.safeTransferFrom(
                tokenPath[0],
                msg.sender,
                pair,
                amountIn
            );
        bool lastIs1155 = ERC165Checker.supportsInterface(
            tokenPath[tokenPath.length - 1],
            0xd9b67a26
        );
        // Output address balance before
        uint256 balanceBefore = lastIs1155
            ? IERC1155(tokenPath[tokenPath.length - 1]).balanceOf(
                to,
                subPath[subPath.length - 1]
            )
            : IERC20(tokenPath[tokenPath.length - 1]).balanceOf(to);
        // Do swap
        _swapSupportingFeeOnTransferTokens(tokenPath, subPath, to);
        // Balance after
        uint256 balanceNow = lastIs1155
            ? IERC1155(tokenPath[tokenPath.length - 1]).balanceOf(
                to,
                subPath[subPath.length - 1]
            )
            : IERC20(tokenPath[tokenPath.length - 1]).balanceOf(to);
        require(
            balanceNow.sub(balanceBefore) >= amountOutMin,
            "YapeswapRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata tokenPath,
        uint256[] calldata subPath,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) {
        require(tokenPath.length == subPath.length);
        require(tokenPath[0] == WETH, "YapeswapRouter: INVALID_PATH");
        uint256 amountIn = msg.value;
        IWETH9(WETH).deposit{value: amountIn}();
        assert(
            IWETH9(WETH).transfer(
                YapeswapLibrary.pairFor(
                    factory,
                    tokenPath[0],
                    subPath[0],
                    tokenPath[1],
                    subPath[1]
                ),
                amountIn
            )
        );
        bool lastIs1155 = ERC165Checker.supportsInterface(
            tokenPath[tokenPath.length - 1],
            0xd9b67a26
        );
        uint256 balanceBefore = lastIs1155
            ? IERC1155(tokenPath[tokenPath.length - 1]).balanceOf(
                to,
                subPath[subPath.length - 1]
            )
            : IERC20(tokenPath[tokenPath.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(tokenPath, subPath, to);
        uint256 balanceNow = lastIs1155
            ? IERC1155(tokenPath[tokenPath.length - 1]).balanceOf(
                to,
                subPath[subPath.length - 1]
            )
            : IERC20(tokenPath[tokenPath.length - 1]).balanceOf(to);
        require(
            balanceNow.sub(balanceBefore) >= amountOutMin,
            "YapeswapRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata tokenPath,
        uint256[] calldata subPath,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        require(tokenPath.length == subPath.length);
        require(
            tokenPath[tokenPath.length - 1] == WETH,
            "YapeswapRouter: INVALID_PATH"
        );

        address pair = YapeswapLibrary.pairFor(
            factory,
            tokenPath[0],
            subPath[0],
            tokenPath[1],
            subPath[1]
        );
        ERC165Checker.supportsInterface(tokenPath[0], 0xd9b67a26)
            ? IERC1155(tokenPath[0]).safeTransferFrom(
                msg.sender,
                pair,
                subPath[0],
                amountIn,
                new bytes(0)
            )
            : ERC20TransferHelper.safeTransferFrom(
                tokenPath[0],
                msg.sender,
                pair,
                amountIn
            );
        _swapSupportingFeeOnTransferTokens(tokenPath, subPath, address(this));
        uint256 amountOut = IERC20(WETH).balanceOf(address(this));
        require(
            amountOut >= amountOutMin,
            "YapeswapRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        IWETH9(WETH).withdraw(amountOut);
        ERC20TransferHelper.safeTransferETH(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) public pure virtual override returns (uint256 amountB) {
        return YapeswapLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure virtual override returns (uint256 amountOut) {
        return YapeswapLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure virtual override returns (uint256 amountIn) {
        return YapeswapLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(
        uint256 amountIn,
        address[] memory tokenPath,
        uint256[] memory subid_path
    ) public view virtual override returns (uint256[] memory amounts) {
        return
            YapeswapLibrary.getAmountsOut(
                factory,
                amountIn,
                tokenPath,
                subid_path
            );
    }

    function getAmountsIn(
        uint256 amountOut,
        address[] memory tokenPath,
        uint256[] memory subid_path
    ) public view virtual override returns (uint256[] memory amounts) {
        return
            YapeswapLibrary.getAmountsIn(
                factory,
                amountOut,
                tokenPath,
                subid_path
            );
    }
}
