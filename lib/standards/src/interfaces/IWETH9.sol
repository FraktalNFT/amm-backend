// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin/IERC20.sol";

interface IWETH9 is IERC20 {
    function deposit() external payable;
    function transfer(address to, uint value) external override returns (bool);
    function withdraw(uint) external;
}