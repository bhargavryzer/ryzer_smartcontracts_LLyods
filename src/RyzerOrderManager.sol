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

import {IRyzerEscrow} from "./interfaces/IRyzerEscrow.sol";
import {IRyzerRealEstateToken} from "./interfaces/IRyzerRealEstateToken.sol";

/*─────────────────────────────────────────────────────────────────────────────
  CONTRACT
─────────────────────────────────────────────────────────────────────────────*/
contract RyzerOrderManager is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    /*────────────────────────────── ROLES ───────────────────────────────*/
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /*────────────────────────────── CONSTANTS ─────────────────────────────*/
    uint8 private constant _DEC_6 = 6;
    uint8 private constant _DEC_18 = 18;
    uint48 private constant _ORDER_EXPIRATION = 7 days;
    uint48 private constant _CANCELLATION_DELAY = 1 days;
    uint48 private constant _RELEASE_TIMELOCK = 7 days;
    uint8 private constant _PRICE_DP = 18;
    uint256 private constant _MAX_ORDER = 1_000_000e18;
    uint256 private constant _BPS = 10_000;

    /*────────────────────────────── ENUMS ────────────────────────────────*/
    enum OrderStatus {
        Pending,
        DocumentsSigned,
        Finalized,
        Cancelled
    }
    enum Currency {
        USDT,
        USDC,
        RYZER
    }
    enum Asset {
        USDT,
        USDC
    }

    /*────────────────────────────── STRUCTS ───────────────────────────────*/
    struct Order {
        address buyer;
        uint128 amountTokens; // RWA tokens to mint
        uint128 totalCurrency; // total stable-coins incl. fees
        uint128 fees; // explicit fees
        bytes32 assetId;
        uint48 createdAt;
        uint48 orderExpiry;
        uint48 releaseAfter;
        OrderStatus status;
        Currency currency;
        bool released;
    }

    struct CurrencyInfo {
        IERC20 token;
        uint8 decimals;
        bool active;
    }

    /*────────────────────────────── STORAGE ───────────────────────────────*/
    mapping(Currency => CurrencyInfo) public currencies;
    address public escrow;
    address public project;
    uint8 public requiredSigs;
    uint16 public platformFeeBps;
    address public feeRecipient;

    uint64 private _nonce;
    mapping(bytes32 => Order) public orders;
    mapping(bytes32 => mapping(address => bool)) private _releaseSig;
    mapping(bytes32 => uint8) private _releaseSigCount;

    /*────────────────────────────── EVENTS ────────────────────────────────*/
    event Initialized(address indexed escrow, address indexed project, address indexed owner);
    event CurrencySet(Currency indexed currency, address indexed token, uint8 decimals, bool active);
    event OrderPlaced(
        bytes32 indexed id, address indexed buyer, uint128 tokens, bytes32 assetId, Currency currency, uint128 total
    );
    event DocumentsSigned(bytes32 indexed id);
    event OrderFinalized(bytes32 indexed id);
    event OrderCancelled(bytes32 indexed id, address indexed buyer, uint128 refund);
    event ReleaseSigned(bytes32 indexed id, address indexed signer);
    event FundsReleased(bytes32 indexed id, address indexed to, uint128 amount);
    event StuckOrderResolved(bytes32 indexed id, address indexed buyer, uint128 refund);
    event EmergencyWithdrawal(Currency indexed currency, address indexed to, uint128 amount);
    event ProjectContractsSet(address indexed escrow, address indexed project);
    event RequiredSignaturesSet(uint8 oldVal, uint8 newVal);
    event PlatformFeeSet(uint16 oldFee, uint16 newFee);
    event FeeRecipientSet(address indexed oldRec, address indexed newRec);

    /*────────────────────────────── ERRORS ────────────────────────────────*/
    error BadAddress();
    error BadAmount();
    error BadDecimals();
    error OrderNotFound();
    error OrderExpired();
    error OrderNotPending();
    error OrderNotFinalized();
    error AlreadyReleased();
    error AlreadySigned();
    error Timelock();
    error Delay();
    error Stuck();
    error Unauthorized();
    error CurrencyDisabled();
    error CurrencyNotSet();
    error DepositFailed();
    error BadParameter();
    error InsufficientBalance();
    error InsufficientAllowance();

    /*────────────────────────────── INITIALIZER ───────────────────────────*/
    function initialize(address _escrow, address _project, address _owner, uint8 _sigs) external initializer {
        if (_escrow == address(0) || _project == address(0) || _owner == address(0)) revert BadAddress();
        if (_project.code.length == 0 || _sigs == 0 || _sigs > 10) revert BadParameter();

        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        escrow = _escrow;
        project = _project;
        requiredSigs = _sigs;
        platformFeeBps = 250; // 2.5 %
        feeRecipient = _owner;

        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(ADMIN_ROLE, _owner);
        _grantRole(OPERATOR_ROLE, _owner);

        emit Initialized(_escrow, _project, _owner);
    }

    /*────────────────────────────── ADMIN ────────────────────────────────*/
    function setCurrency(Currency c, address token, bool active) external onlyRole(ADMIN_ROLE) {
        if (token == address(0)) revert BadAddress();
        uint8 d = IERC20Metadata(token).decimals();
        if ((c == Currency.USDT || c == Currency.USDC) && d != _DEC_6 && d != _DEC_18) revert BadDecimals();
        currencies[c] = CurrencyInfo(IERC20(token), d, active);
        emit CurrencySet(c, token, d, active);
    }

    function setProjectContracts(address _escrow, address _project) external onlyRole(DEFAULT_ADMIN_ROLE) {
        escrow = _escrow;
        project = _project;
        emit ProjectContractsSet(_escrow, _project);
    }

    function setRequiredSignatures(uint8 n) external onlyRole(ADMIN_ROLE) {
        if (n == 0 || n > 10) revert BadParameter();
        uint8 old = requiredSigs;
        requiredSigs = n;
        emit RequiredSignaturesSet(old, n);
    }

    function setPlatformFee(uint16 bps) external onlyRole(ADMIN_ROLE) {
        if (bps > 1_000) revert BadParameter(); // ≤ 10 %
        uint16 old = platformFeeBps;
        platformFeeBps = bps;
        emit PlatformFeeSet(old, bps);
    }

    function setFeeRecipient(address a) external onlyRole(ADMIN_ROLE) {
        address old = feeRecipient;
        feeRecipient = a;
        emit FeeRecipientSet(old, a);
    }

    /*────────────────────────────── USER ────────────────────────────────*/
    struct PlaceOrderParams {
        address projectAddress;
        address escrowAddress;
        bytes32 assetId;
        uint128 amountTokens;
        uint256 currencyPrice; // 1 currency = ? USD (18 dp)
        uint128 fees;
        Currency currency;
    }

    function placeOrder(PlaceOrderParams calldata p) external nonReentrant whenNotPaused returns (bytes32 id) {
        _validatePlaceOrder(p);

        CurrencyInfo memory info = currencies[p.currency];
        if (!info.active) revert CurrencyDisabled();

        uint256 price = IRyzerRealEstateToken(p.projectAddress).tokenPrice();
        uint256 value = _toCurrencyDecimals(p.amountTokens * price / p.currencyPrice, _PRICE_DP, info.decimals);
        uint128 platformFee = uint128(value * platformFeeBps / _BPS);
        uint128 total = uint128(value) + platformFee + p.fees;

        _ensureFunds(info.token, msg.sender, total);

        id = keccak256(abi.encode(msg.sender, p.assetId, block.timestamp, _nonce++));
        orders[id] = Order({
            buyer: msg.sender,
            amountTokens: p.amountTokens,
            totalCurrency: total,
            fees: p.fees,
            assetId: p.assetId,
            createdAt: uint48(block.timestamp),
            orderExpiry: uint48(block.timestamp + _ORDER_EXPIRATION),
            releaseAfter: 0,
            status: OrderStatus.Pending,
            currency: p.currency,
            released: false
        });

        info.token.safeTransferFrom(msg.sender, p.escrowAddress, total);

        try IRyzerEscrow(p.escrowAddress).deposit(id, msg.sender, p.amountTokens, IRyzerEscrow.Asset.USDT, p.assetId) {
            emit OrderPlaced(id, msg.sender, p.amountTokens, p.assetId, p.currency, total);
        } catch {
            revert DepositFailed();
        }
    }

    function signDocuments(bytes32 id) external whenNotPaused {
        Order storage o = orders[id];
        if (msg.sender != o.buyer) revert Unauthorized();
        if (o.status != OrderStatus.Pending) revert OrderNotPending();
        if (block.timestamp > o.orderExpiry) revert OrderExpired();

        o.status = OrderStatus.DocumentsSigned;
        emit DocumentsSigned(id);
    }

    function finalizeOrder(bytes32 id) external whenNotPaused {
        Order storage o = orders[id];
        if (msg.sender != o.buyer && !hasRole(ADMIN_ROLE, msg.sender)) revert Unauthorized();
        if (o.status == OrderStatus.Finalized) revert OrderNotFinalized();
        if (block.timestamp > o.orderExpiry) revert OrderExpired();

        o.status = OrderStatus.Finalized;
        o.releaseAfter = uint48(block.timestamp + _RELEASE_TIMELOCK);
        emit OrderFinalized(id);
    }

    function cancelOrder(bytes32 id) external whenNotPaused {
        Order storage o = orders[id];
        if (msg.sender != o.buyer && !hasRole(ADMIN_ROLE, msg.sender)) revert Unauthorized();
        if (o.status == OrderStatus.Finalized) revert OrderNotFinalized();
        if (block.timestamp < o.createdAt + _CANCELLATION_DELAY && !hasRole(ADMIN_ROLE, msg.sender)) revert Delay();

        o.status = OrderStatus.Cancelled;
        IRyzerEscrow(escrow).signRelease(id, o.buyer, o.totalCurrency);
        emit OrderCancelled(id, o.buyer, o.totalCurrency);
    }

    /*────────────────────────────── MULTISIG ─────────────────────────────*/
    function signRelease(bytes32 id) external onlyRole(ADMIN_ROLE) whenNotPaused {
        Order storage o = orders[id];
        if (o.status != OrderStatus.Finalized) revert OrderNotFinalized();
        if (o.released) revert AlreadyReleased();
        if (block.timestamp < o.releaseAfter) revert Timelock();
        if (_releaseSig[id][msg.sender]) revert AlreadySigned();

        _releaseSig[id][msg.sender] = true;
        uint8 sigs = ++_releaseSigCount[id];

        if (sigs >= requiredSigs) {
            address owner = IRyzerRealEstateToken(project).getProjectOwner();
            IRyzerEscrow(escrow).signRelease(id, owner, o.totalCurrency);
            o.released = true;
            emit FundsReleased(id, owner, o.totalCurrency);
        }
    }

    /*────────────────────────────── RESCUE ───────────────────────────────*/
    function resolveStuckOrder(bytes32 id) external onlyRole(ADMIN_ROLE) whenNotPaused {
        Order storage o = orders[id];
        if (o.status != OrderStatus.Pending && o.status != OrderStatus.DocumentsSigned) revert Stuck();
        if (block.timestamp <= o.orderExpiry) revert Stuck();

        o.status = OrderStatus.Cancelled;
        IRyzerEscrow(escrow).signRelease(id, o.buyer, o.totalCurrency);
        emit StuckOrderResolved(id, o.buyer, o.totalCurrency);
    }

    function emergencyWithdraw(Currency c, address to, uint128 amount) external onlyRole(ADMIN_ROLE) nonReentrant {
        if (amount == 0) revert BadAmount();
        CurrencyInfo memory info = currencies[c];
        if (address(info.token) == address(0)) revert CurrencyNotSet();

        info.token.safeTransfer(to, amount);
        emit EmergencyWithdrawal(c, to, amount);
    }

    /*────────────────────────────── PAUSE ────────────────────────────────*/
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /*────────────────────────────── UPGRADES ─────────────────────────────*/
    function _authorizeUpgrade(address impl) internal view override onlyRole(ADMIN_ROLE) {
        if (impl.code.length == 0) revert BadAddress();
    }

    /*────────────────────────────── INTERNAL ─────────────────────────────*/
    function _validatePlaceOrder(PlaceOrderParams calldata p) private view {
        if (p.assetId == 0 || p.currencyPrice == 0) revert BadParameter();
        if (p.projectAddress.code.length == 0) revert BadAddress();
        if (!IRyzerRealEstateToken(p.projectAddress).getIsActive()) revert BadParameter();

        (uint256 min, uint256 max) = IRyzerRealEstateToken(p.projectAddress).getInvestmentLimits();
        if (p.amountTokens < min || p.amountTokens > max || p.amountTokens > _MAX_ORDER) {
            revert BadAmount();
        }
    }

    function _ensureFunds(IERC20 token, address user, uint256 amount) private view {
        if (token.balanceOf(user) < amount) revert InsufficientBalance();
        if (token.allowance(user, address(this)) < amount) revert InsufficientAllowance();
    }

    function _toCurrencyDecimals(uint256 v, uint8 from, uint8 to) private pure returns (uint128) {
        if (from == to) return uint128(v);
        return uint128(from > to ? v / 10 ** (from - to) : v * 10 ** (to - from));
    }

    /*────────────────────────────── VIEW HELPERS ─────────────────────────*/
    function getOrder(bytes32 id) external view returns (Order memory) {
        return orders[id];
    }

    function currencyInfo(Currency c) external view returns (CurrencyInfo memory) {
        return currencies[c];
    }

    function isSupported(Currency c) external view returns (bool) {
        CurrencyInfo memory info = currencies[c];
        return address(info.token) != address(0) && info.active;
    }

    function releaseSigCount(bytes32 id) external view returns (uint8) {
        return _releaseSigCount[id];
    }

    function hasSignedRelease(bytes32 id, address signer) external view returns (bool) {
        return _releaseSig[id][signer];
    }
}
