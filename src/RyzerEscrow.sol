// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IRyzerRealEstateToken} from "./interfaces/IRyzerRealEstateToken.sol";

/// @title RyzerEscrow
/// @notice Dual-stable-coin (USDT / USDC) escrow & dispute engine for the Ryzer ecosystem
/// @dev    Uses UUPS proxies, tight packing, bitmaps, custom errors
contract RyzerEscrow is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    /*//////////////////////////////////////////////////////////////
                                ROLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /*//////////////////////////////////////////////////////////////
                          CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////////////*/
    uint8 private constant _STABLE_DECIMALS = 6;
    uint256 private constant _DISPUTE_TIMEOUT = 7 days;
    uint256 private constant _DISPUTE_EXPIRATION = 30 days;
    uint8 private constant _MIN_SIGNATURES = 2;
    uint16 private constant _MAX_REASON_LEN = 256;

    /*//////////////////////////////////////////////////////////////
                          ENUMS & STRUCTS
    //////////////////////////////////////////////////////////////*/
    enum Asset {
        USDT,
        USDC
    }

    struct Deposit {
        address buyer;
        uint128 amount; // fits $3.4T
        Asset token; // 0 or 1
        bytes32 assetId;
    }

    struct Dispute {
        address buyer;
        Asset token;
        uint128 amount;
        bytes32 assetId;
        bytes32 orderId;
        uint48 disputeTimeout;
        uint48 disputeExpiration;
        address resolvedTo;
        bool resolved;
    }

    /*//////////////////////////////////////////////////////////////
                           STATE – SLOTS 0-3
    //////////////////////////////////////////////////////////////*/
    using SafeERC20 for IERC20;

    IERC20 public usdt;
    IERC20 public usdc;
    IRyzerRealEstateToken public project;

    uint32 public disputeNonce; // globally unique dispute id
    uint8 public requiredSigs; // 1B
    uint128 public dividendPoolUSDT;
    uint128 public dividendPoolUSDC;

    /*//////////////////////////////////////////////////////////////
                       MAPPINGS / BITMAP STORAGE
    //////////////////////////////////////////////////////////////*/
    mapping(bytes32 => Deposit) public deposits;
    mapping(bytes32 => Dispute) public disputes; // disputeId => Dispute
    mapping(bytes32 => uint256) public releaseSigCount;
    mapping(bytes32 => uint256) public disputeSigCount;
    mapping(bytes32 => mapping(address => bool)) public releaseSigned;
    mapping(bytes32 => mapping(address => bool)) public disputeSigned;

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/
    event EscrowInitialized(address indexed usdt, address indexed usdc, address indexed project);
    event Deposited(
        bytes32 indexed orderId, address indexed buyer, Asset indexed token, uint128 amount, bytes32 assetId
    );
    event Released(bytes32 indexed orderId, address indexed to, Asset indexed token, uint128 amount);
    event DividendDeposited(address indexed depositor, Asset indexed token, uint128 amount);
    event DividendDistributed(address indexed recipient, Asset indexed token, uint128 amount);
    event DisputeRaised(
        bytes32 indexed disputeId, address indexed buyer, Asset indexed token, uint128 amount, string reason
    );
    event DisputeSigned(bytes32 indexed disputeId, address indexed signer);
    event DisputeResolved(bytes32 indexed disputeId, address indexed resolvedTo, Asset indexed token, uint128 amount);
    event EmergencyWithdrawal(address indexed recipient, Asset indexed token, uint128 amount);
    event CoreContractsSet(address indexed usdt, address indexed usdc, address indexed project);
    event RequiredSigsSet(uint8 requiredSigs);

    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAddress();
    error InvalidAmount();
    error InvalidDecimals();
    error DepositNotFound();
    error DisputeNotFound();
    error DisputeExpired();
    error DisputeTimeoutNotMet();
    error AlreadySigned();
    error InsufficientFunds();
    error Unauthorized();
    error ZeroValue();
    error InvalidToken();
    error InvalidParameter();

    /*//////////////////////////////////////////////////////////////
                              INITIALIZER
    //////////////////////////////////////////////////////////////*/
    function initialize(address _usdt, address _usdc, address _project, address _owner) external initializer {
        if (_usdt == address(0) || _usdc == address(0) || _project == address(0)) revert InvalidAddress();
        if (
            IERC20Metadata(_usdt).decimals() != _STABLE_DECIMALS || IERC20Metadata(_usdc).decimals() != _STABLE_DECIMALS
        ) revert InvalidDecimals();

        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        usdt = IERC20(_usdt);
        usdc = IERC20(_usdc);
        project = IRyzerRealEstateToken(_project);
        requiredSigs = _MIN_SIGNATURES;

        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(ADMIN_ROLE, _owner);

        emit EscrowInitialized(_usdt, _usdc, _project);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN – CONFIGURATION
    //////////////////////////////////////////////////////////////*/
    function setCoreContracts(address _usdt, address _usdc, address _project) external onlyRole(ADMIN_ROLE) {
        if (_usdt == address(0) || _usdc == address(0) || _project == address(0)) revert InvalidAddress();
        if (
            IERC20Metadata(_usdt).decimals() != _STABLE_DECIMALS || IERC20Metadata(_usdc).decimals() != _STABLE_DECIMALS
        ) revert InvalidDecimals();

        usdt = IERC20(_usdt);
        usdc = IERC20(_usdc);
        project = IRyzerRealEstateToken(_project);
        emit CoreContractsSet(_usdt, _usdc, _project);
    }

    function setRequiredSignatures(uint8 _sigs) external onlyRole(ADMIN_ROLE) {
        if (_sigs == 0) revert ZeroValue();
        requiredSigs = _sigs;
        emit RequiredSigsSet(_sigs);
    }

    /*//////////////////////////////////////////////////////////////
                           USER – DEPOSIT
    //////////////////////////////////////////////////////////////*/
    function deposit(bytes32 orderId, address buyer, uint128 amount, Asset token, bytes32 assetId)
        external
        nonReentrant
        whenNotPaused
    {
        (,,, address projectOwner_) = project.getProjectDetails();

        if (buyer == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (token > Asset.USDC) revert InvalidToken(); // 0 or 1 only

        deposits[orderId] = Deposit(buyer, amount, token, assetId);

        IERC20 paymentToken = token == Asset.USDT ? usdt : usdc;
        SafeERC20.safeTransferFrom(paymentToken, buyer, address(this), amount);

        emit Deposited(orderId, buyer, token, amount, assetId);
    }

    /*//////////////////////////////////////////////////////////////
                        SIGNATURE-BASED RELEASE
    //////////////////////////////////////////////////////////////*/
    function signRelease(bytes32 orderId, address to, uint128 amount)
        external
        nonReentrant
        onlyRole(ADMIN_ROLE)
        whenNotPaused
    {
        Deposit storage dep = deposits[orderId];
        if (dep.buyer == address(0)) revert DepositNotFound();
        if (to == address(0)) revert InvalidAddress();
        if (amount == 0 || amount > dep.amount) revert InvalidAmount();
        if (releaseSigned[orderId][msg.sender]) revert AlreadySigned();

        releaseSigned[orderId][msg.sender] = true;
        uint256 sigs = ++releaseSigCount[orderId];

        if (sigs >= requiredSigs) {
            dep.amount -= amount;
            IERC20 paymentToken = dep.token == Asset.USDT ? usdt : usdc;
            paymentToken.safeTransfer(to, amount);

            if (dep.amount == 0) delete deposits[orderId];
            emit Released(orderId, to, dep.token, amount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         DIVIDEND MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    function depositDividend(Asset token, uint128 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroValue();
        IERC20 _t = token == Asset.USDT ? usdt : usdc;
        _t.safeTransferFrom(msg.sender, address(this), amount);

        if (token == Asset.USDT) dividendPoolUSDT += amount;
        else dividendPoolUSDC += amount;

        emit DividendDeposited(msg.sender, token, amount);
    }

    function distributeDividend(address recipient, Asset token, uint128 amount)
        external
        nonReentrant
        onlyRole(ADMIN_ROLE)
        whenNotPaused
    {
        if (recipient == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroValue();

        uint128 pool = token == Asset.USDT ? dividendPoolUSDT : dividendPoolUSDC;
        if (pool < amount) revert InsufficientFunds();

        token == Asset.USDT ? dividendPoolUSDT -= amount : dividendPoolUSDC -= amount;

        IERC20(token == Asset.USDT ? address(usdt) : address(usdc)).safeTransfer(recipient, amount);

        emit DividendDistributed(recipient, token, amount);
    }

    /*//////////////////////////////////////////////////////////////
                          DISPUTE LIFECYCLE
    //////////////////////////////////////////////////////////////*/
    function raiseDispute(bytes32 orderId, string calldata reason)
        external
        nonReentrant
        whenNotPaused
        returns (bytes32 disputeId)
    {
        Deposit storage dep = deposits[orderId];
        if (dep.buyer == address(0)) revert DepositNotFound();
        (,,, address projectOwner) = project.getProjectDetails();
        if (bytes(reason).length == 0 || bytes(reason).length > _MAX_REASON_LEN) revert InvalidParameter();

        disputeId = keccak256(abi.encodePacked(block.timestamp, dep.buyer, orderId, disputeNonce++));
        disputes[disputeId] = Dispute({
            buyer: dep.buyer,
            token: dep.token,
            amount: dep.amount,
            assetId: dep.assetId,
            orderId: orderId,
            disputeTimeout: uint48(block.timestamp + _DISPUTE_TIMEOUT),
            disputeExpiration: uint48(block.timestamp + _DISPUTE_EXPIRATION),
            resolvedTo: address(0),
            resolved: false
        });

        emit DisputeRaised(disputeId, dep.buyer, dep.token, dep.amount, reason);
    }

    function signDisputeResolution(bytes32 disputeId, address resolvedTo)
        external
        nonReentrant
        onlyRole(ADMIN_ROLE)
        whenNotPaused
    {
        Dispute storage d = disputes[disputeId];
        if (d.buyer == address(0)) revert DisputeNotFound();
        if (d.resolved) revert DisputeNotFound();
        if (block.timestamp < d.disputeTimeout) revert DisputeTimeoutNotMet();
        if (block.timestamp > d.disputeExpiration) revert DisputeExpired();
        if (resolvedTo == address(0)) revert InvalidAddress();
        if (disputeSigned[disputeId][msg.sender]) revert AlreadySigned();

        disputeSigned[disputeId][msg.sender] = true;
        uint256 sigs = ++disputeSigCount[disputeId];

        if (sigs >= requiredSigs) {
            IERC20 _t = d.token == Asset.USDT ? usdt : usdc;
            if (_t.balanceOf(address(this)) < d.amount) revert InsufficientFunds();

            d.resolved = true;
            d.resolvedTo = resolvedTo;
            _t.safeTransfer(resolvedTo, d.amount);

            delete deposits[d.orderId];
            emit DisputeResolved(disputeId, resolvedTo, d.token, d.amount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY WITHDRAWAL
    //////////////////////////////////////////////////////////////*/
    function emergencyWithdraw(address recipient, Asset token, uint128 amount)
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
    {
        if (recipient == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroValue();

        IERC20 _t = token == Asset.USDT ? usdt : usdc;
        if (_t.balanceOf(address(this)) < amount) revert InsufficientFunds();

        _t.safeTransfer(recipient, amount);
        emit EmergencyWithdrawal(recipient, token, amount);
    }

    /*//////////////////////////////////////////////////////////////
                         PAUSABILITY & UPGRADES
    //////////////////////////////////////////////////////////////*/
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address newImpl) internal view override onlyRole(ADMIN_ROLE) {
        if (newImpl.code.length == 0) revert InvalidAddress();
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW HELPERS
    //////////////////////////////////////////////////////////////*/
    function getDisputeStatus(bytes32 id) external view returns (Dispute memory) {
        return disputes[id];
    }

    function dividendPoolBalance(Asset token) external view returns (uint128) {
        return token == Asset.USDT ? dividendPoolUSDT : dividendPoolUSDC;
    }

    function getDepositStatus(bytes32 id) external view returns(Deposit memory){
        return deposits[id];
    }
}
