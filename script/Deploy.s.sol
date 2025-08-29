// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Core contracts
import {RyzerRegistry} from "../src/RyzerRegistry.sol";
import {RyzerCompanyFactory} from "../src/RyzerCompanyFactory.sol";
import {RyzerRealEstateTokenFactory} from "../src/RyzerRealEstateFactory.sol";
import {RyzerEscrow} from "../src/RyzerEscrow.sol";
import {RyzerOrderManager} from "../src/RyzerOrderManager.sol";
import {RyzerDAO} from "../src/RyzerDAO.sol";
import {RyzerRealEstateToken} from "../src/RyzerRealEstateToken.sol";
import {RyzerCompany} from "../src/RyzerCompany.sol";
import {UsdtMock} from "../src/UsdtMock.sol";
import {UsdcMock} from "../src/UsdcMock.sol";
import {RyzerToken} from "../src/RyzerToken.sol";

// Mock contracts for testing/deployment
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

contract Deploy is Script {
    // Contract instances (proxies)
    RyzerRegistry public registry;
    RyzerCompanyFactory public companyFactory;
    RyzerRealEstateTokenFactory public realEstateFactory;
    
    // Implementation contracts
    RyzerEscrow public escrowImpl;
    RyzerOrderManager public orderManagerImpl;
    RyzerDAO public daoImpl;
    RyzerRealEstateToken public projectTokenImpl;
    RyzerCompany public ryzerCompanyImpl;

    // Mock tokens
    UsdtMock public usdt;
    UsdcMock public usdc;
    RyzerToken public ryzerToken;

    // Mock contracts for TREX compliance
    MockIdentityRegistry public identityRegistry;
    MockModularCompliance public modularCompliance;
    MockClaimIssuerRegistry public claimIssuerRegistry;
    MockClaimRegistry public claimRegistry;
    MockValidationLibrary public validationLibrary;

    // Deployment parameters
    address public deployer;
    address public admin = 0xFDa522b8c863ed7Abf681d0c86Cc0c5DCb95d4E6; // Replace with your admin address

    // XDC Apothem testnet parameters
    uint256 public constant APOTHEM_CHAIN_ID = 51;
    string public constant RPC_URL = "https://erpc.apothem.network";

    function run() external {
        // Get deployer from private key
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.rememberKey(deployerPrivateKey);

        // Set the chain ID for XDC Apothem
        vm.chainId(APOTHEM_CHAIN_ID);

        console.log("Deployer:", deployer);
        console.log("Admin:", admin);
        console.log("Deploying to XDC Apothem testnet...");

        // Start broadcasting transactions
        vm.startBroadcast(deployer);

        // 1. Deploy mock contracts for TREX compliance
        console.log("Deploying mock TREX compliance contracts...");
        identityRegistry = new MockIdentityRegistry();
        modularCompliance = new MockModularCompliance();
        claimIssuerRegistry = new MockClaimIssuerRegistry();
        claimRegistry = new MockClaimRegistry();
        validationLibrary = new MockValidationLibrary();

        console.log("MockIdentityRegistry deployed at:", address(identityRegistry));
        console.log("MockModularCompliance deployed at:", address(modularCompliance));
        console.log("MockClaimIssuerRegistry deployed at:", address(claimIssuerRegistry));
        console.log("MockClaimRegistry deployed at:", address(claimRegistry));
        console.log("MockValidationLibrary deployed at:", address(validationLibrary));

        // 2. Deploy mock tokens (for testnet only)
        console.log("Deploying mock tokens...");
        usdt = new UsdtMock();
        usdc = new UsdcMock();
        ryzerToken = new RyzerToken();

        console.log("USDT deployed at:", address(usdt));
        console.log("USDC deployed at:", address(usdc));
        console.log("RyzerToken deployed at:", address(ryzerToken));

        // 3. Deploy implementation contracts
        console.log("Deploying implementation contracts...");
        ryzerCompanyImpl = new RyzerCompany();
        projectTokenImpl = new RyzerRealEstateToken();
        daoImpl = new RyzerDAO();
        escrowImpl = new RyzerEscrow();
        orderManagerImpl = new RyzerOrderManager();

        console.log("Implementation contracts deployed");
        console.log("RyzerCompany impl:", address(ryzerCompanyImpl));
        console.log("RyzerRealEstateToken impl:", address(projectTokenImpl));
        console.log("RyzerDAO impl:", address(daoImpl));
        console.log("RyzerEscrow impl:", address(escrowImpl));
        console.log("RyzerOrderManager impl:", address(orderManagerImpl));

        // 3. Deploy and initialize registry
        console.log("Deploying registry...");
        RyzerRegistry registryImpl = new RyzerRegistry();
        bytes memory registryInitData = abi.encodeWithSignature("initialize()");
        ERC1967Proxy registryProxy = new ERC1967Proxy(address(registryImpl), registryInitData);
        registry = RyzerRegistry(address(registryProxy));

        console.log("Registry deployed at:", address(registry));

        // 4. Deploy and initialize company factory
        console.log("Deploying company factory...");
        RyzerCompanyFactory companyFactoryImpl = new RyzerCompanyFactory();
        bytes memory companyFactoryInitData = abi.encodeWithSignature("initialize(address)", address(ryzerCompanyImpl));
        ERC1967Proxy companyFactoryProxy = new ERC1967Proxy(address(companyFactoryImpl), companyFactoryInitData);
        companyFactory = RyzerCompanyFactory(address(companyFactoryProxy));

        console.log("Company Factory deployed at:", address(companyFactory));

        // 5. Deploy and initialize real estate factory
        console.log("Deploying real estate factory...");
        RyzerRealEstateTokenFactory realEstateFactoryImpl = new RyzerRealEstateTokenFactory();
        
        bytes memory realEstateFactoryInitData = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address,address)",
            address(usdc),           // USDC address
            address(usdt),           // USDT address
            address(ryzerToken),     // RyzerX token address
            address(projectTokenImpl), // Project token implementation
            address(escrowImpl),     // Escrow implementation
            address(orderManagerImpl), // Order manager implementation
            address(daoImpl)         // DAO implementation
        );
        
        ERC1967Proxy realEstateFactoryProxy = new ERC1967Proxy(
            address(realEstateFactoryImpl), 
            realEstateFactoryInitData
        );
        realEstateFactory = RyzerRealEstateTokenFactory(address(realEstateFactoryProxy));

        console.log("Real Estate Factory deployed at:", address(realEstateFactory));

        // 6. Set up admin roles
        console.log("Setting up admin roles...");
        
        // Grant admin role on real estate factory
        realEstateFactory.grantRole(realEstateFactory.ADMIN_ROLE(), admin);
        
        // If deployer is different from admin, transfer ownership
        if (deployer != admin) {
            // Grant admin role to the specified admin address
            realEstateFactory.grantRole(realEstateFactory.DEFAULT_ADMIN_ROLE(), admin);
            
            // Optionally revoke deployer's admin role if desired
            // realEstateFactory.revokeRole(realEstateFactory.DEFAULT_ADMIN_ROLE(), deployer);
        }

        // 7. Mint some test tokens to admin and deployer for testing
        console.log("Minting test tokens...");
        usdt.mint(admin, 1_000_000 * 10 ** 6);      // 1M USDT to admin
        usdt.mint(deployer, 100_000 * 10 ** 6);     // 100K USDT to deployer
        usdc.mint(admin, 1_000_000 * 10 ** 6);      // 1M USDC to admin
        usdc.mint(deployer, 100_000 * 10 ** 6);     // 100K USDC to deployer

        vm.stopBroadcast();

        // Log all deployed contract addresses
        console.log("\n=== Deployment Summary ===");
        console.log("Network: XDC Apothem Testnet");
        console.log("Chain ID:", APOTHEM_CHAIN_ID);
        console.log("Deployer:", deployer);
        console.log("Admin:", admin);
        
        console.log("\n--- Core Contracts (Proxies) ---");
        console.log("RyzerRegistry:", address(registry));
        console.log("RyzerCompanyFactory:", address(companyFactory));
        console.log("RyzerRealEstateTokenFactory:", address(realEstateFactory));
        
        console.log("\n--- Implementation Contracts ---");
        console.log("RyzerCompany (impl):", address(ryzerCompanyImpl));
        console.log("RyzerRealEstateToken (impl):", address(projectTokenImpl));
        console.log("RyzerEscrow (impl):", address(escrowImpl));
        console.log("RyzerOrderManager (impl):", address(orderManagerImpl));
        console.log("RyzerDAO (impl):", address(daoImpl));
        
        console.log("\n--- Mock TREX Compliance Contracts ---");
        console.log("MockIdentityRegistry:", address(identityRegistry));
        console.log("MockModularCompliance:", address(modularCompliance));
        console.log("MockClaimIssuerRegistry:", address(claimIssuerRegistry));
        console.log("MockClaimRegistry:", address(claimRegistry));
        console.log("MockValidationLibrary:", address(validationLibrary));
        
        console.log("\n--- Mock Tokens ---");
        console.log("USDT Mock:", address(usdt));
        console.log("USDC Mock:", address(usdc));
        console.log("RyzerToken:", address(ryzerToken));
        
        console.log("\n=== Deployment Complete ===");

        // Additional verification
        console.log("\n--- Verification ---");
        console.log("Registry initialized:", address(registry) != address(0));
        console.log("Company Factory initialized:", address(companyFactory) != address(0));
        console.log("Real Estate Factory initialized:", address(realEstateFactory) != address(0));
        console.log("Admin has ADMIN_ROLE on Real Estate Factory:", realEstateFactory.hasRole(realEstateFactory.ADMIN_ROLE(), admin));
        console.log("Mock contracts deployed:", address(identityRegistry) != address(0) && address(modularCompliance) != address(0));
    }
}