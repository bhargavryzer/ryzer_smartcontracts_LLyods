// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {UsdcMock} from "../src/USDCMock.sol";
import {UsdtMock} from "../src/UsdtMock.sol";

// Import interfaces
import {IRyzerCompany} from "../src/interfaces/IRyzerCompany.sol";
import {IRyzerRegistry} from "../src/interfaces/IRyzerRegistry.sol";
import {IRyzerOrderManager} from "../src/interfaces/IRyzerOrderManager.sol";
import {IRyzerEscrow} from "../src/interfaces/IRyzerEscrow.sol";
import {IRyzerRealEstateToken} from "../src/interfaces/IRyzerRealEstateToken.sol";

// Import implementations
import {RyzerCompanyFactory} from "../src/RyzerCompanyFactory.sol";
import {RyzerCompany} from "../src/RyzerCompany.sol";
import {RyzerRegistry} from "../src/RyzerRegistry.sol";
import {RyzerRealEstateTokenFactory} from "../src/RyzerRealEstateFactory.sol";
import {RyzerOrderManager} from "../src/RyzerOrderManager.sol";
import {RyzerEscrow} from "../src/RyzerEscrow.sol";
import {RyzerRealEstateToken} from "../src/RyzerRealEstateToken.sol";
import {RyzerDAO} from "../src/RyzerDAO.sol";

