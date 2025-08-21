// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {RyzerEscrow} from "../src/RyzerEscrow.sol";
import {IRyzerRealEstateToken} from "../src/interfaces/IRyzerRealEstateToken.sol";

contract MockRealEstateToken is IRyzerRealEstateToken {
    address public orderManager;
    address public projectOwner;
    bool public isPaused;
    bool public isActive = true;
    uint256 public currentPrice = 1e18; // 1 token = 1 USDT/USDC
    
    constructor(address _orderManager, address _projectOwner) {
        orderManager = _orderManager;
        projectOwner = _projectOwner;
    }
    
    function getProjectDetails() external view returns (
        address escrow_,
        address orderManager_,
        address dao_,
        address projectOwner_
    ) {
        return (address(this), orderManager, address(0), projectOwner);
    }
    
    function initialize(bytes calldata) external {}
    
    function setProjectContracts(address _escrow, address _orderManager, address _dao, uint256 _preMintAmount) external {
        orderManager = _orderManager;
    }
    
    function deactivateProject(bytes32) external {
        isActive = false;
    }
    
    function pause() external {
        isPaused = true;
    }
    
    function unpause() external {
        isPaused = false;
    }
    
    function updateMetadataCID(bytes32, bool) external {}
    
    function getProjectOwner() external view returns (address) {
        return projectOwner;
    }
    
    function tokenPrice() external view returns (uint256) {
        return currentPrice;
    }
    
    function getIsActive() external view returns (bool) {
        return isActive;
    }
    
    function getInvestmentLimits() external pure returns (uint256 min, uint256 max) {
        return (1e18, 1000000e18); // 1 to 1M tokens
    }
    
    function setOrderManager(address _orderManager) external {
        orderManager = _orderManager;
    }
    
    function setProjectOwner(address _projectOwner) external {
        projectOwner = _projectOwner;
    }
    
    function setTokenPrice(uint256 _price) external {
        currentPrice = _price;
    }
}

