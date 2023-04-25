// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ITokenManager {
	function takeVestedWINR(address _from, uint256 _amount) external;

	function takeWINR(address _from, uint256 _amount) external;

	function sendVestedWINR(address _to, uint256 _amount) external;

	function sendWINR(address _to, uint256 _amount) external;

	function burnVestedWINR(uint256 _amount) external;

	function burnWINR(uint256 _amount) external;

	function mintWINR(address _to, uint256 _amount) external;

	function sendWLP(address _to, uint256 _amount) external;

	function mintOrTransferByPool(address _to, uint256 _amount) external;

	function mintVestedWINR(address _input, uint256 _amount, address _recipient) external;

	function mintedByGames() external returns (uint256);

	function MAX_MINT() external returns (uint256);

	function share(uint256 amount) external;
}
