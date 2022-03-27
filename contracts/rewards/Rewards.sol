// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity >=0.8.4;

import "hardhat/console.sol";
import "./ERC4626.sol";

abstract contract Rewards is ERC4626 {
    constructor(string memory name, string memory symbol) {
        
    }

}
