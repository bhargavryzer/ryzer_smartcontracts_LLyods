// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IRyzerRegistry {
    /*────────────────────────────── ENUMS ───────────────────────────────*/
    enum CompanyType {
        LLC,
        PRIVATELIMITED,
        DAOLLC,
        CORPORATION,
        PUBLICENTITY,
        PARTNERSHIP
    }
    enum AssetType {
        Commercial,
        Residential,
        Holiday,
        Land
    }

    /*────────────────────────────── STRUCTS ─────────────────────────────*/
    struct Company {
        address owner;
        CompanyType companyType;
        bool isActive;
        bytes24 __gap;
        bytes32 name;
        bytes32 jurisdiction;
    }

    struct Project {
        address projectAddress;
        address escrow;
        address orderManager;
        address dao;
        AssetType assetType;
        bool isActive;
        bytes10 __gap;
        bytes32 name;
        bytes32 symbol;
        bytes32 metadataCID;
        bytes32 legalCID;
    }

    /*────────────────────────────── EVENTS ──────────────────────────────*/
    event CompanyRegistered(uint256 indexed id, address indexed owner, bytes32 name);
    event ProjectRegistered(uint256 indexed companyId, uint256 indexed projectId, address indexed addr);
    event ProjectDeactivated(uint256 indexed companyId, uint256 indexed projectId);
    event MetadataUpdated(uint256 indexed projectId, bool isLegal, bytes32 newCID);

    /*────────────────────────────── ERRORS ──────────────────────────────*/
    error BadAddress();
    error BadParameter();
    error BadLength();
    error NotFound();
    error Exists();

    /*────────────────────────────── CORE FUNCTIONS ──────────────────────*/
    function registerCompany(address owner, bytes32 name, bytes32 jurisdiction, CompanyType companyType)
        external
        returns (uint256 id);

    function registerProject(
        uint256 companyId,
        bytes32 name,
        bytes32 symbol,
        bytes32 metadataCID,
        bytes32 legalCID,
        AssetType assetType,
        address projectAddress,
        address escrow,
        address orderManager,
        address dao
    ) external returns (uint256 id);

    function deactivateProject(uint256 projectId) external;

    function updateMetadata(uint256 projectId, bool isLegal, bytes32 newCID) external;

    /*────────────────────────────── VIEW HELPERS ────────────────────────*/
    function companyCount() external view returns (uint256);
    function projectCount() external view returns (uint256);
    function companies(uint256 id)
        external
        view
        returns (
            address owner,
            CompanyType companyType,
            bool isActive,
            bytes24 __gap,
            bytes32 name,
            bytes32 jurisdiction
        );
    function projects(uint256 id)
        external
        view
        returns (
            address projectAddress,
            address escrow,
            address orderManager,
            address dao,
            AssetType assetType,
            bool isActive,
            bytes10 __gap,
            bytes32 name,
            bytes32 symbol,
            bytes32 metadataCID,
            bytes32 legalCID
        );
    function companyOf(address owner) external view returns (uint256);
    function projectIdsOf(uint256 companyId) external view returns (uint256[] memory);

    function getCompany(uint256 id) external view returns (Company memory);
    function getProject(uint256 id) external view returns (Project memory);
    function projectIdsByCompany(uint256 companyId) external view returns (uint256[] memory);
}
