// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

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
    address public admin = address(0x1);
    address public companyOwner = address(0x2);
    address public investor1 = address(0x3);
    address public investor2 = address(0x4);
    address public feeRecipient = address(0x5);

    // Contract instances
    RyzerCompanyFactory public companyFactory;
    RyzerRegistry public registry;
    RyzerRealEstateTokenFactory public refactory;

    // Token addresses
    ERC20Mock public usdt;
    ERC20Mock public usdc;

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

        // Deploy stablecoins
        usdt = new ERC20Mock();
        usdt.mint(admin, 1000000 * 10 ** 6);
        usdt.mint(investor1, 50000 * 10 ** 6);
        usdt.mint(investor2, 50000 * 10 ** 6);

        usdc = new ERC20Mock();
        usdc.mint(admin, 1000000 * 10 ** 6);

        // Deploy registry
        RyzerRegistry registryImpl = new RyzerRegistry();
        registry = RyzerRegistry(address(new ERC1967Proxy(address(registryImpl), "")));
        registry.initialize();

        // Deploy company factory
        RyzerCompany companyImpl = new RyzerCompany();
        companyFactory = new RyzerCompanyFactory();
        companyFactory.initialize(address(companyImpl));

        // Deploy implementation contracts first
        address tokenImpl = address(new RyzerRealEstateToken());
        address escrowImpl = address(new RyzerEscrow());
        address orderManagerImpl = address(new RyzerOrderManager());
        address daoImpl = address(new RyzerDAO());

        // Deploy real estate factory with all required parameters
        refactory = new RyzerRealEstateTokenFactory();

        // Deploy a mock RyzerX token for testing with 18 decimals
        ERC20Mock ryzerXToken = new ERC20Mock();

        // Set decimals to 18 for RyzerX token before any operations
        vm.store(
            address(ryzerXToken),
            bytes32(uint256(0x7)), // ERC20Storage._DECIMALS_SLOT
            bytes32(uint256(18))
        );

        // Initialize the factory with all required parameters
        refactory.initialize(
            address(usdt), // USDT address
            address(usdc), // USDC address
            address(ryzerXToken), // RyzerX token address (18 decimals)
            tokenImpl, // Project token implementation
            escrowImpl, // Escrow implementation
            orderManagerImpl, // Order manager implementation
            daoImpl // DAO implementation
        );

        // Register company as the company owner
        vm.startPrank(companyOwner);
        companyFactory.deployCompany(RyzerCompany.CompanyType.LLC, keccak256("Test Company"), keccak256("US"));

        // Get company ID
        companyId = registry.companyOf(companyOwner);
        vm.stopPrank();

        vm.stopPrank();
    }

    function testCompleteFlow() public {
        vm.startPrank(admin);

        // 1. Deploy project contracts
        RyzerRealEstateTokenFactory.DeployParams memory params = RyzerRealEstateTokenFactory.DeployParams({
            identityRegistry: address(0), // TODO: Add proper identity registry
            compliance: address(0), // TODO: Add proper compliance
            onchainID: address(0), // TODO: Add proper onchainID
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
            maxInvestment: 1_000_000 * 10 ** 6 // $1M max investment
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

        // Set up order manager
        om.setCurrency(RyzerOrderManager.Currency.USDT, address(usdt), true); // USDT
        om.setCurrency(RyzerOrderManager.Currency.USDC, address(usdc), true); // USDC
        om.setPlatformFee(100); // 1%
        om.setFeeRecipient(feeRecipient);

        // 3. Mint initial tokens to company owner
        project.mint(companyOwner, TOKEN_SUPPLY);

        // 4. Approve tokens for sale
        vm.startPrank(companyOwner);
        project.approve(escrowAddress, TOKEN_SUPPLY);

        // 5. Create an order
        bytes32 orderId = keccak256(abi.encodePacked("test-order-1"));
        uint128 amount = 10 * 10 ** 18; // 10 tokens
        uint128 totalPrice = uint128((amount * TOKEN_PRICE) / 10 ** 18);

        // 6. Investor places an order
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

        // 7. Sign release (simulating admin signatures)
        address[] memory signers = new address[](2);
        signers[0] = admin;
        signers[1] = companyOwner;

        for (uint256 i = 0; i < signers.length; i++) {
            vm.prank(signers[i]);
            escrowContract.signRelease(orderId, investor1, totalPrice);
        }

        // 8. Sign the release (requires multiple admin signatures)
        address[] memory admins = new address[](2);
        admins[0] = admin;
        admins[1] = companyOwner; // Assuming companyOwner is also an admin

        // Each admin signs the release
        for (uint256 i = 0; i < admins.length; i++) {
            vm.prank(admins[i]);
            escrowContract.signRelease(orderId, companyOwner, totalPrice);
        }

        // 9. Transfer tokens to investor
        vm.prank(companyOwner);
        project.transfer(investor1, amount);

        // 10. Distribute dividends
        uint256 dividendAmount = 1000 * 10 ** 6; // $1000 in USDT

        // Company deposits dividends
        vm.prank(companyOwner);
        usdt.transfer(escrowAddress, dividendAmount);

        // Distribute dividends directly to the investor
        vm.prank(companyOwner);
        escrowContract.distributeDividend(investor1, RyzerEscrow.Asset.USDT, uint128(dividendAmount));

        // Verify final balances
        assertEq(usdt.balanceOf(investor1), (50000 * 10 ** 6) - totalPrice + dividendAmount);
        assertEq(project.balanceOf(investor1), amount);
        assertEq(project.balanceOf(companyOwner), TOKEN_SUPPLY - amount);

        vm.stopPrank();
    }
}
