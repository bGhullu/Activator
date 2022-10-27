// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./libraries/TokenUtils.sol";
import "./base/Error.sol";

/**
 * @title StoaActivator
 * @author Stoa
 * @notice A contract which facilitates the exchange of synthetic assets for their underlying
 * asset. This contract guarantees that synthetic assets are exchanged exactly 1:1
 * for the underlying asset.
 */

contract StoaActivator is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    struct DepositSyntheticAsset {
        address user;
        uint256 unclaimedAmount;
        uint256 claimedAmount;
    }

    /**
     * @notice Emitted when the system is paused or unpaused.
     * @param flag `true` if the system has been paused, `false` otherwise.
     */
    event Paused(bool flag);

    event Deposit(address indexed user, uint256 unclaimedAmount);

    event Withdraw(address indexed user, uint256 unclaimedAmount, uint256 claimedAmount);

    // @dev The identifier of the role which maintains other roles.
    bytes32 public constant ADMIN = keccak256("ADMIN");

    // @dev The identifier of the sentinel role
    bytes32 public constant SENTINEL = keccak256("SENTINEL");

    // @dev the synthetic token to be exchanged
    address public syntheticToken;

    // @dev the underlyinToken token to be received
    address public underlyingToken;

    // @dev The amount of decimal places needed to normalize collateral to debtToken
    uint256 public conversionFactor;

    // @dev contract pause state
    bool public isPaused;

    DepositSyntheticAsset[] private depositToStoaActivator;

    constructor() {}

    function initialize(address _syntheticToken, address _underlyingToken) external initializer {
        _setupRole(ADMIN, msg.sender);
        _setRoleAdmin(ADMIN, ADMIN);
        _setRoleAdmin(SENTINEL, ADMIN);
        syntheticToken = _syntheticToken;
        underlyingToken = _underlyingToken;
        uint8 debtTokenDecimals = TokenUtils.expectDecimals(syntheticToken);
        uint8 underlyingTokenDecimals = TokenUtils.expectDecimals(underlyingToken);
        conversionFactor = 10**(debtTokenDecimals - underlyingTokenDecimals);
        isPaused = false;
    }

    //@dev A modifier which checks if caller is a sentinel or admin.
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

    // @dev A modifier which checks whether the Activator is unpaused.
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

    function deposit(uint256 amount) external nonReentrant {
        if (amount == 0) {
            revert StoaActivator__NotAllowedZeroValue();
        }
        TokenUtils.safeTransferFrom(syntheticToken, msg.sender, address(this), amount);
        _existingUser(msg.sender, amount);
        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        uint256 index = _validUser(msg.sender, amount);
        TokenUtils.safeTransfer(syntheticToken, msg.sender, amount);
        uint256 _unclaimedAmount = depositToStoaActivator[index].unclaimedAmount - amount;
        depositToStoaActivator[index].unclaimedAmount = _unclaimedAmount;
        _removeUser(_unclaimedAmount, index);
        TokenUtils.safeTransfer(syntheticToken, msg.sender, amount);
        emit Withdraw(msg.sender, _unclaimedAmount, amount);
    }

    function claim(uint256 amount) external nonReentrant {
        uint256 index = _validUser(msg.sender, amount);
        uint256 _unclaimedAmount = depositToStoaActivator[index].unclaimedAmount - amount;
        depositToStoaActivator[index].claimedAmount = amount;
        depositToStoaActivator[index].unclaimedAmount = _unclaimedAmount;
        _removeUser(_unclaimedAmount, index);
        TokenUtils.safeTransfer(underlyingToken, msg.sender, amount);
        TokenUtils.safeBurn(syntheticToken, _normalizeUnderlyinTokensToDebt(amount));
    }

    /**
     * @dev Checks the msg.sender is valid user.
     * @notice Reverts if msg.sender is not.
     */

    function _validUser(address _user, uint256 amount) internal view returns (uint256) {
        uint256 index;
        DepositSyntheticAsset[] memory _depositSyntheticAsset = depositToStoaActivator;
        for (uint256 i = 0; i < _depositSyntheticAsset.length; i++) {
            if (_depositSyntheticAsset[i].user != _user) {
                revert StoaActivator__Unauthorized();
            }
            index = i;

            if (_depositSyntheticAsset[index].unclaimedAmount < amount) {
                revert StoaActivator__InvalidAmount();
            }
        }
        return index;
    }

    /**
     * @dev Checks if the msg.sender is existing Activator.
     * @notice Update the balance if it is else create a new index for the user.
     */

    function _existingUser(address _user, uint256 amount) internal {
        DepositSyntheticAsset[] memory _depositSyntheticAsset = depositToStoaActivator;
        for (uint256 i = 0; i < _depositSyntheticAsset.length; i++) {
            if (_depositSyntheticAsset[i].user == _user) {
                uint256 updatedUnclaimedAmount = depositToStoaActivator[i].unclaimedAmount + amount;
                depositToStoaActivator[i].unclaimedAmount = updatedUnclaimedAmount;
            } else {
                DepositSyntheticAsset memory depositAsset = DepositSyntheticAsset(_user, amount, 0);
                depositToStoaActivator.push(depositAsset);
            }
        }
    }

    /**
     * @dev Checks the whitelist for msg.sender.
     * @notice Reverts if msg.sender is not in the whitelist.
     */

    function _removeUser(uint256 unclaimedAmount, uint256 index) internal {
        if (unclaimedAmount == 0) {
            depositToStoaActivator[index] = depositToStoaActivator[
                depositToStoaActivator.length - 1
            ];
            depositToStoaActivator.pop();
        }
    }

    /**
     * @dev Normalize `amount` of `underlyingToken` to a value which is comparable to units of the debt token.
     * @param amount The amount of the debt token.
     * @return The normalized amount.
     */

    function _normalizeUnderlyinTokensToDebt(uint256 amount) internal view returns (uint256) {
        return amount * conversionFactor;
    }
}