//create company -> create project -> place order -> finalize order ->
contract RyzerFlowTest is Test {
    // Test accounts
    address public admin = makeAddr("ADMIN");
    address public companyOwner = makeAddr("Company Owner");
    address public investor1 = makeAddr("INVESTOR 1");
    address public investor2 = makeAddr("INVESTOR 2");
    address public feeRecipient = makeAddr("Fee Recipient");

    // Contract instances
    RyzerCompanyFactory public companyFactory;
    RyzerRegistry public registry;
    RyzerRealEstateTokenFactory public refactory;

    // Mock contracts for testing
    MockIdentityRegistry public identityRegistry;
    MockModularCompliance public compliance;
    MockClaimIssuerRegistry public issuerRegistry;
    MockClaimRegistry public claimRegistry;

    // Token addresses
    UsdtMock public usdt;
    UsdcMock public usdc;

    // Project details
    uint256 public companyId;
    uint256 public projectId;
    address public projectAddress;
    address public escrowAddress;
    address public orderManagerAddress;
    address public daoAddress;

    // Constants
    bytes32 public constant PROJECT_NAME = keccak256("Test Project");
    bytes32 public constant PROJECT_SYMBOL = keccak256("TEST");
    bytes32 public constant METADATA_CID = keccak256("test-metadata");
    bytes32 public constant LEGAL_CID = keccak256("test-legal");
    uint256 public constant TOKEN_PRICE = 100 * 10 ** 6; // $100 per token (6 decimals)
    uint256 public constant TOKEN_SUPPLY = 10000 * 10 ** 18; // 10,000 tokens

    function setUp() public {
        // Set up test accounts
        vm.startPrank(admin);

        // Deploy mock contracts for identity and compliance
        identityRegistry = new MockIdentityRegistry();
        compliance = new MockModularCompliance();
        issuerRegistry = new MockClaimIssuerRegistry();
        claimRegistry = new MockClaimRegistry();

        // Deploy stablecoins with proper decimal handling
        usdt = new UsdtMock();
        usdt.mint(admin, 1000000 * 10 ** 6);
        usdt.mint(investor1, 50000 * 10 ** 6);
        usdt.mint(investor2, 50000 * 10 ** 6);

        usdc = new UsdcMock();
        usdc.mint(admin, 1000000 * 10 ** 6);

        // Deploy registry
        RyzerRegistry registryImpl = new RyzerRegistry();
        registry = RyzerRegistry(address(new ERC1967Proxy(address(registryImpl), "")));
        registry.initialize();

        // Deploy company factory
        RyzerCompany companyImpl = new RyzerCompany();
        companyFactory = new RyzerCompanyFactory();
        companyFactory.initialize(address(companyImpl));
        companyFactory.deployCompany(RyzerCompany.CompanyType.LLC, keccak256("Test Company"), keccak256("US"));

        // Deploy implementation contracts first
        address tokenImpl = address(new RyzerRealEstateToken());
        address escrowImpl = address(new RyzerEscrow());
        address orderManagerImpl = address(new RyzerOrderManager());
        address daoImpl = address(new RyzerDAO());

        // Deploy real estate factory with all required parameters
        refactory = new RyzerRealEstateTokenFactory();

        // Deploy a mock RyzerX token for testing with 18 decimals
        ERC20Mock ryzerXToken = new ERC20Mock();

        // Initialize the factory with all required parameters
        refactory.initialize(
            address(usdc), // USDC address
            address(usdt), // USDT address
            address(ryzerXToken), // RyzerX token address (18 decimals)
            tokenImpl, // Project token implementation
            escrowImpl, // Escrow implementation
            orderManagerImpl, // Order manager implementation
            daoImpl // DAO implementation
        );

        // Grant ADMIN_ROLE to admin for factory operations
        refactory.grantRole(refactory.ADMIN_ROLE(), admin);


        vm.stopPrank();
    }

    function testCompleteFlow() public {
        vm.startPrank(admin);

        // 1. Deploy project contracts
        RyzerRealEstateTokenFactory.DeployParams memory params = RyzerRealEstateTokenFactory.DeployParams({
            identityRegistry: address(identityRegistry), // Use mock identity registry
            compliance: address(compliance), // Use mock compliance
            onchainID: address(0x20), // Placeholder address
            name: "Test Project",
            symbol: "TST",
            decimals: 18,
            maxSupply: 1_000_000 * 10 ** 18, // 1M tokens
            tokenPrice: 1 * 10 ** 6, // $1 per token (6 decimals)
            cancelDelay: 1 days,
            projectOwner: companyOwner,
            assetId: keccak256("test-asset"),
            metadataCID: keccak256("test-metadata"),
            assetType: IRyzerRealEstateToken.AssetType.Residential,
            legalMetadataCID: keccak256("test-legal"),
            dividendPct: 10, // 10%
            preMintAmount: 0,
            minInvestment: 100 * 10 ** 6, // $100 min investment
            maxInvestment: 1_000_000 * 10 ** 18 // $1M max investment (adjusted to 18 decimals for token amount)
        });

        (address token, address escrow, address orderManager, address dao) =
            refactory.deployProject(params, RyzerRealEstateTokenFactory.StableCoin.USDT);

        // Store contract addresses
        projectAddress = token;
        escrowAddress = escrow;
        orderManagerAddress = orderManager;
        daoAddress = dao;

        // 2. Configure project
        RyzerRealEstateToken project = RyzerRealEstateToken(projectAddress);
        RyzerOrderManager om = RyzerOrderManager(orderManagerAddress);
        RyzerEscrow escrowContract = RyzerEscrow(escrowAddress);

        // Set up order manager (switch to company owner who has admin role)
        vm.stopPrank();
        vm.startPrank(companyOwner); // CompanyOwner has the ADMIN_ROLE for OrderManager
        om.setCurrency(RyzerOrderManager.Currency.USDT, address(usdt), true); // USDT
        om.setCurrency(RyzerOrderManager.Currency.USDC, address(usdc), true); // USDC
        om.setPlatformFee(100); // 1%
        om.setFeeRecipient(feeRecipient);
        vm.stopPrank();

        // 3. Mint initial tokens to company owner (the factory has minting role)
        vm.startPrank(address(refactory)); // Factory has MINTER_ROLE
        project.mint(companyOwner, TOKEN_SUPPLY);
        vm.stopPrank();
        vm.startPrank(companyOwner);

        // 4. Approve tokens for sale
        project.approve(escrowAddress, TOKEN_SUPPLY);

        // 5. Create an order
        bytes32 orderId = keccak256(abi.encodePacked("test-order-1"));
        uint128 amount = 10 * 10 ** 18; // 10 tokens
        uint128 totalPrice = uint128((amount * TOKEN_PRICE) / 10 ** 18);

        // 6. Investor places an order
        vm.stopPrank();
        vm.startPrank(investor1);
        usdt.approve(escrowAddress, totalPrice);

        // Place order - use the correct enum type from RyzerEscrow
        escrowContract.deposit(
            orderId,
            investor1,
            totalPrice,
            RyzerEscrow.Asset.USDT, // Using USDT for this test
            keccak256("test-asset")
        );

        // 7. Sign release to project owner (simulating successful order completion)
        vm.stopPrank();
        
        // Grant admin role to admin for escrow operations
        vm.startPrank(companyOwner);
        escrowContract.grantRole(escrowContract.ADMIN_ROLE(), admin);
        vm.stopPrank();
        
        address[] memory signers = new address[](2);
        signers[0] = admin;
        signers[1] = companyOwner;

        // Sign release to project owner (company receives payment for tokens sold)
        for (uint256 i = 0; i < signers.length; i++) {
            vm.prank(signers[i]);
            escrowContract.signRelease(orderId, companyOwner, totalPrice);
        }

        // 8. Transfer tokens to investor (company fulfills the order)
        vm.prank(companyOwner);
        project.transfer(investor1, amount);

        // 9. Distribute dividends
        uint256 dividendAmount = 1000 * 10 ** 6; // $1000 in USDT

        // Company deposits dividends to dividend pool
        vm.prank(companyOwner);
        usdt.approve(escrowAddress, dividendAmount);
        
        vm.prank(companyOwner);
        escrowContract.depositDividend(RyzerEscrow.Asset.USDT, uint128(dividendAmount));

        // Distribute dividends to the investor
        vm.prank(companyOwner);
        escrowContract.distributeDividend(investor1, RyzerEscrow.Asset.USDT, uint128(dividendAmount));

        // Verify final balances
        // Investor should have:
        // - Initial balance: 50000 * 10 ** 6
        // - Minus payment: totalPrice  
        // - Plus dividend: dividendAmount
        assertEq(usdt.balanceOf(investor1), (50000 * 10 ** 6) - totalPrice + dividendAmount);
        assertEq(project.balanceOf(investor1), amount);
        assertEq(project.balanceOf(companyOwner), TOKEN_SUPPLY - amount);
        
        // Company should have received payment but then spent it all on dividends
        // Company received: totalPrice, spent: dividendAmount (same amount)
        assertEq(usdt.balanceOf(companyOwner), 0);

        vm.stopPrank();
    }
}

