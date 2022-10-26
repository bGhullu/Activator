// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "./libraries/TokenUtils.sol";
import "./interfaces/IERC20Burnable.sol";
import "./bsae/Error.sol";

/// @title StoaActivator
///
/// @notice A contract which facilitates the exchange of synthetic assets for their underlying
//          asset. This contract guarantees that synthetic assets are exchanged exactly 1:1
//          for the underlying asset.

contract StoaActivator is ReentrancyGuardUpgradeable{


    struct DepositSyntheticAsset {
        address depositer;
        uint256 amount;
    }

    struct AccountStatus{
        address owner;
        uint256 exchanged;
        uint256 unexchanged;
    }

    event Deposit(address user, uint256 amount);

    event Withdraw(address user, uint256 amount);

    /// @dev the synthetic token to be transmuted
    address private immutable i_syntheticToken;

    /// @dev the underlyinToken token to be received
    address private immutable i_underlyinToken;

    /// @dev The amount of decimal places needed to normalize collateral to debtToken
     uint256 public override conversionFactor;
    
    /// @dev contract pause state
    bool public isPaused;

    DepositSyntheticAsset[] private depositToStoaActivator;

    constructor() {}


    function initialize(
        address _syntheticToken,
        address _underlyingToken,
    ) external initializer {
        _setupRole(ADMIN, msg.sender);
        _setRoleAdmin(ADMIN, ADMIN);
        _setRoleAdmin(SENTINEL, ADMIN);
        i_syntheticToken = _syntheticToken;
        i_underlyingToken = _underlyingToken;
        uint8 debtTokenDecimals = TokenUtils.expectDecimals(i_syntheticToken);
        uint8 underlyingTokenDecimals = TokenUtils.expectDecimals(i_underlyingToken);
        conversionFactor = 10**(debtTokenDecimals - underlyingTokenDecimals);
        isPaused = false;
    }

    /// @dev A modifier which checks if caller is a sentinel or admin.
    modifier onlySentinelOrAdmin() {
         if (!hasRole(SENTINEL, msg.sender) && !hasRole(ADMIN, msg.sender)) {
        revert StoaActivator__Unauthorized();
        }
        _;
    }

    function _onlyAdmin() internal view {
        if (!hasRole(ADMIN, msg.sender)) {
        revert StoaActivator__Unauthorized();
        }
    }

    /// @dev A modifier which checks whether the Activator is unpaused.
    modifier notPaused() {
        if (isPaused) {
        revert IllegalState();
        }
        _;
    }

    function setPause(bool pauseState) external onlySentinelOrAdmin {
        isPaused = pauseState;
        emit Paused(isPaused);
    }

    function deposit(uint256 amount) external nonReentrant{
        if (amount == 0) {
            revert StoaActivator__NotAllowedZeroValue();
        }
        TokenUtils.safeTransferFrom(syntheticToken, msg.sender, address(this), amount);
        DepositSyntheticAsset memory depositAsset = DepositSyntheticAsset(
            msg.sender,
            amount
        );
        depositToStoaActivator.push(depositAsset);
        emit Deposit(msg.sender, amount);
    }

    function checkClaimer()internal {
         DepositSyntheticAsset[]
            memory _depositSyntheticAsset = depositToStoaActivator;
        for (uint i = 0; i < _depositSyntheticAsset.length; i++) {
            if (!_depositSyntheticAsset[i].depositer == msg.sender) {
                revert StoaActivator__Unauthorized();
            }
            uint index = i;
            if (_depositSyntheticAsset[index].amount < amount) {
                revert StoaActivator__NotValidAmount();
            }
    }

    function withdraw(uint256 amount) external nonReentrant {
            checkClaimer();
            TokenUtils.safeTransfer(syntheticToken, recipient, amount);
            emit Withdraw(msg.sender, syntheticToken, amount);
        }
    }

    function claim(uint256 amount) external{
            checkClaimer();
            IERC20(i_underlyinToken).transfer(address(this), msg.sender,amount);
            TokenUtils.safeBurn(syntheticToken, _normalizeunderlyinTokenTokensToDebt(amount));
    }

    /// @dev Normalize `amount` of `underlyingToken` to a value which is comparable to units of the debt token.
    ///
    /// @param amount The amount of the debt token.
    ///
    /// @return The normalized amount.

    function _normalizeUnderlyingTokensToDebt(uint256 amount) internal view returns (uint256) {
    return amount * conversionFactor;
    }

}
