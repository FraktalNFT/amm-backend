// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Common.sol";
import "../core/YapeswapFactory.sol";
import "../core/YapeswapPair.sol";
import "../periphery/YapeswapRouter.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "ds-test/test.sol";

contract YapeswapRouterTest is DSTest, ERC1155Holder {
    WETH9 weth;
    MockERC1155Token fraktal;
    YapeswapFactory factory;
    YapeswapPair pair;

    YapeswapRouter router;

    // TODO(https://github.com/gakonst/foundry/issues/619)

    function setUp() public {
        weth = new WETH9();
        fraktal = new MockERC1155Token("Fraktal NFT", "FRAK1");
        factory = new YapeswapFactory(address(this));

        // Send mock weth to holder
        weth.deposit{value: 8 ether}();

        // Send a mock fraktal token to holder
        fraktal.mint(address(this), 1, 1, new bytes(0));
        fraktal.mint(address(this), 2, 8 ether, new bytes(0));

        // Setup a weth/fraktal pair
        pair = YapeswapPair(
            factory.createPair(address(weth), 0, address(fraktal), 2)
        );

        // Send some weth and fraktal to the pair
        weth.transfer(address(pair), 1 ether);
        fraktal.safeTransferFrom(
            address(this),
            address(pair),
            2,
            4 ether,
            new bytes(0)
        );

        // Mint some liquidity
        pair.mint(address(this));

        router = new YapeswapRouter(address(factory), address(weth));
    }

    function testFactory() public {
        //assert(address(factory) == router.factory());
    }

    function testWETH() public {
        //assert(address(weth) == router.WETH());
    }
}
