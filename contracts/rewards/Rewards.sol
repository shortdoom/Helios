// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

import {HeliosERC1155} from "../HeliosERC1155.sol";
import {IHelios} from "../interfaces/IHelios.sol";

/// @notice Minimal ERC4626-style tokenized Vault implementation with HeliosERC1155 accounting.
/// @author Modified from Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/mixins/ERC4626.sol)
contract Rewards is HeliosERC1155 {
    using SafeTransferLib for HeliosERC1155;
    using FixedPointMathLib for uint256;

    /*///////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Create(HeliosERC1155 indexed asset, uint256 id);

    event Deposit(
        address indexed caller,
        address indexed owner,
        HeliosERC1155 indexed asset,
        uint256 assets,
        uint256 shares
    );

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        HeliosERC1155 asset,
        uint256 assets,
        uint256 shares
    );

    /*///////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public totalSupplyRewards;

    /// owner => rewardId => balance
    mapping(address => mapping(uint256 => uint256)) public balanceLocked;

    /// Base Helios1155 LP-token => rewardId => Vault
    mapping(HeliosERC1155 => mapping(uint256 => Vault)) public vaults;

    struct Vault {
        uint256 poolId;
        uint256 totalSupply;
        ERC20 rewardToken; // ERC20 rewardToken?
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// Only one Vault per reward token, but infinite Vaults with diff rTokens
    /// One reward token can exist in multiple vaults
    /// asset = underlying (deposited pool LP token) of vaults[asset][rewardId]
    function create(HeliosERC1155 asset, uint256 poolId, address rewardToken)
        internal
        returns (uint256 rewardId)
    {

        unchecked {
            rewardId = ++totalSupplyRewards;
        }

        vaults[asset][rewardId].poolId = poolId;
        vaults[asset][rewardId].rewardToken = ERC20(rewardToken);

        // afterCreate() should init ERC20

        emit Create(asset, rewardId);
    }

    function deposit(
        HeliosERC1155 asset,
        uint256 rewardId,
        uint256 poolId,
        uint256 assets,
        address receiver
    ) internal returns (uint256 shares) {
        require((shares = previewDeposit(asset, rewardId, assets)) != 0, "ZERO_SHARES");

        /// @notice can this be done differently?
        asset.safeTransferFrom(msg.sender, address(this), poolId, assets, "");
        /// @notice check if reward=pool match
        balanceLocked[msg.sender][rewardId] += assets;
        vaults[asset][rewardId].totalSupply += shares;

        emit Deposit(msg.sender, receiver, asset, assets, shares);

        afterDeposit(asset, assets, shares);
    }

    function mint(
        HeliosERC1155 asset,
        uint256 rewardId,
        uint256 poolId,
        uint256 shares,
        address receiver
    ) public returns (uint256 assets) {
        assets = previewMint(asset, rewardId, shares); // No need to check for rounding error, previewMint rounds up.

        asset.safeTransferFrom(msg.sender, address(this), poolId, assets, "");
        balanceLocked[msg.sender][rewardId] += assets;
        vaults[asset][rewardId].totalSupply += assets;

        emit Deposit(msg.sender, receiver, asset, assets, shares);

        afterDeposit(asset, assets, shares);
    }

    function withdraw(
        HeliosERC1155 asset,
        uint256 rewardId,
        uint256 assets,
        address receiver,
        address owner
    ) public returns (uint256 shares) {
        shares = previewWithdraw(asset, rewardId, assets); // No need to check for rounding error, previewWithdraw rounds up.
        if (msg.sender != owner)
            require(isApprovedForAll[owner][msg.sender], "NOT_OPERATOR");

        balanceLocked[msg.sender][rewardId] -= shares;
        vaults[asset][rewardId].totalSupply -= shares;

        emit Withdraw(msg.sender, receiver, owner, asset, assets, shares);

        /// 3rd party token, this should be validated on create()
        vaults[asset][rewardId].rewardToken.transferFrom(address(this), msg.sender, assets);
    }

    function redeem(
        HeliosERC1155 asset,
        uint256 rewardId,
        uint256 shares,
        address receiver,
        address owner
    ) public returns (uint256 assets) {
        if (msg.sender != owner)
            require(isApprovedForAll[owner][msg.sender], "NOT_OPERATOR");

        require((assets = previewRedeem(asset, rewardId, shares)) != 0, "ZERO_ASSETS");

        balanceLocked[msg.sender][rewardId] -= shares;
        vaults[asset][rewardId].totalSupply -= shares;

        emit Withdraw(msg.sender, receiver, owner, asset, assets, shares);

        /// 3rd party token, this should be validated on create()
        vaults[asset][rewardId].rewardToken.transferFrom(address(this), msg.sender, assets);
    }

    /*///////////////////////////////////////////////////////////////
                           ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view returns (uint256) {
        return 0;
    }

    function convertToShares(HeliosERC1155 asset, uint256 rewardId, uint256 assets)
        public
        view
        returns (uint256)
    {
        uint256 supply = vaults[asset][rewardId].totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDivDown(supply, totalAssets());
    }

    function convertToAssets(HeliosERC1155 asset, uint256 rewardId, uint256 shares)
        public
        view
        returns (uint256)
    {
        uint256 supply = vaults[asset][rewardId].totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDivDown(totalAssets(), supply);
    }

    function previewDeposit(HeliosERC1155 asset, uint256 rewardId,  uint256 assets)
        public
        view
        returns (uint256)
    {
        return convertToShares(asset, rewardId, assets);
    }

    function previewMint(HeliosERC1155 asset, uint256 rewardId, uint256 shares)
        public
        view
        returns (uint256)
    {
        uint256 supply = vaults[asset][rewardId].totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDivUp(totalAssets(), supply);
    }

    function previewWithdraw(HeliosERC1155 asset, uint256 rewardId,  uint256 assets)
        public
        view
        returns (uint256)
    {
        uint256 supply = vaults[asset][rewardId].totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDivUp(supply, totalAssets());
    }

    function previewRedeem(HeliosERC1155 asset, uint256 rewardId,  uint256 shares)
        public
        view
        returns (uint256)
    {
        return convertToAssets(asset, rewardId, shares);
    }

    /*///////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function maxDeposit(address) public view returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public view returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(HeliosERC1155 asset, uint256 rewardId, address owner)
        public
        view
        returns (uint256)
    {
        return convertToAssets(asset, rewardId, balanceLocked[owner][rewardId]);
    }

    function maxRedeem(uint256 rewardId, address owner)
        public
        view
        returns (uint256)
    {
        return balanceLocked[owner][rewardId];
    }

    /*///////////////////////////////////////////////////////////////
                         INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(
        HeliosERC1155 asset,
        uint256 assets,
        uint256 shares
    ) internal {}

    function afterDeposit(
        HeliosERC1155 asset,
        uint256 assets,
        uint256 shares
    ) internal {}
}
