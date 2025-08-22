// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IRyzerRealEstateToken
/// @notice Interface for RyzerRealEstateToken contract
interface IRyzerRealEstateToken {
    /*────────────────────────────── ENUMS ───────────────────────────────*/
    enum AssetType {
        Commercial,
        Residential,
        Holiday,
        Land
    }

    /*────────────────────────────── STRUCTS ──────────────────────────────*/
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

    /*────────────────────────────── EVENTS ───────────────────────────────*/
    event Initialized(TokenConfig params);
    event ProjectContractsSet(
        address indexed escrow, address indexed orderManager, address indexed dao, uint256 preMintAmount
    );
    event MetadataCIDUpdated(bytes32 oldCID, bytes32 newCID, bool isLegal);
    event ProjectDeactivated(bytes32 reason);

    /*────────────────────────────── ERRORS ───────────────────────────────*/
    error BadAddress();
    error BadParameter();
    error ProjectInactive();
    error DepositFailed();

    /*────────────────────────────── INITIALIZER ──────────────────────────*/
    function initialize(bytes calldata initData) external;

    /*────────────────────────────── ADMIN ────────────────────────────────*/
    function setProjectContracts(address _escrow, address _orderManager, address _dao, uint256 _preMintAmount)
        external;

    function updateMetadataCID(bytes32 newCID, bool isLegal) external;

    function deactivateProject(bytes32 reason) external;

    /*────────────────────────────── PAUSABILITY ──────────────────────────*/
    function pause() external;
    function unpause() external;

    /*────────────────────────────── VIEW HELPERS ─────────────────────────*/
    function getProjectOwner() external view returns (address);

    function tokenPrice() external view returns (uint256);

    function getIsActive() external view returns (bool);

        function transferFrom(address _from, address _to, uint256 _amount) external;

    function getInvestmentLimits() external view returns (uint256 min, uint256 max);

    function getProjectDetails()
        external
        view
        returns (address escrow_, address orderManager_, address dao_, address projectOwner_);
}
