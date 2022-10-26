pragma solidity ^0.8.7;

/// @notice An error used to indicate that an action could not be completed because either the `msg.sender` or
///         `msg.origin` is not authorized.
error StoaActivator__Unauthorized();

/// @notice An error used to indicate that an action could not be completed because of invalid amount zero entered.
error StoaActivator__NotAllowedZeroValue();

/// @notice An error used to indicate that an action could not be completed because of invalid amount entered.
error StoaActivator__NotValidAmount();