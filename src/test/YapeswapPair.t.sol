// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/token/ERC1155/ERC1155.sol";
import "openzeppelin/utils/Ownable.sol";
import "../core/YapeswapERC20.sol";
import "../core/YapeswapFactory.sol";
import "../core/YapeswapPair.sol";
import "openzeppelin/token/ERC1155/utils/ERC1155Holder.sol";
import "openzeppelin/utils/introspection/ERC165Checker.sol";
import "ds-test/test.sol";

contract MockERC20Token is ERC20, Ownable {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}

contract MockERC1155Token is ERC1155, Ownable {
    constructor(string memory name, string memory symbol) ERC1155(string("")) {}

    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) public onlyOwner {
        _mint(to, id, amount, data);
    }
}

// TODO(Our holder may need to be able to do some stuff here)

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
        weth.mint(address(this), 10000000000000000000);

        // Send a mock fraktal token to holder
        fraktal.mint(address(this), 1, 1, new bytes(0));
        fraktal.mint(address(this), 2, 10000, new bytes(0));

        // Setup a weth/fraktal pair
        pair = YapeswapPair(
            factory.createPair(address(weth), 0, address(fraktal), 2)
        );

        // Send some weth and fraktal to the pair
        weth.transfer(address(pair), 1000000000000000000);
        fraktal.safeTransferFrom(
            address(this),
            address(pair),
            2,
            5000,
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

    // TODO(Check these 5 tests against sort)
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
        // TODO(Figure out how to test this correctly)
    }
}
