// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4;

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";

interface IRewards {
    function createVault(ERC20 asset, uint256 poolId) external returns (uint256 id);

    function deposit(
        ERC20 asset,
        uint256 assets,
        address receiver
    ) external returns (uint256 shares);

    function withdraw(
        ERC20 asset,
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares);
}
