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
import {ModularCompliance} from "../src/TREX/compliance/modular/ModularCompliance.sol";
import {IdentityRegistry} from "../src/TREX/registry/implementation/IdentityRegistry.sol";

contract DeployLocalScript is Script {
    // Contract instances
    RyzerRegistry public registry;
    RyzerCompanyFactory public companyFactory;
    RyzerRealEstateTokenFactory public realEstateFactory;
    RyzerEscrow public escrowImpl;
    RyzerOrderManager public orderManagerImpl;
    RyzerDAO public daoImpl;
    RyzerRealEstateToken public projectTokenImpl;
    RyzerCompany public ryzerCompanyImpl;
    ModularCompliance public modularCompliance;
    IdentityRegistry public identityRegistry;

    // Proxy contracts
    ERC1967Proxy public ryzerRegistryProxy;
    ERC1967Proxy public ryzerCompanyFactoryProxy;
    ERC1967Proxy public ryzerRealEstateFactoryProxy;

    // Mock tokens
    UsdtMock public usdt;
    UsdcMock public usdc;

    // Deployment parameters
    address public deployer;
    address public admin;

    // Local Anvil parameters
    uint256 public constant LOCAL_CHAIN_ID = 31337;
    string public constant RPC_URL = "http://localhost:8545";

    function run() external {
        // For local deployment, use default anvil account or environment variable
        uint256 deployerPrivateKey;

        // Try to get private key from environment, fallback to default anvil key
        try vm.envUint("PRIVATE_KEY") returns (uint256 key) {
            deployerPrivateKey = key;
        } catch {
            // Default Anvil account #0 private key
            deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
            console.log("Using default Anvil private key");
        }

        deployer = vm.rememberKey(deployerPrivateKey);
        admin = deployer; // For local deployment, deployer is also admin

        console.log("Deployer:", deployer);
        console.log("Admin:", admin);
        console.log("Deploying to Local Anvil blockchain...");
        console.log("Chain ID:", block.chainid);

        // Start broadcasting transactions
        vm.startBroadcast(deployer);

        // 1. Deploy mock tokens
        console.log("Deploying mock tokens...");
        usdt = new UsdtMock();
        usdc = new UsdcMock();
        console.log("USDT Mock deployed at:", address(usdt));
        console.log("USDC Mock deployed at:", address(usdc));

        // 2. Deploy implementation contracts
        console.log("Deploying implementation contracts...");

        ryzerCompanyImpl = new RyzerCompany();
        console.log("RyzerCompany implementation deployed at:", address(ryzerCompanyImpl));

        projectTokenImpl = new RyzerRealEstateToken();
        console.log("RyzerRealEstateToken implementation deployed at:", address(projectTokenImpl));

        daoImpl = new RyzerDAO();
        console.log("RyzerDAO implementation deployed at:", address(daoImpl));

        escrowImpl = new RyzerEscrow();
        console.log("RyzerEscrow implementation deployed at:", address(escrowImpl));

        orderManagerImpl = new RyzerOrderManager();
        console.log("RyzerOrderManager implementation deployed at:", address(orderManagerImpl));

        companyFactory = new RyzerCompanyFactory();
        console.log("RyzerCompanyFactory implementation deployed at:", address(companyFactory));

        realEstateFactory = new RyzerRealEstateTokenFactory();
        console.log("RyzerRealEstateTokenFactory implementation deployed at:", address(realEstateFactory));

        registry = new RyzerRegistry();
        console.log("RyzerRegistry implementation deployed at:", address(registry));

        modularCompliance = new ModularCompliance();
        console.log("ModularCompliance deployed at:", address(modularCompliance));

        identityRegistry = new IdentityRegistry();
        console.log("IdentityRegistry deployed at:", address(identityRegistry));

        // 3. Deploy and initialize proxies
        console.log("Deploying and initializing proxies...");

        // Deploy RyzerRegistry proxy
        bytes memory ryzerRegistryInitData = abi.encodeWithSignature("initialize()");
        ryzerRegistryProxy = new ERC1967Proxy(address(registry), ryzerRegistryInitData);
        console.log("RyzerRegistry proxy deployed at:", address(ryzerRegistryProxy));

        // Deploy RyzerCompanyFactory proxy
        bytes memory ryzerCompanyFactoryInitData =
            abi.encodeWithSignature("initialize(address)", address(ryzerCompanyImpl));
        ryzerCompanyFactoryProxy = new ERC1967Proxy(address(companyFactory), ryzerCompanyFactoryInitData);
        console.log("RyzerCompanyFactory proxy deployed at:", address(ryzerCompanyFactoryProxy));

        // Deploy RyzerRealEstateFactory proxy
        bytes memory realEstateFactoryInitData = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address,address)",
            address(usdc),
            address(usdt),
            address(modularCompliance), // Using modularCompliance instead of zero address
            address(projectTokenImpl),
            address(escrowImpl),
            address(orderManagerImpl),
            address(daoImpl)
        );
        ryzerRealEstateFactoryProxy = new ERC1967Proxy(address(realEstateFactory), realEstateFactoryInitData);
        console.log("RyzerRealEstateFactory proxy deployed at:", address(ryzerRealEstateFactoryProxy));

        vm.stopBroadcast();

        // Log deployment summary
        console.log("\n=== LOCAL DEPLOYMENT SUMMARY ===");
        console.log("Network: Local Anvil");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("Admin:", admin);
        console.log("");

        console.log("=== Implementation Contracts ===");
        console.log("RyzerRegistry (impl):", address(registry));
        console.log("RyzerCompanyFactory (impl):", address(companyFactory));
        console.log("RyzerRealEstateTokenFactory (impl):", address(realEstateFactory));
        console.log("RyzerEscrow (impl):", address(escrowImpl));
        console.log("RyzerOrderManager (impl):", address(orderManagerImpl));
        console.log("RyzerDAO (impl):", address(daoImpl));
        console.log("RyzerRealEstateToken (impl):", address(projectTokenImpl));
        console.log("RyzerCompany (impl):", address(ryzerCompanyImpl));
        console.log("");

        console.log("=== Proxy Contracts ===");
        console.log("RyzerRegistry (proxy):", address(ryzerRegistryProxy));
        console.log("RyzerCompanyFactory (proxy):", address(ryzerCompanyFactoryProxy));
        console.log("RyzerRealEstateFactory (proxy):", address(ryzerRealEstateFactoryProxy));
        console.log("");

        console.log("=== Supporting Contracts ===");
        console.log("ModularCompliance:", address(modularCompliance));
        console.log("IdentityRegistry:", address(identityRegistry));
        console.log("");

        console.log("=== Mock Tokens ===");
        console.log("USDT Mock:", address(usdt));
        console.log("USDC Mock:", address(usdc));

        // Save deployment addresses to a file for easy reference
        _saveDeploymentAddresses();
    }

    function _saveDeploymentAddresses() internal {
        string memory deploymentInfo = string.concat(
            "# Local Deployment Addresses\n\n",
            "## Proxy Contracts (Use these addresses)\n",
            "- RyzerRegistry: ",
            vm.toString(address(ryzerRegistryProxy)),
            "\n",
            "- RyzerCompanyFactory: ",
            vm.toString(address(ryzerCompanyFactoryProxy)),
            "\n",
            "- RyzerRealEstateFactory: ",
            vm.toString(address(ryzerRealEstateFactoryProxy)),
            "\n\n",
            "## Mock Tokens\n",
            "- USDT: ",
            vm.toString(address(usdt)),
            "\n",
            "- USDC: ",
            vm.toString(address(usdc)),
            "\n\n",
            "## Supporting Contracts\n",
            "- ModularCompliance: ",
            vm.toString(address(modularCompliance)),
            "\n",
            "- IdentityRegistry: ",
            vm.toString(address(identityRegistry)),
            "\n"
        );

        vm.writeFile("deployments/local.md", deploymentInfo);
        console.log("\nDeployment addresses saved to: deployments/local.md");
    }
}
