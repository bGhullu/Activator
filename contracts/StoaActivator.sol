// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin/contracts/token/ERC20/IERC20.sol";

error Activator__NotAuthorizedUser();
error Activator__NotAllowedZeroValue();

contract Activator {
    struct DepositSyntheticAsset {
        address depositer;
        address token;
        uint256 amount;
    }

    event DepositRequest(address user, address synToken, uint256 amount);
    event Withdraw(address user, address synToken, uint256 amount);

    DepositSyntheticAsset[] private depositToActivator;

    function deposit(address synToken, uint256 amount) external {
        if (amount == 0) {
            revert Activator__NotAllowedZeroValue();
        }
        IERC20(synToken).transferFrom(msg.sender, address(this), amount);
        DepositSyntheticAsset memory depositAsset = DepositSyntheticAsset(
            msg.sender,
            synToken,
            amount
        );
        depositToActivator.push(depositAsset);
        emit DepositRequest(msg.sender, synToken, amount);
    }

    function withdraw(address synToken, uint256 amount) external {
        DepositSyntheticAsset[]
            memory _depositSyntheticAsset = depositToActivator;
        for (uint i = 0; i < _depositSyntheticAsset.length; i++) {
            if (!_depositSyntheticAsset[i].depositer == msg.sender) {
                revert Activator__NotAuthorizedUser();
            }
            IERC20(synToken).tranfer(address(this), msg.sender, amount);
            emit Withdraw(msg.sender, synToken, amount);
        }
    }
}