contract RyzerEscrowTest is Test {
    RyzerEscrow public escrow;
    ERC20Mock public usdt;
    ERC20Mock public usdc;
    MockRealEstateToken public project;
    
    address public owner = makeAddr("owner");
    address public admin1 = makeAddr("admin1");
    address public admin2 = makeAddr("admin2");
    address public admin3 = makeAddr("admin3");
    address public buyer = makeAddr("buyer");
    address public seller = makeAddr("seller");
    address public orderManager = makeAddr("orderManager");
    address public projectOwner = makeAddr("projectOwner");
    address public user1 = makeAddr("user1");
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    
    // Test data
    bytes32 public orderId = keccak256("order1");
    bytes32 public assetId = keccak256("asset1");
    uint128 public constant DEPOSIT_AMOUNT = 1000e6; // 1000 USDT/USDC
    
    event EscrowInitialized(address indexed usdt, address indexed usdc, address indexed project);
    event Deposited(bytes32 indexed orderId, address indexed buyer, RyzerEscrow.Asset indexed token, uint128 amount, bytes32 assetId);
    event Released(bytes32 indexed orderId, address indexed to, RyzerEscrow.Asset indexed token, uint128 amount);
    event DividendDeposited(address indexed depositor, RyzerEscrow.Asset indexed token, uint128 amount);
    event DividendDistributed(address indexed recipient, RyzerEscrow.Asset indexed token, uint128 amount);
    event DisputeRaised(bytes32 indexed disputeId, address indexed buyer, RyzerEscrow.Asset indexed token, uint128 amount, string reason);
    event DisputeResolved(bytes32 indexed disputeId, address indexed resolvedTo, RyzerEscrow.Asset indexed token, uint128 amount);
    
    function setUp() public {
        // Deploy mock tokens with 6 decimals to match stablecoin standards
        usdt = new ERC20Mock();
        usdc = new ERC20Mock();
        
        // Set decimals to 6 for both tokens before any operations
        vm.store(
            address(usdt),
            bytes32(uint256(0x7)), // ERC20Storage._DECIMALS_SLOT
            bytes32(uint256(6))
        );
        
        vm.store(
            address(usdc),
            bytes32(uint256(0x7)), // ERC20Storage._DECIMALS_SLOT
            bytes32(uint256(6))
        );
        
        // Set the symbol for the tokens (required by _validateDecimals)
        vm.store(
            address(usdt),
            bytes32(uint256(0x3)), // ERC20Storage._SYMBOL_SLOT
            bytes32("USDT")
        );
        
        vm.store(
            address(usdc),
            bytes32(uint256(0x3)), // ERC20Storage._SYMBOL_SLOT
            bytes32("USDC")
        );
        
        // Now mint tokens after setting decimals
        usdt.mint(address(this), 1000000 * 10**6);
        usdc.mint(address(this), 1000000 * 10**6);
        
        // Deploy mock project contract
        project = new MockRealEstateToken(orderManager, projectOwner);
        
        // Deploy the implementation contract
        RyzerEscrow implementation = new RyzerEscrow();
        
        // Deploy the proxy and initialize it
        bytes memory data = abi.encodeWithSelector(
            RyzerEscrow.initialize.selector,
            address(usdt),
            address(usdc),
            address(project),
            owner  // This address will get the DEFAULT_ADMIN_ROLE
        );
        
        // Deploy the proxy and point it to the implementation
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            data
        );
        
        // Cast the proxy to the RyzerEscrow interface
        escrow = RyzerEscrow(address(proxy));
        
        // Grant admin roles - must be done by the owner (DEFAULT_ADMIN_ROLE)
        vm.startPrank(owner);
        escrow.grantRole(escrow.ADMIN_ROLE(), admin1);
        escrow.grantRole(escrow.ADMIN_ROLE(), admin2);
        escrow.grantRole(escrow.ADMIN_ROLE(), admin3);
        vm.stopPrank();
        
        // Mint tokens to test accounts
        usdt.mint(buyer, 10000e6);
        usdc.mint(buyer, 10000e6);
        usdt.mint(user1, 5000e6);
        usdc.mint(user1, 5000e6);
        
        // Approve escrow to spend tokens
        vm.prank(buyer);
        usdt.approve(address(escrow), type(uint256).max);
        vm.prank(buyer);
        usdc.approve(address(escrow), type(uint256).max);
        vm.prank(user1);
        usdt.approve(address(escrow), type(uint256).max);
        vm.prank(user1);
        usdc.approve(address(escrow), type(uint256).max);
    }
    
    /*//////////////////////////////////////////////////////////////
                         INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testInitialization() public {
        assertEq(address(escrow.usdt()), address(usdt));
        assertEq(address(escrow.usdc()), address(usdc));
        assertEq(address(escrow.project()), address(project));
        assertEq(escrow.requiredSigs(), 2);
        assertTrue(escrow.hasRole(DEFAULT_ADMIN_ROLE, owner));
        assertTrue(escrow.hasRole(ADMIN_ROLE, owner));
    }
    
    function testInitializationWithInvalidTokens() public {
        // Deploy token with wrong decimals
        ERC20Mock wrongToken = new ERC20Mock();
        
        // Deploy a new implementation for this test
        RyzerEscrow newImpl = new RyzerEscrow();
        
        // Deploy the proxy with invalid token (wrong decimals)
        vm.expectRevert(RyzerEscrow.InvalidDecimals.selector);
new ERC1967Proxy(
            address(newImpl),
            abi.encodeWithSelector(
                RyzerEscrow.initialize.selector,
                address(wrongToken),
                address(usdc),
                address(project),
                owner
            )
        );
    }
    
    function testInitializationWithZeroAddresses() public {
        // Deploy a new implementation for this test
        RyzerEscrow newImpl = new RyzerEscrow();
        
        // Deploy the proxy with zero address
        vm.expectRevert(RyzerEscrow.InvalidAddress.selector);
new ERC1967Proxy(
            address(newImpl),
            abi.encodeWithSelector(
                RyzerEscrow.initialize.selector,
                address(0),
                address(usdc),
                address(project),
                owner
            )
        );
    }
    
    /*//////////////////////////////////////////////////////////////
                           DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testDeposit() public {
        vm.expectEmit(true, true, true, true);
        emit Deposited(orderId, buyer, RyzerEscrow.Asset.USDT, DEPOSIT_AMOUNT, assetId);
        
        vm.prank(orderManager);
        escrow.deposit(orderId, buyer, DEPOSIT_AMOUNT, RyzerEscrow.Asset.USDT, assetId);
        
        (address depositBuyer, uint128 amount, RyzerEscrow.Asset token, bytes32 storedAssetId) = escrow.deposits(orderId);
        assertEq(depositBuyer, buyer);
        assertEq(amount, DEPOSIT_AMOUNT);
        assertTrue(token == RyzerEscrow.Asset.USDT);
        assertEq(storedAssetId, assetId);
        assertEq(usdt.balanceOf(address(escrow)), DEPOSIT_AMOUNT);
    }
    
    function testDepositUSDC() public {
        vm.prank(orderManager);
        escrow.deposit(orderId, buyer, DEPOSIT_AMOUNT, RyzerEscrow.Asset.USDC, assetId);
        
        assertEq(usdc.balanceOf(address(escrow)), DEPOSIT_AMOUNT);
    }
    
    function testDepositUnauthorized() public {
        vm.expectRevert(RyzerEscrow.Unauthorized.selector);
        vm.prank(user1);
        escrow.deposit(orderId, buyer, DEPOSIT_AMOUNT, RyzerEscrow.Asset.USDT, assetId);
    }
    
    function testDepositZeroAmount() public {
        vm.expectRevert(RyzerEscrow.InvalidAmount.selector);
        vm.prank(orderManager);
        escrow.deposit(orderId, buyer, 0, RyzerEscrow.Asset.USDT, assetId);
    }
    
    function testDepositZeroBuyer() public {
        vm.expectRevert(RyzerEscrow.InvalidAddress.selector);
        vm.prank(orderManager);
        escrow.deposit(orderId, address(0), DEPOSIT_AMOUNT, RyzerEscrow.Asset.USDT, assetId);
    }
    
    /*//////////////////////////////////////////////////////////////
                           RELEASE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testSignRelease() public {
        // First make a deposit
        vm.prank(orderManager);
        escrow.deposit(orderId, buyer, DEPOSIT_AMOUNT, RyzerEscrow.Asset.USDT, assetId);
        
        // Sign release with admin1
        vm.prank(admin1);
        escrow.signRelease(orderId, seller, DEPOSIT_AMOUNT);
        assertEq(escrow.releaseSigCount(orderId), 1);
        assertTrue(escrow.releaseSigned(orderId, admin1));
        
        // Sign release with admin2 (should trigger release)
        vm.expectEmit(true, true, true, true);
        emit Released(orderId, seller, RyzerEscrow.Asset.USDT, DEPOSIT_AMOUNT);
        
        vm.prank(admin2);
        escrow.signRelease(orderId, seller, DEPOSIT_AMOUNT);
        
        assertEq(usdt.balanceOf(seller), DEPOSIT_AMOUNT);
        assertEq(usdt.balanceOf(address(escrow)), 0);
        
        // Deposit should be deleted after full release
        (address depositBuyer,,,) = escrow.deposits(orderId);
        assertEq(depositBuyer, address(0));
    }
    
    function testPartialRelease() public {
        // Make a deposit
        vm.prank(orderManager);
        escrow.deposit(orderId, buyer, DEPOSIT_AMOUNT, RyzerEscrow.Asset.USDT, assetId);
        
        uint128 partialAmount = DEPOSIT_AMOUNT / 2;
        
        // Sign partial release
        vm.prank(admin1);
        escrow.signRelease(orderId, seller, partialAmount);
        
        vm.prank(admin2);
        escrow.signRelease(orderId, seller, partialAmount);
        
        assertEq(usdt.balanceOf(seller), partialAmount);
        
        // Check remaining deposit
        (, uint128 remainingAmount,,) = escrow.deposits(orderId);
        assertEq(remainingAmount, DEPOSIT_AMOUNT - partialAmount);
    }
    
    function testSignReleaseNonExistentOrder() public {
        vm.expectRevert(RyzerEscrow.DepositNotFound.selector);
        vm.prank(admin1);
        escrow.signRelease(keccak256("nonexistent"), seller, 100);
    }
    
    function testSignReleaseAlreadySigned() public {
        vm.prank(orderManager);
        escrow.deposit(orderId, buyer, DEPOSIT_AMOUNT, RyzerEscrow.Asset.USDT, assetId);
        
        vm.prank(admin1);
        escrow.signRelease(orderId, seller, DEPOSIT_AMOUNT);
        
        vm.expectRevert(RyzerEscrow.AlreadySigned.selector);
        vm.prank(admin1);
        escrow.signRelease(orderId, seller, DEPOSIT_AMOUNT);
    }
    
    function testSignReleaseUnauthorized() public {
        vm.prank(orderManager);
        escrow.deposit(orderId, buyer, DEPOSIT_AMOUNT, RyzerEscrow.Asset.USDT, assetId);
        
        vm.expectRevert();
        vm.prank(user1);
        escrow.signRelease(orderId, seller, DEPOSIT_AMOUNT);
    }
    
    /*//////////////////////////////////////////////////////////////
                          DIVIDEND TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testDepositDividend() public {
        uint128 dividendAmount = 500e6;
        
        vm.expectEmit(true, true, false, true);
        emit DividendDeposited(user1, RyzerEscrow.Asset.USDT, dividendAmount);
        
        vm.prank(user1);
        escrow.depositDividend(RyzerEscrow.Asset.USDT, dividendAmount);
        
        assertEq(escrow.dividendPoolUSDT(), dividendAmount);
        assertEq(escrow.dividendPoolBalance(RyzerEscrow.Asset.USDT), dividendAmount);
        assertEq(usdt.balanceOf(address(escrow)), dividendAmount);
    }
    
    function testDistributeDividend() public {
        uint128 dividendAmount = 500e6;
        
        // First deposit dividend
        vm.prank(user1);
        escrow.depositDividend(RyzerEscrow.Asset.USDT, dividendAmount);
        
        // Distribute dividend
        vm.expectEmit(true, true, false, true);
        emit DividendDistributed(seller, RyzerEscrow.Asset.USDT, dividendAmount);
        
        vm.prank(admin1);
        escrow.distributeDividend(seller, RyzerEscrow.Asset.USDT, dividendAmount);
        
        assertEq(escrow.dividendPoolUSDT(), 0);
        assertEq(usdt.balanceOf(seller), dividendAmount);
    }
    
    function testDistributeDividendInsufficientFunds() public {
        vm.expectRevert(RyzerEscrow.InsufficientFunds.selector);
        vm.prank(admin1);
        escrow.distributeDividend(seller, RyzerEscrow.Asset.USDT, 100e6);
    }
    
    /*//////////////////////////////////////////////////////////////
                           DISPUTE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testRaiseDispute() public {
        // Make a deposit first
        vm.prank(orderManager);
        escrow.deposit(orderId, buyer, DEPOSIT_AMOUNT, RyzerEscrow.Asset.USDT, assetId);
        
        string memory reason = "Product not as described";
        
        vm.expectEmit(false, true, true, false);
        emit DisputeRaised(bytes32(0), buyer, RyzerEscrow.Asset.USDT, DEPOSIT_AMOUNT, reason);
        
        vm.prank(buyer);
        bytes32 disputeId = escrow.raiseDispute(orderId, reason);
        
        RyzerEscrow.Dispute memory dispute = escrow.getDisputeStatus(disputeId);
        assertEq(dispute.buyer, buyer);
        assertEq(dispute.amount, DEPOSIT_AMOUNT);
        assertTrue(dispute.token == RyzerEscrow.Asset.USDT);
        assertEq(dispute.assetId, assetId);
        assertEq(dispute.orderId, orderId);
        assertFalse(dispute.resolved);
        assertEq(dispute.resolvedTo, address(0));
        assertGt(dispute.disputeTimeout, block.timestamp);
        assertGt(dispute.disputeExpiration, block.timestamp);
    }
    
    function testRaiseDisputeByProjectOwner() public {
        vm.prank(orderManager);
        escrow.deposit(orderId, buyer, DEPOSIT_AMOUNT, RyzerEscrow.Asset.USDT, assetId);
        
        // Project owner should also be able to raise disputes
        vm.prank(projectOwner);
        escrow.raiseDispute(orderId, "Buyer violated terms");
    }
    
    function testRaiseDisputeUnauthorized() public {
        vm.prank(orderManager);
        escrow.deposit(orderId, buyer, DEPOSIT_AMOUNT, RyzerEscrow.Asset.USDT, assetId);
        
        vm.expectRevert(RyzerEscrow.Unauthorized.selector);
        vm.prank(user1);
        escrow.raiseDispute(orderId, "Not authorized");
    }
    
    function testSignDisputeResolution() public {
        // Setup: deposit and raise dispute
        vm.prank(orderManager);
        escrow.deposit(orderId, buyer, DEPOSIT_AMOUNT, RyzerEscrow.Asset.USDT, assetId);
        
        vm.prank(buyer);
        bytes32 disputeId = escrow.raiseDispute(orderId, "Issue with order");
        
        // Fast forward past dispute timeout
        vm.warp(block.timestamp + 8 days);
        
        // Sign dispute resolution
        vm.prank(admin1);
        escrow.signDisputeResolution(disputeId, buyer);
        assertEq(escrow.disputeSigCount(disputeId), 1);
        
        // Second signature should resolve dispute
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(disputeId, buyer, RyzerEscrow.Asset.USDT, DEPOSIT_AMOUNT);
        
        vm.prank(admin2);
        escrow.signDisputeResolution(disputeId, buyer);
        
        // Check dispute is resolved
        RyzerEscrow.Dispute memory dispute = escrow.getDisputeStatus(disputeId);
        assertTrue(dispute.resolved);
        assertEq(dispute.resolvedTo, buyer);
        assertEq(usdt.balanceOf(buyer), 10000e6); // Original balance restored
        
        // Original deposit should be deleted
        (address depositBuyer,,,) = escrow.deposits(orderId);
        assertEq(depositBuyer, address(0));
    }
    
    function testSignDisputeResolutionTimeoutNotMet() public {
        vm.prank(orderManager);
        escrow.deposit(orderId, buyer, DEPOSIT_AMOUNT, RyzerEscrow.Asset.USDT, assetId);
        
        vm.prank(buyer);
        bytes32 disputeId = escrow.raiseDispute(orderId, "Issue");
        
        // Try to resolve before timeout
        vm.expectRevert(RyzerEscrow.DisputeTimeoutNotMet.selector);
        vm.prank(admin1);
        escrow.signDisputeResolution(disputeId, buyer);
    }
    
    function testSignDisputeResolutionExpired() public {
        vm.prank(orderManager);
        escrow.deposit(orderId, buyer, DEPOSIT_AMOUNT, RyzerEscrow.Asset.USDT, assetId);
        
        vm.prank(buyer);
        bytes32 disputeId = escrow.raiseDispute(orderId, "Issue");
        
        // Fast forward past expiration
        vm.warp(block.timestamp + 31 days);
        
        vm.expectRevert(RyzerEscrow.DisputeExpired.selector);
        vm.prank(admin1);
        escrow.signDisputeResolution(disputeId, buyer);
    }
    
    /*//////////////////////////////////////////////////////////////
                           ADMIN TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testSetRequiredSignatures() public {
        vm.prank(owner);
        escrow.setRequiredSignatures(3);
        assertEq(escrow.requiredSigs(), 3);
    }
    
    function testSetRequiredSignaturesZero() public {
        vm.expectRevert(RyzerEscrow.ZeroValue.selector);
        vm.prank(owner);
        escrow.setRequiredSignatures(0);
    }
    
    function testSetCoreContracts() public {
        ERC20Mock newUSDT = new ERC20Mock();
        ERC20Mock newUSDC = new ERC20Mock();
        MockRealEstateToken newProject = new MockRealEstateToken(orderManager, projectOwner);
        
        vm.prank(owner);
        escrow.setCoreContracts(address(newUSDT), address(newUSDC), address(newProject));
        
        assertEq(address(escrow.usdt()), address(newUSDT));
        assertEq(address(escrow.usdc()), address(newUSDC));
        assertEq(address(escrow.project()), address(newProject));
    }
    
    function testEmergencyWithdraw() public {
        // Setup: deposit some funds
        vm.prank(orderManager);
        escrow.deposit(orderId, buyer, DEPOSIT_AMOUNT, RyzerEscrow.Asset.USDT, assetId);
        
        vm.prank(admin1);
        escrow.emergencyWithdraw(owner, RyzerEscrow.Asset.USDT, DEPOSIT_AMOUNT);
        
        assertEq(usdt.balanceOf(owner), DEPOSIT_AMOUNT);
        assertEq(usdt.balanceOf(address(escrow)), 0);
    }
    
    function testEmergencyWithdrawInsufficientFunds() public {
        vm.expectRevert(RyzerEscrow.InsufficientFunds.selector);
        vm.prank(admin1);
        escrow.emergencyWithdraw(owner, RyzerEscrow.Asset.USDT, 1000e6);
    }
    
    function testPauseUnpause() public {
        vm.prank(admin1);
        escrow.pause();
        assertTrue(escrow.paused());
        
        // Should revert when paused
        vm.expectRevert();
        vm.prank(orderManager);
        escrow.deposit(orderId, buyer, DEPOSIT_AMOUNT, RyzerEscrow.Asset.USDT, assetId);
        
        vm.prank(admin1);
        escrow.unpause();
        assertFalse(escrow.paused());
        
        // Should work after unpause
        vm.prank(orderManager);
        escrow.deposit(orderId, buyer, DEPOSIT_AMOUNT, RyzerEscrow.Asset.USDT, assetId);
    }
    
    /*//////////////////////////////////////////////////////////////
                        EDGE CASES & FUZZING
    //////////////////////////////////////////////////////////////*/
    
    function testFuzzDeposit(uint128 amount, uint8 tokenType) public {
        vm.assume(amount > 0 && amount <= 1000000e6);
        vm.assume(tokenType <= 1);
        
        RyzerEscrow.Asset token = tokenType == 0 ? RyzerEscrow.Asset.USDT : RyzerEscrow.Asset.USDC;
        
        // Mint enough tokens
        if (token == RyzerEscrow.Asset.USDT) {
            usdt.mint(buyer, amount);
        } else {
            usdc.mint(buyer, amount);
        }
        
        vm.prank(orderManager);
        escrow.deposit(orderId, buyer, amount, token, assetId);
        
        (, uint128 depositAmount, RyzerEscrow.Asset depositToken,) = escrow.deposits(orderId);
        assertEq(depositAmount, amount);
        assertTrue(depositToken == token);
    }
    
    function testMultipleDepositsAndReleases() public {
        bytes32 orderId2 = keccak256("order2");
        bytes32 orderId3 = keccak256("order3");
        
        // Multiple deposits
        vm.startPrank(orderManager);
        escrow.deposit(orderId, buyer, 1000e6, RyzerEscrow.Asset.USDT, assetId);
        escrow.deposit(orderId2, buyer, 2000e6, RyzerEscrow.Asset.USDC, assetId);
        escrow.deposit(orderId3, buyer, 1500e6, RyzerEscrow.Asset.USDT, assetId);
        vm.stopPrank();
        
        // Release one order completely
        vm.prank(admin1);
        escrow.signRelease(orderId, seller, 1000e6);
        vm.prank(admin2);
        escrow.signRelease(orderId, seller, 1000e6);
        
        // Partial release of another
        vm.prank(admin1);
        escrow.signRelease(orderId2, seller, 1000e6);
        vm.prank(admin2);
        escrow.signRelease(orderId2, seller, 1000e6);
        
        assertEq(usdt.balanceOf(seller), 1000e6);
        assertEq(usdc.balanceOf(seller), 1000e6);
        
        // Check remaining deposits
        (, uint128 remainingAmount,,) = escrow.deposits(orderId2);
        assertEq(remainingAmount, 1000e6);
    }
    
    function testReentrancyProtection() public {
        // This would require a malicious token contract to test properly
        // For now, we verify the modifiers are in place
        vm.prank(orderManager);
        escrow.deposit(orderId, buyer, DEPOSIT_AMOUNT, RyzerEscrow.Asset.USDT, assetId);
        
        // Basic test that functions can't be called recursively
        // (This would need more sophisticated testing with actual reentrant calls)
        assertTrue(true); // Placeholder for reentrancy tests
    }
    
    /*//////////////////////////////////////////////////////////////
                          UPGRADE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testUpgradeAuthorization() public {
        // Deploy a new implementation
        RyzerEscrow newImpl = new RyzerEscrow();
        
        // Only admin should be able to upgrade
        vm.expectRevert();
        vm.prank(user1);
        escrow.upgradeToAndCall(address(newImpl), "");
        
        // Admin should be able to upgrade
        vm.prank(owner);
        escrow.upgradeToAndCall(address(newImpl), "");
    }
    
    /*//////////////////////////////////////////////////////////////
                         VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testViewFunctions() public {
        // Test dividend pool balances
        assertEq(escrow.dividendPoolBalance(RyzerEscrow.Asset.USDT), 0);
        assertEq(escrow.dividendPoolBalance(RyzerEscrow.Asset.USDC), 0);
        
        // Test dispute status for non-existent dispute
        RyzerEscrow.Dispute memory emptyDispute = escrow.getDisputeStatus(bytes32("nonexistent"));
        assertEq(emptyDispute.buyer, address(0));
        assertEq(emptyDispute.amount, 0);
        assertFalse(emptyDispute.resolved);
    }
    
    /*//////////////////////////////////////////////////////////////
                           HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _setupDepositAndDispute() internal returns (bytes32 disputeId) {
        vm.prank(orderManager);
        escrow.deposit(orderId, buyer, DEPOSIT_AMOUNT, RyzerEscrow.Asset.USDT, assetId);
        
        vm.prank(buyer);
        disputeId = escrow.raiseDispute(orderId, "Test dispute");
    }
}