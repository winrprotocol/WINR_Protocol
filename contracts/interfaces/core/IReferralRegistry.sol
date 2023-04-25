// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IReferralRegistry {
	function isReferred(address _playerAddress) external view returns (bool);
}
