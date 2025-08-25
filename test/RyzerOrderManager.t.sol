// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../src/RyzerOrderManager.sol";
import "../src/interfaces/IRyzerEscrow.sol";
import "../src/interfaces/IRyzerRealEstateToken.sol";
import {RyzerEscrow} from "../src/RyzerEscrow.sol";
import {RyzerRealEstateToken} from "../src/RyzerRealEstateToken.sol";
import {UsdcMock} from "../src/USDCMock.sol";
import {UsdtMock} from "../src/UsdtMock.sol";
import {RyzerToken} from "../src/RyzerToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {RyzerDAO} from "../src/RyzerDAO.sol";
import {IdentityRegistry} from "../src/TREX/registry/implementation/IdentityRegistry.sol";
import {TrustedIssuersRegistry} from "../src/TREX/registry/implementation/TrustedIssuersRegistry.sol";
import {ClaimTopicsRegistry} from "../src/TREX/registry/implementation/ClaimTopicsRegistry.sol";
import {IdentityRegistryStorage} from "../src/TREX/registry/implementation/IdentityRegistryStorage.sol";
import {Identity} from "@onchain-id/solidity/contracts/Identity.sol";

contract RyzerOrderManagerTest is Test {
    RyzerOrderManager public orderManager;
    RyzerOrderManager public implementation;
    RyzerEscrow public escrow;
    RyzerRealEstateToken public project;
    UsdcMock public usdc;
    UsdtMock public usdt;
    RyzerToken public ryzer;
    RyzerDAO public ryzerDAO;
    IdentityRegistry public identityRegistry;
    TrustedIssuersRegistry public trustedIssuersRegistry;
    ClaimTopicsRegistry public claimTopicsRegistry;
    IdentityRegistryStorage public identityRegistryStorage;
    Identity public identity;

    address public owner = makeAddr("owner");
    address public admin = makeAddr("admin");
    address public operator = makeAddr("operator");
    address public buyer = makeAddr("buyer");
    address public projectOwner = makeAddr("projectOwner");
    address public feeRecipient = makeAddr("feeRecipient");
    address public factory = makeAddr("factory");

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    bytes32 public testAssetId = keccak256("TEST_ASSET");

    event OrderPlaced(
        bytes32 indexed id,
        address indexed buyer,
        uint128 tokens,
        bytes32 assetId,
        RyzerOrderManager.Currency currency,
        uint128 total
    );
    event DocumentsSigned(bytes32 indexed id);
    event OrderFinalized(bytes32 indexed id);
    event OrderCancelled(bytes32 indexed id, address indexed buyer, uint128 refund);
    event FundsReleased(bytes32 indexed id, address indexed to, uint128 amount);

    function setUp() public {
        // Deploy mock tokens
        usdt = new UsdtMock();
        usdc = new UsdcMock();
        ryzer = new RyzerToken();
        ryzerDAO = new RyzerDAO();
        identityRegistry = new IdentityRegistry();
        trustedIssuersRegistry = new TrustedIssuersRegistry();
        claimTopicsRegistry = new ClaimTopicsRegistry();
        identityRegistryStorage = new IdentityRegistryStorage();

        vm.startPrank(owner);
        trustedIssuersRegistry.init();
        claimTopicsRegistry.init();
        identityRegistryStorage.init();
        // identityRegistryStorage.addIdentityToStorage(buyer,,1);

        identityRegistry.init(
            address(trustedIssuersRegistry), address(claimTopicsRegistry), address(identityRegistryStorage)
        );
        vm.stopPrank();

        // Deploy escrow first
        escrow = new RyzerEscrow();

        // Deploy implementation and proxy for OrderManager
        implementation = new RyzerOrderManager();

        // Deploy project token
        project = new RyzerRealEstateToken();

        // Initialize escrow
        escrow.initialize(address(usdt), address(usdc), address(project), owner);

        // Initialize OrderManager with proxy
        bytes memory orderManagerInitData =
            abi.encodeCall(RyzerOrderManager.initialize, (address(escrow), address(project), owner));

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), orderManagerInitData);
        orderManager = RyzerOrderManager(address(proxy));

        // Configure project token
        RyzerRealEstateToken.TokenConfig memory config = RyzerRealEstateToken.TokenConfig({
            info: RyzerRealEstateToken.TokenInfo({
                name: "Test Real Estate Token",
                symbol: "TRET",
                decimals: 18,
                maxSupply: 1000000 * 10 ** 18,
                tokenPrice: 100 * 10 ** 6,
                cancelDelay: 7 days,
                assetType: RyzerRealEstateToken.AssetType.Commercial
            }),
            gov: RyzerRealEstateToken.GovernanceConfig({
                identityRegistry: address(identityRegistry),
                compliance: makeAddr("compliance"),
                onchainID: makeAddr("onchainID"),
                projectOwner: projectOwner,
                factory: factory,
                escrow: address(escrow),
                orderManager: address(orderManager),
                dao: address(ryzerDAO),
                companyId: keccak256("testCompany"),
                assetId: testAssetId,
                metadataCID: keccak256("testMetadata"),
                legalMetadataCID: keccak256("testLegalMetadata"),
                dividendPct: 25 // 25%
            }),
            policy: RyzerRealEstateToken.InvestmentPolicy({
                preMintAmount: 1000000 * 10 ** 18, // Pre-mint tokens to escrow
                minInvestment: 100 * 10 ** 18, // Lower minimum to 100 tokens
                maxInvestment: 100000 * 10 ** 18,
                isActive: true
            })
        });

        // Initialize the project token
        bytes memory projectInitData = abi.encode(config);
        vm.prank(factory);
        project.initialize(projectInitData);

        // Set project contracts (this will mint pre-mint amount to escrow)
        vm.prank(projectOwner);
        project.setProjectContracts(address(escrow), address(orderManager), address(ryzerDAO), 0);

        // Setup OrderManager roles and configurations
        vm.startPrank(owner);
        orderManager.grantRole(ADMIN_ROLE, admin);
        orderManager.grantRole(OPERATOR_ROLE, operator);

        // Configure currencies
        orderManager.setCurrency(RyzerOrderManager.Currency.USDT, address(usdt), true);
        orderManager.setCurrency(RyzerOrderManager.Currency.USDC, address(usdc), true);
        orderManager.setCurrency(RyzerOrderManager.Currency.RYZER, address(ryzer), true);

        // Set required signatures for multisig
        orderManager.setRequiredSignatures(1);
        orderManager.setFeeRecipient(feeRecipient);
        vm.stopPrank();

        // Setup escrow admin role for orderManager to handle releases
        vm.prank(owner);
        escrow.grantRole(ADMIN_ROLE, address(orderManager));

        // Setup tokens for buyer
        usdt.mint(buyer, 1000000000000000000000); // 1M USDT
        usdc.mint(buyer, 1000000000000000000000); // 1M USDC
        ryzer.mint(buyer, 1000000e18); // 1M RYZER

        // Approve tokens from buyer
        vm.startPrank(buyer);
        usdt.approve(address(orderManager), type(uint256).max);
        usdc.approve(address(orderManager), type(uint256).max);
        ryzer.approve(address(orderManager), type(uint256).max);
        vm.stopPrank();

        // Grant project owner ADMIN_ROLE in escrow for deposit functionality
        vm.prank(owner);
        escrow.grantRole(ADMIN_ROLE, projectOwner);

        vm.prank(address(orderManager));
        project.approve(address(escrow), type(uint256).max);
    }

    function testPlaceOrderOrderManager() public {
        // Let's first check what tokenPrice returns and adjust accordingly
        uint256 tokenPriceRaw = project.tokenPrice();
        console.log("Token price:", tokenPriceRaw);
        console.log("Buyer USDT balance:", usdt.balanceOf(buyer));

        // Use smaller amounts that work with the actual token price
        uint128 amountTokens = 1000 * 10 ** 18; // 1,000 tokens instead of 10,000
        uint256 currencyPrice = 1 * 10 ** 18; // 1 USDT = 1 USD
        uint128 fees = 50 * 10 ** 6; // 50 USDT additional fees

        RyzerOrderManager.PlaceOrderParams memory params = RyzerOrderManager.PlaceOrderParams({
            projectAddress: address(project),
            escrowAddress: address(escrow),
            assetId: testAssetId,
            amountTokens: amountTokens,
            currencyPrice: currencyPrice,
            fees: fees,
            currency: RyzerOrderManager.Currency.USDT
        });

        // Calculate expected values more carefully
        uint256 tokenPrice = project.tokenPrice();

        // The tokenPrice is in some decimals, need to convert properly
        // amountTokens is in 18 decimals, tokenPrice appears to be in 8 decimals
        // currencyPrice is in 18 decimals
        // Result should be in USDT decimals (6)

        uint256 valueInWei = (amountTokens * tokenPrice) / currencyPrice; // This gives us value in token decimals
        uint256 value = valueInWei / 10 ** 12; // Convert from 18 decimals to 6 decimals for USDT

        uint256 platformFeeBps = 250; // 2.5%
        uint128 platformFee = uint128(value * platformFeeBps / 10000);
        uint128 expectedTotal = uint128(value) + platformFee + fees;

        console.log("Expected value:", value);
        console.log("Expected platform fee:", platformFee);
        console.log("Expected total:", expectedTotal);

        // Ensure buyer has enough balance
        require(usdt.balanceOf(buyer) >= expectedTotal, "Buyer doesn't have enough USDT");

        uint256 buyerBalanceBefore = usdt.balanceOf(buyer);

        vm.startPrank(buyer);
        usdt.approve(address(escrow), type(uint256).max);
        bytes32 orderId = orderManager.placeOrder(params);
        vm.stopPrank();

        // Verify order was created
        RyzerOrderManager.Order memory order = orderManager.getOrder(orderId);
        assertEq(order.buyer, buyer);
        assertEq(order.amountTokens, amountTokens);
        assertEq(order.fees, fees);
        assertEq(order.assetId, testAssetId);
        assertEq(uint256(order.status), uint256(RyzerOrderManager.OrderStatus.Pending));
        assertEq(uint256(order.currency), uint256(RyzerOrderManager.Currency.USDT));
        assertEq(order.projectAddress, address(project));
        assertEq(order.escrowAddress, address(escrow));
        assertEq(order.released, false);

        // Verify tokens were transferred from buyer
        uint256 buyerBalanceAfter = usdt.balanceOf(buyer);
        assertTrue(buyerBalanceBefore > buyerBalanceAfter, "Buyer balance should decrease");
    }

    function testSignDocuments() public {
        // First place an order
        bytes32 orderId = _placeTestOrder();

        vm.expectEmit(true, false, false, false);
        emit DocumentsSigned(orderId);

        vm.prank(buyer);
        orderManager.signDocuments(orderId);

        RyzerOrderManager.Order memory order = orderManager.getOrder(orderId);
        assertEq(uint256(order.status), uint256(RyzerOrderManager.OrderStatus.DocumentsSigned));
    }

    function testFinalizeOrderSuccess() public {
        // Place order and sign documents
        bytes32 orderId = _placeTestOrder();

        vm.prank(buyer);
        orderManager.signDocuments(orderId);

        uint256 buyerTokenBalanceBefore = project.balanceOf(buyer);
        uint256 escrowTokenBalanceBefore = project.balanceOf(address(escrow));

        RyzerOrderManager.Order memory orderBefore = orderManager.getOrder(orderId);

        vm.prank(buyer);
        orderManager.finalizeOrder(orderId);
        console.log("buyerTokenBalanceBefore", buyerTokenBalanceBefore);
        console.log("escrowTokenBalanceBefore", escrowTokenBalanceBefore);

        // Verify order status
        RyzerOrderManager.Order memory order = orderManager.getOrder(orderId);
        assertEq(uint256(order.status), uint256(RyzerOrderManager.OrderStatus.Finalized));

        // Verify tokens were transferred from escrow to buyer
        uint256 buyerTokenBalanceAfter = project.balanceOf(buyer);
        uint256 escrowTokenBalanceAfter = project.balanceOf(address(escrow));

        console.log("buyerTokenBalanceAfter", buyerTokenBalanceAfter);
        console.log("escrowTokenBalanceAfter", escrowTokenBalanceAfter);

        assertEq(buyerTokenBalanceAfter - buyerTokenBalanceBefore, orderBefore.amountTokens);
        assertEq(escrowTokenBalanceBefore - escrowTokenBalanceAfter, orderBefore.amountTokens);
    }

    // Helper function to place a standard test order
    function _placeTestOrder() internal returns (bytes32) {
        uint128 amountTokens = 1000 * 10 ** 18;
        uint256 currencyPrice = 1 * 10 ** 18;
        uint128 fees = 50 * 10 ** 6;

        RyzerOrderManager.PlaceOrderParams memory params = RyzerOrderManager.PlaceOrderParams({
            projectAddress: address(project),
            escrowAddress: address(escrow),
            assetId: testAssetId,
            amountTokens: amountTokens,
            currencyPrice: currencyPrice,
            fees: fees,
            currency: RyzerOrderManager.Currency.USDT
        });

        vm.startPrank(buyer);
        usdt.approve(address(escrow), type(uint256).max);
        bytes32 orderId = orderManager.placeOrder(params);
        vm.stopPrank();

        return orderId;
    }
}
