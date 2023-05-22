// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "solmate/src/utils/ReentrancyGuard.sol";
import "../interfaces/core/ITokenManager.sol";
import "../interfaces/tokens/IWINR.sol";
import "./AccessControlBase.sol";
import "../interfaces/strategies/IMiningStrategy.sol";
import "../interfaces/strategies/IFeeStrategy.sol";
import "../interfaces/stakings/IWINRStaking.sol";
import "../interfaces/referrals/IReferralStorage.sol";
import "../tokens/wlp/interfaces/IBasicFDT.sol";

contract TokenManager is AccessControlBase, ReentrancyGuard {
    using SafeERC20 for IWINR;
    using SafeERC20 for IERC20;
    event Converted(address indexed account, uint256 amount);
    event StrategiesSet(
        IMiningStrategy indexed miningStrategyAddress,
        IFeeStrategy indexed feeStrategyAddress
    );
    event TokensSet(IWINR indexed WINR, IWINR indexed vWINRAddress);
    event WINRStakingSet(IWINRStaking indexed WINRStakingAddress);
    event ReferralStorageSet(IReferralStorage indexed referralStorageAddress);
    /*==================================================== State Variables =============================================================*/
    /// @notice WINR address
    IWINR public immutable WINR;
    /// @notice vWINR address
    IWINR public immutable vWINR;
    /// @notice WLP address
    IBasicFDT public immutable WLP;
    /// @notice WINR staking address
    IWINRStaking public WINRStaking;
    /// @notice referral storage contract
    IReferralStorage public referralStorage;
    /// @notice mining strategy address
    IMiningStrategy public miningStrategy;
    /// @notice fee strategy address
    IFeeStrategy public feeStrategy;
    /// @notice total minted Vested WINR by games
    uint256 public mintedByGames;
    /// @notice max mint amount by games
    uint256 public immutable MAX_MINT;
    /// @notice total coverted amount (WINR => vWINR)
    uint256 public totalConverted;
    /// @notice stores transferable WINR amount
    uint256 public sendableAmount;
    /// @notice accumulative Vested WINR fee amount
    uint256 public accumFee;
    /// @notice divider for minting vested WINR fee
    uint256 public mintDivider;
    /// @notice referral Basis points
    uint256 private constant BASIS_POINTS = 10000;

    /*==================================================== Constructor =============================================================*/
    constructor(
        IWINR _WINR,
        IWINR _vWINR,
        IBasicFDT _WLP,
        uint256 _maxMint,
        address _vaultRegistry,
        address _timelock
    ) AccessControlBase(_vaultRegistry, _timelock) {
        WINR = _WINR;
        vWINR = _vWINR;
        WLP = _WLP;
        MAX_MINT = _maxMint;
        mintDivider = 4;
    }

    /*==================================================== Functions =============================================================*/
    /**
     *
     * @param  _miningStrategy mining strategy address
     * @param _feeStrategy fee strategy address
     * @notice function to set mining and fee strategies
     */
    function setStrategies(
        IMiningStrategy _miningStrategy,
        IFeeStrategy _feeStrategy
    ) external onlyGovernance {
        miningStrategy = _miningStrategy;
        feeStrategy = _feeStrategy;

        emit StrategiesSet(miningStrategy, feeStrategy);
    }

    /**
     *
     * @param _WINRStaking WINR staking address
     * @notice function to set WINR Staking address
     * @notice grants WINR_STAKING_ROLE to the address
     */
    function setWINRStaking(IWINRStaking _WINRStaking) external onlyGovernance {
        require(address(_WINRStaking) != address(0), "address can not be zero");
        WINRStaking = _WINRStaking;
        emit WINRStakingSet(WINRStaking);
    }

    function setReferralStorage(
        IReferralStorage _referralStorage
    ) external onlyGovernance {
        referralStorage = _referralStorage;

        emit ReferralStorageSet(referralStorage);
    }

    /**
     *
     * @param _mintDivider new divider for minting Vested WINR on gameCall
     */
    function setMintDivider(uint256 _mintDivider) external onlyGovernance {
        mintDivider = _mintDivider;
    }

    /*==================================================== WINR Staking Functions =============================================================*/
    /**
     *
     * @param _from adress of the sender
     * @param _amount amount of Vested WINR to take
     * @notice function to transfer Vested WINR from sender to Token Manager
     */
    function takeVestedWINR(
        address _from,
        uint256 _amount
    ) external nonReentrant onlyProtocol {
        vWINR.safeTransferFrom(_from, address(this), _amount);
    }

    /**
     *
     * @param _from adress of the sender
     * @param _amount amount of WINR to take
     * @notice function to transfer WINR from sender to Token Manager
     */
    function takeWINR(
        address _from,
        uint256 _amount
    ) external nonReentrant onlyProtocol {
        WINR.safeTransferFrom(_from, address(this), _amount);
    }

    /**
     *
     * @param _to adress of the receiver
     * @param _amount amount of Vested WINR to send
     * @notice function to transfer Vested WINR from Token Manager to receiver
     */
    function sendVestedWINR(
        address _to,
        uint256 _amount
    ) external nonReentrant onlyProtocol {
        vWINR.safeTransfer(_to, _amount);
    }

    /**
     *
     * @param _to adress of the receiver
     * @param _amount amount of WINR to send
     * @notice function to transfer WINR from Token Manager to receiver
     */
    function sendWINR(
        address _to,
        uint256 _amount
    ) external nonReentrant onlyProtocol {
        _sendWINR(_to, _amount);
    }

    /**
     *
     * @param _to adress of the receiver
     * @param _amount amount of WINR to mint
     * @notice function to mint WINR to receiver
     */
    function mintWINR(
        address _to,
        uint256 _amount
    ) external nonReentrant onlyProtocol {
        _mintWINR(_to, _amount);
    }

    /**
     *
     * @param _amount amount of Vested WINR to burn
     * @notice function to burn Vested WINR from Token Manager
     */
    function burnVestedWINR(
        uint256 _amount
    ) external nonReentrant onlyProtocol {
        vWINR.burn(_amount);
    }

    /**
     *
     * @param _amount amount of WINR to burn
     * @notice function to burn WINR from Token Manager
     */
    function burnWINR(uint256 _amount) external nonReentrant onlyProtocol {
        WINR.burn(_amount);
    }

    /**
     *
     * @param _to WINIR receiver address
     * @param _amount amount of WINR
     * @notice this function transfers WINR to receiver
     * @notice if the sendable amount is insufficient it mints WINR
     */
    function mintOrTransferByPool(
        address _to,
        uint256 _amount
    ) external nonReentrant onlyProtocol {
        if (sendableAmount >= _amount) {
            sendableAmount -= _amount;
            _sendWINR(_to, _amount);
        } else {
            _mintWINR(_to, _amount);
        }
    }

    /**
     *
     * @param _to WLP receiver address (claim on WINR Staking)
     * @param _amount amount of WLP
     * @notice funtion to transfer WLP from Token Manager to receiver
     */
    function sendWLP(
        address _to,
        uint256 _amount
    ) external nonReentrant onlyProtocol {
        IERC20(WLP).safeTransfer(_to, _amount);
    }

    /**
     *
     * @param _to address of receiver
     * @param _amount amount of WINR
     * @notice internal function to mint WINR
     */
    function _mintWINR(address _to, uint256 _amount) internal {
        WINR.mint(_to, _amount);
    }

    /**
     *
     * @param _to address of receiver
     * @param _amount amount of WINR
     * @notice internal function to transfer WINR
     */
    function _sendWINR(address _to, uint256 _amount) internal {
        WINR.safeTransfer(_to, _amount);
    }

    /**
     * @notice function to share fees with WINR Staking
     * @dev only callable by FEE_COLLECTOR_ROLE
     * @param amount amount of WINR to share
     */
    function share(uint256 amount) external nonReentrant onlyProtocol {
        WINRStaking.share(amount);
    }

    /*==================================================== Conversion =============================================================*/
    /**
     *
     * @param _amount amount of WINR to convert
     * @notice function to convert WINR to Vested WINR
     * @notice takes WINR, mints equivalent amount of Vested WINR
     */
    function convertToken(uint256 _amount) external nonReentrant {
        // Transfer WINR from sender to Token Manager
        WINR.safeTransferFrom(msg.sender, address(this), _amount);
        // Mint equivalent amount of Vested WINR
        vWINR.mint(msg.sender, _amount);
        // Update total converted amount
        totalConverted += _amount;
        // Update sendable amount
        sendableAmount += _amount;

        emit Converted(msg.sender, _amount);
    }

    /*==================================================== Game Functions =============================================================*/
    /**
     *
     * @param _input  address of the input token (weth, dai, wbtc)
     * @param _amount amount of the input token
     * @param _recipient Vested WINR receiver
     * @notice function to mint Vested WINR
     * @notice only games can mint with this function by Vault Manager
     * @notice stores all minted amount in mintedByGames variable
     * @notice can not mint more than MAX_MINT
     */
    function mintVestedWINR(
        address _input,
        uint256 _amount,
        address _recipient
    ) external nonReentrant onlyProtocol returns (uint256 _mintAmount) {
        //mint with mining strategy
        uint256 _feeAmount = feeStrategy.calculate(_input, _amount);
        _mintAmount = miningStrategy.calculate(
            _recipient,
            _feeAmount,
            mintedByGames
        );
        // get referral rate
        uint256 _vWINRRate = referralStorage.getPlayerVestedWINRRate(
            _recipient
        );
        // add vested WINR rate to mint amount
        if (_vWINRRate > 0) {
            _mintAmount += (_mintAmount * _vWINRRate) / BASIS_POINTS;
        }
        // mint Vested WINR
        if (mintedByGames + _mintAmount > MAX_MINT) {
            _mintAmount = MAX_MINT - mintedByGames;
        }

        vWINR.mint(_recipient, _mintAmount);
        accumFee += _mintAmount / mintDivider;
        mintedByGames += _mintAmount;
    }

    /**
     * @notice function to mint Vested WINR
     * @notice mint amount comes from minted by games( check mintVestedWINR function)
     */
    function mintFee() external nonReentrant onlySupport {
        vWINR.mint(address(WLP), accumFee);
        WLP.updateFundsReceived_VWINR();
        accumFee = 0;
    }

    /**
     *
     * @param _input address of the input token
     * @param _amount amount of the input token
     * @notice function to increase volume on mining strategy
     * @notice games can increase volume by Vault Manager
     */
    function increaseVolume(
        address _input,
        uint256 _amount
    ) external nonReentrant onlyProtocol {
        miningStrategy.increaseVolume(_input, _amount);
    }

    /**
     *
     * @param _input address of the input token
     * @param _amount amount of the input token
     * @notice function to decrease volume on mining strategy
     * @notice games can decrease volume by Vault Manager
     */
    function decreaseVolume(
        address _input,
        uint256 _amount
    ) external nonReentrant onlyProtocol {
        miningStrategy.decreaseVolume(_input, _amount);
    }
}
