// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/token/ERC1155/ERC1155.sol";
import "openzeppelin/utils/Ownable.sol";
import "../core/YapeswapFactory.sol";
import "../core/YapeswapPair.sol";
import "openzeppelin/token/ERC1155/utils/ERC1155Holder.sol";
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

contract YapeswapFactoryTest is DSTest, ERC1155Holder {
    MockERC20Token weth;
    MockERC1155Token fraktal;
    MockERC1155Token fraktal2;
    YapeswapFactory factory;
    YapeswapPair pair;

    function setUp() public {
        weth = new MockERC20Token("Wrapped Ethereum", "WETH");
        fraktal = new MockERC1155Token("Fraktal NFT", "FRAK1");
        fraktal2 = new MockERC1155Token("Fraktal NFT", "FRAK2");
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
    }

    // Factory tests

    function testFeeTo() public {
        // Because it's null.
        factory.setFeeTo(address(this));
        assert(factory.feeTo() == address(this));
    }

    function testFeeToSetter() public {
        assert(factory.feeToSetter() == address(this));
    }

    function testGetPair() public {
        assert(
            factory.getPair(address(weth), 0, address(fraktal), 2) ==
                address(pair)
        );
    }

    function testAllPairs() public {
        assert(factory.allPairs(0) == address(pair));
    }

    function testAllPairsLength() public {
        assert(factory.allPairsLength() == 1);
    }

    function testCreatePair() public {
        factory.createPair(address(weth), 0, address(fraktal2), 2);
    }

    function testFailCreatePair() public {
        // We expect this to fail because it was already created in setUp
        factory.createPair(address(weth), 0, address(fraktal), 2);
    }

    function testSetFeeTo() public {
        factory.setFeeTo(address(this));
    }

    function testFailSetFeeTo() public {
        factory.setFeeToSetter(address(weth));
        factory.setFeeTo(address(this));
    }

    function testSetFeeToSetter() public {
        factory.setFeeToSetter(address(this));
    }

    function testFailSetFeeToSetter() public {
        factory.setFeeToSetter(address(weth));
        factory.setFeeToSetter(address(this));
    }
}
