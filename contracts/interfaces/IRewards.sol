// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4;

import {ERC1155} from "@rari-capital/solmate/src/tokens/ERC1155.sol";

/// @notice Rewards required interface
interface IRewards {
    function createVault(ERC1155 asset, uint256 poolId) external returns (uint256 id);

    function deposit(
        ERC1155 asset,
        uint256 assets,
        address receiver
    ) external returns (uint256 shares);

    function withdraw(
        ERC1155 asset,
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares);
}
