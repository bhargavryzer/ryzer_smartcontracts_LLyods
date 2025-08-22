// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/* ──────────────── OpenZeppelin Upgradeable ───────────────── */
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/* ───────────────────── Interfaces ────────────────────────── */
import "./interfaces/IRyzerEscrow.sol";
import "./interfaces/IRyzerOrderManager.sol";
import "./interfaces/IRyzerDAO.sol";
import "./interfaces/IRyzerRealEstateToken.sol";

/* ──────────────────── Factory Contract ───────────────────── */
/// @title RyzerRealEstateTokenFactory
/// @notice Deploys real-estate token projects with Escrow, OrderManager & DAO.
///         Supports both USDC and USDT as underlying stable-coins.
contract RyzerRealEstateTokenFactory is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    /* --------------------------------------------------------- */
    /*                        ROLES & CONST                      */
    /* --------------------------------------------------------- */
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint8 private constant EXPECTED_DECIMALS = 6; // USDC & USDT

    /* --------------------------------------------------------- */
    /*                         STORAGE                           */
    /* --------------------------------------------------------- */
    IERC20 public usdc;
    IERC20 public usdt;
    IERC20 public ryzerXToken;

    address public projectTemplate;
    address public escrowTemplate;
    address public orderManagerTemplate;
    address public daoTemplate;

    /* --------------------------------------------------------- */
    /*                           EVENTS                          */
    /* --------------------------------------------------------- */
    event FactoryInitialized(address indexed usdc, address indexed usdt, address indexed ryzerX);
    event ProjectDeployed(
        address indexed project,
        address indexed escrow,
        address indexed orderManager,
        address dao,
        bytes32 assetId,
        string name,
        address stableCoin
    );

    /* --------------------------------------------------------- */
    /*                       CUSTOM ERRORS                       */
    /* --------------------------------------------------------- */
    error ZeroAddress();
    error BadDecimals(string token, uint8 actual);
    error InvalidParameter(string field);

    /* --------------------------------------------------------- */
    /*                      INITIALISER                          */
    /* --------------------------------------------------------- */
    function initialize(
        address _usdc,
        address _usdt,
        address _ryzerXToken,
        address _projectTemplate,
        address _escrowTemplate,
        address _orderManagerTemplate,
        address _daoTemplate
    ) external initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        if (
            _usdc == address(0) || _usdt == address(0) || _ryzerXToken == address(0) || _projectTemplate == address(0)
                || _escrowTemplate == address(0) || _orderManagerTemplate == address(0) || _daoTemplate == address(0)
        ) revert ZeroAddress();

        _validateDecimals(_usdc);
        _validateDecimals(_usdt);
        if (IERC20Metadata(_ryzerXToken).decimals() != 18) {
            revert BadDecimals("RyzerX", IERC20Metadata(_ryzerXToken).decimals());
        }

        usdc = IERC20(_usdc);
        usdt = IERC20(_usdt);
        ryzerXToken = IERC20(_ryzerXToken);

        projectTemplate = _projectTemplate;
        escrowTemplate = _escrowTemplate;
        orderManagerTemplate = _orderManagerTemplate;
        daoTemplate = _daoTemplate;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        emit FactoryInitialized(_usdc, _usdt, _ryzerXToken);
    }

    /* --------------------------------------------------------- */
    /*                  PROJECT DEPLOYMENT                       */
    /* --------------------------------------------------------- */
    enum StableCoin {
        USDC,
        USDT
    }

    struct DeployParams {
        address identityRegistry;
        address compliance;
        address onchainID;
        string name;
        string symbol;
        uint8 decimals;
        uint256 maxSupply;
        uint256 tokenPrice;
        uint48 cancelDelay;
        address projectOwner;
        bytes32 assetId;
        bytes32 metadataCID;
        IRyzerRealEstateToken.AssetType assetType;
        bytes32 legalMetadataCID;
        uint8 dividendPct;
        uint256 preMintAmount;
        uint256 minInvestment;
        uint256 maxInvestment;
    }

    /// @notice Deploy a new real-estate project.
    /// @param p    All project parameters (unchanged).
    /// @param coin Which stable-coin to wire into Escrow / OM.
    function deployProject(DeployParams calldata p, StableCoin coin)
        external
        onlyRole(ADMIN_ROLE)
        whenNotPaused
        returns (address project, address escrow, address orderManager, address dao)
    {
        if (p.projectOwner == address(0)) revert ZeroAddress();
        _validateProjectParams(p);

        IERC20 stableCoin = coin == StableCoin.USDC ? usdc : usdt;

        // clone satellites
        project = Clones.clone(projectTemplate);
        escrow = Clones.clone(escrowTemplate);
        orderManager = Clones.clone(orderManagerTemplate);
        dao = Clones.clone(daoTemplate);

        IRyzerRealEstateToken.TokenConfig memory cfg = IRyzerRealEstateToken.TokenConfig({
            info: IRyzerRealEstateToken.TokenInfo({
                name: p.name,
                symbol: p.symbol,
                decimals: p.decimals,
                maxSupply: p.maxSupply,
                tokenPrice: p.tokenPrice,
                cancelDelay: p.cancelDelay,
                assetType: p.assetType
            }),
            gov: IRyzerRealEstateToken.GovernanceConfig({
                identityRegistry: p.identityRegistry,
                compliance: p.compliance,
                onchainID: p.onchainID,
                projectOwner: p.projectOwner,
                factory: address(this),
                escrow: escrow,
                orderManager: orderManager,
                dao: dao,
                companyId: bytes32(0),
                assetId: p.assetId,
                metadataCID: p.metadataCID,
                legalMetadataCID: p.legalMetadataCID,
                dividendPct: p.dividendPct
            }),
            policy: IRyzerRealEstateToken.InvestmentPolicy({
                preMintAmount: p.preMintAmount,
                minInvestment: p.minInvestment,
                maxInvestment: p.maxInvestment,
                isActive: true
            })
        });

        IRyzerRealEstateToken(project).initialize(abi.encode(cfg));

        IRyzerEscrow(escrow).initialize(address(usdt), address(usdc), project, p.projectOwner);
        IRyzerOrderManager(orderManager).initialize(escrow, project, p.projectOwner);
        IRyzerDAO(dao).initialize(project, address(ryzerXToken), 60 /* quorum placeholder */ );

        emit ProjectDeployed(project, escrow, orderManager, dao, p.assetId, p.name, address(stableCoin));
    }

    /* --------------------------------------------------------- */
    /*                    ADMIN / UPGRADE                        */
    /* --------------------------------------------------------- */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address newImpl) internal view override onlyRole(ADMIN_ROLE) {}

    /* --------------------------------------------------------- */
    /*                      PRIVATE HELPERS                      */
    /* --------------------------------------------------------- */
    function _validateDecimals(address token) private view {
        uint8 d = IERC20Metadata(token).decimals();
        if (d != EXPECTED_DECIMALS) revert BadDecimals(IERC20Metadata(token).symbol(), d);
    }

    function _validateProjectParams(DeployParams calldata p) private pure {
        if (bytes(p.name).length == 0) revert InvalidParameter("name");
        if (bytes(p.symbol).length == 0) revert InvalidParameter("symbol");
        if (p.maxSupply == 0) revert InvalidParameter("maxSupply");
        if (p.tokenPrice == 0) revert InvalidParameter("tokenPrice");
        if (p.cancelDelay == 0) revert InvalidParameter("cancelDelay");
        if (p.minInvestment == 0) revert InvalidParameter("minInvestment");
        if (p.maxInvestment < p.minInvestment) revert InvalidParameter("maxInvestment");
        if (p.dividendPct > 50) revert InvalidParameter("dividendPct");
    }
}
