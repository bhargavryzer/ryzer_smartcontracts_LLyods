// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {RyzerProjectToken} from "./project/token/RyzerProjectToken.sol";
import {IRyzerEscrow} from "./interfaces/IRyzerEscrow.sol";
import {IRyzerOrderManager} from "./interfaces/IRyzerOrderManager.sol";

contract RyzerRealEstateToken is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    RyzerProjectToken
{
    // /────────────────────────────── CONSTANTS ───────────────────────────/
    uint256 public constant MAX_DIVIDEND_PCT = 50; // 50 %

    // /────────────────────────────── ENUMS ───────────────────────────────/
    enum AssetType {
        Commercial,
        Residential,
        Holiday,
        Land
    }

    // /────────────────────────────── STRUCTS ─────────────────────────────/
    struct TokenInfo {
        string name;
        string symbol;
        uint8 decimals;
        uint256 maxSupply;
        uint256 tokenPrice;
        uint48 cancelDelay;
        AssetType assetType;
    }

    struct GovernanceConfig {
        address identityRegistry;
        address compliance;
        address onchainID;
        address projectOwner;
        address factory;
        address escrow;
        address orderManager;
        address dao;
        bytes32 companyId;
        bytes32 assetId;
        bytes32 metadataCID;
        bytes32 legalMetadataCID;
        uint8 dividendPct; // 0-50
    }

    struct InvestmentPolicy {
        uint256 preMintAmount;
        uint256 minInvestment;
        uint256 maxInvestment;
        bool isActive;
    }

    struct TokenConfig {
        TokenInfo info;
        GovernanceConfig gov;
        InvestmentPolicy policy;
    }

    // /────────────────────────────── STORAGE ─────────────────────────────/
    TokenConfig public config;

    // /────────────────────────────── EVENTS / ERRORS ─────────────────────/
    event Initialized(TokenConfig params);
    event ProjectContractsSet(
        address indexed escrow, address indexed orderManager, address indexed dao, uint256 preMintAmount
    );
    event MetadataCIDUpdated(bytes32 oldCID, bytes32 newCID, bool isLegal);
    event ProjectDeactivated(bytes32 reason);

    error BadAddress();
    error BadParameter();
    error ProjectInactive();
    error DepositFailed();

    // /────────────────────────────── INITIALIZER ─────────────────────────/
    function initialize(bytes calldata initData) external initializer {
        TokenConfig memory params = abi.decode(initData, (TokenConfig));
        _validateConfig(params);

        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();

        super.init(
            params.gov.identityRegistry,
            params.gov.compliance,
            params.info.name,
            params.info.symbol,
            params.info.decimals,
            params.info.maxSupply,
            params.gov.factory,
            params.gov.projectOwner
        );

        config = params;

        _grantRole(PROJECT_ADMIN_ROLE, params.gov.projectOwner);
        _grantRole(DEFAULT_ADMIN_ROLE, params.gov.projectOwner);

        if (params.policy.preMintAmount > 0) {
            super.mint(params.gov.escrow, params.policy.preMintAmount);
        }

        emit Initialized(params);
    }

    // /────────────────────────────── ADMIN ───────────────────────────────/
    function setProjectContracts(address _escrow, address _orderManager, address _dao, uint256 _preMintAmount)
        external
        onlyRole(PROJECT_ADMIN_ROLE)
        whenNotPaused
    {
        if (_escrow == address(0) || _orderManager == address(0) || _dao == address(0)) {
            revert BadAddress();
        }

        config.gov.escrow = _escrow;
        config.gov.orderManager = _orderManager;
        config.gov.dao = _dao;

        if (_preMintAmount > 0) {
            super.mint(_escrow, _preMintAmount);
        }

        emit ProjectContractsSet(_escrow, _orderManager, _dao, _preMintAmount);
    }

    function updateMetadataCID(bytes32 newCID, bool isLegal) external onlyRole(PROJECT_ADMIN_ROLE) whenNotPaused {
        if (newCID == bytes32(0)) revert BadParameter();

        bytes32 oldCID;
        if (isLegal) {
            oldCID = config.gov.legalMetadataCID;
            config.gov.legalMetadataCID = newCID;
        } else {
            oldCID = config.gov.metadataCID;
            config.gov.metadataCID = newCID;
        }
        emit MetadataCIDUpdated(oldCID, newCID, isLegal);
    }

    function deactivateProject(bytes32 reason) external onlyRole(PROJECT_ADMIN_ROLE) {
        config.policy.isActive = false;
        emit ProjectDeactivated(reason);
    }

    // /────────────────────────────── PAUSABILITY ─────────────────────────/
    function pause() public override onlyRole(PROJECT_ADMIN_ROLE) {
        if (config.gov.escrow != address(0)) {
            IRyzerEscrow(config.gov.escrow).pause();
        }
    }

    function unpause() public override onlyRole(PROJECT_ADMIN_ROLE) {
        if (config.gov.escrow != address(0)) {
            IRyzerEscrow(config.gov.escrow).unpause();
        }
    }

    // /────────────────────────────── INTERNAL ────────────────────────────/
    function _validateConfig(TokenConfig memory c) private pure {
        // TokenInfo
        if (c.info.maxSupply == 0 || c.info.tokenPrice == 0 || c.info.cancelDelay == 0) {
            revert BadParameter();
        }
        // GovernanceConfig
        if (c.gov.identityRegistry == address(0) || c.gov.compliance == address(0) || c.gov.factory == address(0)) {
            revert BadAddress();
        }
        if (c.gov.dividendPct > MAX_DIVIDEND_PCT) revert BadParameter();
        if (c.gov.metadataCID == bytes32(0) || c.gov.legalMetadataCID == bytes32(0)) {
            revert BadParameter();
        }
        // InvestmentPolicy
        if (c.policy.minInvestment == 0 || c.policy.maxInvestment < c.policy.minInvestment) revert BadParameter();
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal view override whenNotPaused {
        if (!config.policy.isActive) revert ProjectInactive();

        if (to != address(0) && to != config.gov.escrow) {
            uint256 newBal = balanceOf(to) + amount;
            if (amount < config.policy.minInvestment && newBal != 0) revert BadParameter();
            if (newBal > config.policy.maxInvestment) revert BadParameter();
        }
    }

    function _authorizeUpgrade(address impl) internal view override onlyRole(PROJECT_ADMIN_ROLE) {
        if (impl.code.length == 0) revert BadAddress();
    }

    // /────────────────────────────── VIEW HELPERS ────────────────────────/
    function getProjectOwner() external view returns (address) {
        return config.gov.projectOwner;
    }

    function tokenPrice() external view returns (uint256) {
        return config.info.tokenPrice;
    }

    function getIsActive() external view returns (bool) {
        return config.policy.isActive;
    }

    function getInvestmentLimits() external view returns (uint256 min, uint256 max) {
        return (config.policy.minInvestment, config.policy.maxInvestment);
    }

    function getProjectDetails()
        external
        view
        returns (address escrow_, address orderManager_, address dao_, address projectOwner_)
    {
        escrow_ = config.gov.escrow;
        orderManager_ = config.gov.orderManager;
        dao_ = config.gov.dao;
        projectOwner_ = config.gov.projectOwner;
    }
}