// Mock contracts for testing
contract MockIdentityRegistry {
    mapping(address => bool) public verified;

    function isVerified(address account) external view returns (bool) {
        return true;
    }

    function setVerified(address account, bool status) external {
        verified[account] = status;
    }
}

contract MockModularCompliance {
    mapping(address => bool) public boundTokens;

    function bindToken(address token) external {
        boundTokens[token] = true;
    }

    function canTransfer(address, address, uint256) external pure returns (bool) {
        return true;
    }

    function transferred(address, address, uint256) external pure {
        // No-op for testing
    }
}

contract MockClaimIssuerRegistry {
    mapping(address => bool) public trustedIssuers;

    function isTrustedIssuer(address issuer) external view returns (bool) {
        return true;
    }

    function setTrustedIssuer(address issuer, bool trusted) external {
        trustedIssuers[issuer] = trusted;
    }
}

contract MockClaimRegistry {
    mapping(address => mapping(uint256 => bool)) public claims;

    function hasClaim(address account, uint256 claimType) external view returns (bool) {
        return true;
    }

    function setClaim(address account, uint256 claimType, bool hasVerifiedClaim) external {
        claims[account][claimType] = hasVerifiedClaim;
    }
}

contract MockValidationLibrary {
    // Static functions for testing - in reality this would be a library
    function validateAddress(address addr, string memory name) external pure {
        require(addr != address(0), string(abi.encodePacked(name, " cannot be zero")));
    }

    function validateBytes32(bytes32 value, string memory name) external pure {
        require(value != bytes32(0), string(abi.encodePacked(name, " cannot be zero")));
    }

    function validateAmount(uint256 amount, string memory name) external pure {
        require(amount > 0, string(abi.encodePacked(name, " must be positive")));
    }
}