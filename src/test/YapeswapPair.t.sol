// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Common.sol";
import "../core/YapeswapERC20.sol";
import "../core/YapeswapFactory.sol";
import "../core/YapeswapPair.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "ds-test/test.sol";

contract YapeswapPairTest is DSTest, ERC1155Holder {
    MockERC20Token weth;
    MockERC1155Token fraktal;
    YapeswapFactory factory;
    YapeswapPair pair;

    function setUp() public {
        weth = new MockERC20Token("Wrapped Ethereum", "WETH");
        fraktal = new MockERC1155Token("Fraktal NFT", "FRAK1");
        factory = new YapeswapFactory(address(this));

        // Send mock weth to holder
        weth.mint(address(this), 8 ether);

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
    }

    //
    // Pair tests
    //

    function testPairIsERC1155Holder() public {
        // The pair must be able to hold erc1155
        assert(
            (ERC165Checker.supportsInterface(address(pair), 0x4e2312e0) == true)
        );
    }

    function testPairMINIMUM_LIQUIDITY() public {
        assert(pair.MINIMUM_LIQUIDITY() == 10**3);
    }

    function testPairFactory() public {
        assert(pair.factory() == address(factory));
    }

    function testPairToken0() public {
        pair.token0();
    }

    function testPairToken0sub() public {
        pair.token0sub();
    }

    function testPairToken1() public {
        address(fraktal);
    }

    function testPairToken1sub() public {
        pair.token1sub();
    }

    function testPairGetReserves() public {
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = pair
            .getReserves();
    }

    function testPairPrice0CumulativeLast() public {
        uint256 price0 = pair.price0CumulativeLast();
    }

    function testPairPrice1CumulativeLast() public {
        uint256 price1 = pair.price1CumulativeLast();
    }

    function testkLast() public {
        uint256 klast = pair.kLast();
    }

    function testMint() public {
        // We already minted in the setup, so here we just make assertions about the balances
        assert(pair.totalSupply() == 2 ether);
        assert(weth.balanceOf(address(pair)) == 1 ether);
        assert(fraktal.balanceOf(address(pair), 2) == 4 ether);
    }

    function testBurn() public {
        pair.transfer(address(pair), 1 ether);
        (uint256 amount0, uint256 amount1) = pair.burn(address(this));
        assert(pair.totalSupply() == 1 ether);
        assert(weth.balanceOf(address(pair)) == 0.5 ether);
        assert(fraktal.balanceOf(address(pair), 2) == 2 ether);
    }

    function testSwap() public {
        bytes memory data;
        weth.transfer(address(pair), 1 ether);
        pair.swap(1.9969 ether, 0 ether, address(this), data);
    }

    function testSkim() public {
        pair.skim(address(this));
    }

    function testSync() public {
        pair.sync();
    }

    // Initialize is tested implicitly at creation by the factory
}
