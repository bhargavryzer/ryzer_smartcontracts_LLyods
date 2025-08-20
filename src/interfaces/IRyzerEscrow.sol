// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRyzerRealEstateToken} from "../interfaces/IRyzerRealEstateToken.sol";

/// @title IRyzerEscrow
/// @notice Interface for RyzerEscrow dual-stablecoin escrow & dispute engine
interface IRyzerEscrow {
    /*//////////////////////////////////////////////////////////////
                          ENUMS & STRUCTS
    //////////////////////////////////////////////////////////////*/
    enum Asset {
        USDT,
        USDC
    }

    struct Deposit {
        address buyer;
        uint128 amount;
        Asset token;
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
    function initialize(address _usdt, address _usdc, address _project, address _owner) external;

    /*//////////////////////////////////////////////////////////////
                        ADMIN – CONFIGURATION
    //////////////////////////////////////////////////////////////*/
    function setCoreContracts(address _usdt, address _usdc, address _project) external;
    function setRequiredSignatures(uint8 _sigs) external;

    /*//////////////////////////////////////////////////////////////
                           USER – DEPOSIT
    //////////////////////////////////////////////////////////////*/
    function deposit(bytes32 orderId, address buyer, uint128 amount, Asset token, bytes32 assetId) external;

    /*//////////////////////////////////////////////////////////////
                        SIGNATURE-BASED RELEASE
    //////////////////////////////////////////////////////////////*/
    function signRelease(bytes32 orderId, address to, uint128 amount) external;

    /*//////////////////////////////////////////////////////////////
                         DIVIDEND MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    function depositDividend(Asset token, uint128 amount) external;
    function distributeDividend(address recipient, Asset token, uint128 amount) external;

    /*//////////////////////////////////////////////////////////////
                          DISPUTE LIFECYCLE
    //////////////////////////////////////////////////////////////*/
    function raiseDispute(bytes32 orderId, string calldata reason) external returns (bytes32 disputeId);
    function signDisputeResolution(bytes32 disputeId, address resolvedTo) external;

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY WITHDRAWAL
    //////////////////////////////////////////////////////////////*/
    function emergencyWithdraw(address recipient, Asset token, uint128 amount) external;

    /*//////////////////////////////////////////////////////////////
                         PAUSABILITY
    //////////////////////////////////////////////////////////////*/
    function pause() external;
    function unpause() external;

    /*//////////////////////////////////////////////////////////////
                           VIEW HELPERS
    //////////////////////////////////////////////////////////////*/
    function getDisputeStatus(bytes32 id) external view returns (Dispute memory);
    function dividendPoolBalance(Asset token) external view returns (uint128);

    /*//////////////////////////////////////////////////////////////
                        PUBLIC STORAGE GETTERS
    //////////////////////////////////////////////////////////////*/
    function usdt() external view returns (IERC20);
    function usdc() external view returns (IERC20);
    function project() external view returns (IRyzerRealEstateToken);

    function disputeNonce() external view returns (uint32);
    function requiredSigs() external view returns (uint8);
    function dividendPoolUSDT() external view returns (uint128);
    function dividendPoolUSDC() external view returns (uint128);

    function deposits(bytes32 orderId) external view returns (Deposit memory);
    function disputes(bytes32 disputeId) external view returns (Dispute memory);
    function releaseSigCount(bytes32 orderId) external view returns (uint256);
    function disputeSigCount(bytes32 disputeId) external view returns (uint256);
    function releaseSigned(bytes32 orderId, address signer) external view returns (bool);
    function disputeSigned(bytes32 disputeId, address signer) external view returns (bool);
}
