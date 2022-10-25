// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin/contracts/token/ERC20/IERC20.sol";

error StoaActivator__NotAuthorizedUser();
error StoaActivator__NotAllowedZeroValue();
error StoaActivator__NotValidAmount();

contract StoaActivator {
    struct DepositSyntheticAsset {
        address depositer;
        uint256 amount;
    }

    event Deposit(address user, uint256 amount);
    event Withdraw(address user, uint256 amount);

    address private immutable i_synToken;
    address private immutable i_underlying;

    DepositSyntheticAsset[] private depositToStoaActivator;

    constructor(address synToken, address underlying) {
        i_synToke = synToken;
        i_underlying = underlying;
    }

    function deposit(uint256 amount) external {
        if (amount == 0) {
            revert StoaActivator__NotAllowedZeroValue();
        }
        IERC20(i_synToken).transferFrom(msg.sender, address(this), amount);
        DepositSyntheticAsset memory depositAsset = DepositSyntheticAsset(
            msg.sender,
            amount
        );
        depositToStoaActivator.push(depositAsset);
        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        DepositSyntheticAsset[]
            memory _depositSyntheticAsset = depositToStoaActivator;
        for (uint i = 0; i < _depositSyntheticAsset.length; i++) {
            if (!_depositSyntheticAsset[i].depositer == msg.sender) {
                revert StoaActivator__NotAuthorizedUser();
            }
            uint index = i;
            if (_depositSyntheticAsset[index].amount < amount) {
                revert StoaActivator__NotValidAmount();
            }
            IERC20(synToken).tranfer(address(this), msg.sender, amount);
            emit Withdraw(msg.sender, synToken, amount);
        }
    }
}
