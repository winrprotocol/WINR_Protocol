// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface IReferralStorage {
    struct Tier {
        uint256 WLPRate; // e.g. 2400 for 24%
        uint256 vWINRRate; // 5000 for 50%
    }
    event SetWithdrawInterval(uint256 timeInterval);
    event SetHandler(address handler, bool isActive);
    event SetPlayerReferralCode(address account, bytes32 code);
    event SetTier(uint256 tierId, uint256 WLPRate, uint256 vWINRRate);
    event SetReferrerTier(address referrer, uint256 tierId);
    event RegisterCode(address account, bytes32 code);
    event SetCodeOwner(address account, address newAccount, bytes32 code);
    event GovSetCodeOwner(bytes32 code, address newAccount);
    event Claim(address referrer, uint256 wlpAmount);
    event Reward(
        address referrer,
        address player,
        address token,
        uint256 amount,
        uint256 rebateAmount
    );
    event RewardRemoved(
        address referrer,
        address player,
        address token,
        uint256 amount,
        bool isFully
    );
    event VaultUpdated(address vault);
    event VaultUtilsUpdated(address vaultUtils);
    event WLPManagerUpdated(address wlpManager);
    event SyncTokens();
    event TokenTransferredByTimelock(
        address token,
        address recipient,
        uint256 amount
    );
    event DeleteAllWhitelistedTokens();
    event TokenAddedToWhitelist(address addedTokenAddress);
    event AddReferrerToBlacklist(address referrer, bool setting);
    event ReferrerBlacklisted(address referrer);
    event NoRewardToSet(address player);
    event SetVestedWINRRate(uint256 vWINRRate);

    function codeOwners(bytes32 _code) external view returns (address);

    function playerReferralCodes(
        address _account
    ) external view returns (bytes32);

    function referrerTiers(address _account) external view returns (uint256);

    function getPlayerReferralInfo(
        address _account
    ) external view returns (bytes32, address);

    function setPlayerReferralCode(address _account, bytes32 _code) external;

    function setTier(uint256 _tierId, uint256 _WLPRate) external;

    function setReferrerTier(address _referrer, uint256 _tierId) external;

    function govSetCodeOwner(bytes32 _code, address _newAccount) external;

    function getReferrerTier(
        address _referrer
    ) external view returns (Tier memory tier_);

    function getPlayerVestedWINRRate(
        address _account
    ) external view returns (uint256);
}
