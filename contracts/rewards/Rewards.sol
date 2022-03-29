// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {ERC1155} from "@rari-capital/solmate/src/tokens/ERC1155.sol";
import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

import {IHelios} from "../interfaces/IHelios.sol";

/// @notice Minimal ERC4626-style tokenized Vault implementation with ERC1155 accounting.
/// @author Modified from Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/mixins/ERC4626.sol)
abstract contract Rewards is ERC1155 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*///////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Create(ERC20 indexed asset, uint256 id);

    event Deposit(
        address indexed caller, 
        address indexed owner, 
        ERC20 indexed asset, 
        uint256 assets, 
        uint256 shares
    );

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        ERC20 asset,
        uint256 assets,
        uint256 shares
    );

    IHelios helios;
    constructor(IHelios _helios) {
        helios = _helios;
    }

    /*///////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public totalSupply;

    mapping(ERC20 => Vault) public vaults;

    struct Vault {
        uint256 id;
        uint256 totalSupply;
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice ALLOW ONLY HELIOS TO CREATE! constructor
    /// Only one Vault per reward token, but infinite of Vaults with diff rTokens
    /// This creates a case where one reward token can exist in multiple vaults
    function create(ERC20 asset) public virtual returns (uint256 id) {
        require(vaults[asset].id == 0, "CREATED");
        require(msg.sender == address(helios), "AUTH");
        
        // cannot overflow on human timescales
        unchecked {
            id = ++totalSupply;
        }

        vaults[asset].id = id;

        emit Create(asset, id);
    }

    /// @notice IF MULTIPLE POOLS FOR REWARD, ROUTE!
    function deposit(
        ERC20 asset, 
        uint256 assets, 
        address receiver
    ) public virtual returns (uint256 shares) {
        require((shares = previewDeposit(asset, assets)) != 0, "ZERO_SHARES");
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, vaults[asset].id, shares, "");

        vaults[asset].totalSupply += shares;

        emit Deposit(msg.sender, receiver, asset, assets, shares);

        afterDeposit(asset, assets, shares);
    }

    function mint(
        ERC20 asset, 
        uint256 shares, 
        address receiver
    ) public virtual returns (uint256 assets) {
        assets = previewMint(asset, shares); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, vaults[asset].id, shares, "");

        vaults[asset].totalSupply += shares;

        emit Deposit(msg.sender, receiver, asset, assets, shares);

        afterDeposit(asset, assets, shares);
    }

    function withdraw(
        ERC20 asset,
        uint256 assets,
        address receiver,
        address owner
    ) public virtual returns (uint256 shares) {
        shares = previewWithdraw(asset, assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) require(isApprovedForAll[owner][msg.sender], "NOT_OPERATOR");

        beforeWithdraw(asset, assets, shares);

        _burn(owner, vaults[asset].id, shares);

        vaults[asset].totalSupply -= shares;

        emit Withdraw(msg.sender, receiver, owner, asset, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    function redeem(
        ERC20 asset,
        uint256 shares,
        address receiver,
        address owner
    ) public virtual returns (uint256 assets) {
        if (msg.sender != owner) require(isApprovedForAll[owner][msg.sender], "NOT_OPERATOR");

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(asset, shares)) != 0, "ZERO_ASSETS");

        beforeWithdraw(asset, assets, shares);

        _burn(owner, vaults[asset].id, shares);

        vaults[asset].totalSupply -= shares;

        emit Withdraw(msg.sender, receiver, owner, asset, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    /*///////////////////////////////////////////////////////////////
                           ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view virtual returns (uint256);

    function convertToShares(ERC20 asset, uint256 assets) public view virtual returns (uint256) {
        uint256 supply = vaults[asset].totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDivDown(supply, totalAssets());
    }

    function convertToAssets(ERC20 asset, uint256 shares) public view virtual returns (uint256) {
        uint256 supply = vaults[asset].totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDivDown(totalAssets(), supply);
    }

    function previewDeposit(ERC20 asset, uint256 assets) public view virtual returns (uint256) {
        return convertToShares(asset, assets);
    }

    function previewMint(ERC20 asset, uint256 shares) public view virtual returns (uint256) {
        uint256 supply = vaults[asset].totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDivUp(totalAssets(), supply);
    }

    function previewWithdraw(ERC20 asset, uint256 assets) public view virtual returns (uint256) {
        uint256 supply = vaults[asset].totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDivUp(supply, totalAssets());
    }

    function previewRedeem(ERC20 asset, uint256 shares) public view virtual returns (uint256) {
        return convertToAssets(asset, shares);
    }

    /*///////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(ERC20 asset, address owner) public view virtual returns (uint256) {
        return convertToAssets(asset, balanceOf[owner][vaults[asset].id]);
    }

    function maxRedeem(ERC20 asset, address owner) public view virtual returns (uint256) {
        return balanceOf[owner][vaults[asset].id];
    }

    /*///////////////////////////////////////////////////////////////
                         INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(ERC20 asset, uint256 assets, uint256 shares) internal virtual {}

    function afterDeposit(ERC20 asset, uint256 assets, uint256 shares) internal virtual {}
}

