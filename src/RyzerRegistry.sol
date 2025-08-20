// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract RyzerRegistry is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    /*────────────────────────────── ROLES ───────────────────────────────*/
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /*────────────────────────────── CONSTANTS ───────────────────────────*/
    uint256 private constant _MAX_NAME = 64;
    uint256 private constant _MAX_SYM = 16;
    string public constant VERSION = "2.0.0";

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

    /*────────────────────────────── STRUCTS (TIGHT) ─────────────────────*/
    struct Company {
        address owner; // 20
        CompanyType companyType; // 1
        bool isActive; // 1
        bytes24 __gap; // 24 (padding)
        bytes32 name; // 32
        bytes32 jurisdiction; // 32
    }

    struct Project {
        address projectAddress; // 20
        address escrow; // 20
        address orderManager; // 20
        address dao; // 20
        AssetType assetType; // 1
        bool isActive; // 1
        bytes10 __gap; // 10
        bytes32 name; // 32
        bytes32 symbol; // 32
        bytes32 metadataCID; // 32
        bytes32 legalCID; // 32
    }

    /*────────────────────────────── STORAGE ──────────────────────────────*/
    uint256 public companyCount;
    uint256 public projectCount;
    mapping(uint256 => Company) public companies; // companyId => Company
    mapping(uint256 => Project) public projects; // projectId => Project
    mapping(address => uint256) public companyOf; // owner => companyId
    mapping(uint256 => uint256[]) public projectIdsOf; // companyId => projectId[]

    /*────────────────────────────── EVENTS ───────────────────────────────*/
    event Initialized(address indexed admin);
    event CompanyRegistered(uint256 indexed id, address indexed owner, bytes32 name);
    event ProjectRegistered(uint256 indexed companyId, uint256 indexed projectId, address indexed addr);
    event ProjectDeactivated(uint256 indexed companyId, uint256 indexed projectId);
    event MetadataUpdated(uint256 indexed projectId, bool isLegal, bytes32 newCID);

    /*────────────────────────────── ERRORS ───────────────────────────────*/
    error BadAddress();
    error BadParameter();
    error BadLength();
    error NotFound();
    error Exists();

    /*────────────────────────────── INITIALIZER ──────────────────────────*/
    function initialize() external initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        emit Initialized(msg.sender);
    }

    /*────────────────────────────── ADMIN ────────────────────────────────*/
    function registerCompany(address owner, bytes32 name, bytes32 jurisdiction, CompanyType companyType)
        external
        onlyRole(ADMIN_ROLE)
        whenNotPaused
        returns (uint256 id)
    {
        if (owner == address(0)) revert BadAddress();
        if (name == 0 || jurisdiction == 0) revert BadParameter();
        if (companyOf[owner] != 0) revert Exists();

        id = ++companyCount;
        companies[id] = Company({
            owner: owner,
            companyType: companyType,
            isActive: true,
            __gap: 0,
            name: name,
            jurisdiction: jurisdiction
        });
        companyOf[owner] = id;

        emit CompanyRegistered(id, owner, name);
    }

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
    ) external onlyRole(ADMIN_ROLE) whenNotPaused returns (uint256 id) {
        if (companyId == 0 || companyId > companyCount) revert NotFound();
        if (projectAddress == address(0) || escrow == address(0) || orderManager == address(0) || dao == address(0)) {
            revert BadAddress();
        }
        if (name == 0 || symbol == 0 || metadataCID == 0 || legalCID == 0) revert BadParameter();

        id = ++projectCount;
        projects[id] = Project({
            projectAddress: projectAddress,
            escrow: escrow,
            orderManager: orderManager,
            dao: dao,
            assetType: assetType,
            isActive: true,
            __gap: 0,
            name: name,
            symbol: symbol,
            metadataCID: metadataCID,
            legalCID: legalCID
        });
        projectIdsOf[companyId].push(id);

        emit ProjectRegistered(companyId, id, projectAddress);
    }

    function deactivateProject(uint256 projectId) external onlyRole(ADMIN_ROLE) whenNotPaused {
        if (projectId == 0 || projectId > projectCount) revert NotFound();
        Project storage p = projects[projectId];
        if (!p.isActive) revert NotFound();
        p.isActive = false;

        emit ProjectDeactivated(0, projectId); // companyId omitted for gas
    }

    function updateMetadata(uint256 projectId, bool isLegal, bytes32 newCID)
        external
        onlyRole(ADMIN_ROLE)
        whenNotPaused
    {
        if (projectId == 0 || projectId > projectCount) revert NotFound();
        if (newCID == 0) revert BadParameter();

        Project storage p = projects[projectId];
        if (isLegal) p.legalCID = newCID;
        else p.metadataCID = newCID;

        emit MetadataUpdated(projectId, isLegal, newCID);
    }

    /*────────────────────────────── PAUSE / UPGRADE ─────────────────────*/
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address impl) internal view override onlyRole(ADMIN_ROLE) {
        if (impl.code.length == 0) revert BadAddress();
    }

    /*────────────────────────────── VIEW HELPERS ─────────────────────────*/
    function getCompany(uint256 id) external view returns (Company memory) {
        if (id == 0 || id > companyCount) revert NotFound();
        return companies[id];
    }

    function getProject(uint256 id) external view returns (Project memory) {
        if (id == 0 || id > projectCount) revert NotFound();
        return projects[id];
    }

    function projectIdsByCompany(uint256 companyId) external view returns (uint256[] memory) {
        if (companyId == 0 || companyId > companyCount) revert NotFound();
        return projectIdsOf[companyId];
    }
}
