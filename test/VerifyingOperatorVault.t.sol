// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {TokenizedRealEstate} from "../src/TokenizedRealEstate.sol";
import {AssetTokenizationManager} from "../src/AssetTokenizationManager.sol";
import {DeployAssetTokenizationManager} from "../script/DeployAssetTokenizationManager.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {VerifyingOperatorVault} from "../src/VerifyingOperatorVault.sol";
import {ERC1967ProxyAutoUp} from "../src/ERC1967ProxyAutoUp.sol";
import {RealEstateRegistry} from "../src/RealEstateRegistry.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockERC20} from "./mocks/MockERC20Token.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract AssetTokenizationManagerTest is Test {
    error AssetTokenizationManager__BaseChainRequired();
    error AssetTokenizationManager__TokenNotWhitelisted();
    error AssetTokenizationManager__NotAssetOwner();
    error RealEstateRegistry__InvalidToken();
    error RealEstateRegistry__InvalidCollateral();

    // TokenizedRealEstate public tokenizedRealEstate;
    // address owner;
    // uint256 ownerKey;
    // HelperConfig public helperConfig;
    // HelperConfig.NetworkConfig public networkConfig;
    // AssetTokenizationManager public assetTokenizationManager;
    // DeployAssetTokenizationManager public deployer;
    VerifyingOperatorVault public vov;
    address public vovAddr;
    RealEstateRegistry public realEstateRegistry;
    address admin;
    address public user;
    address nodeOperator;
    address estateOwner;
    address slasher;
    address signer;
    uint256 signerKey;
    uint256 fiatReqForCollateral_RER;
    ERC20 mockToken;

    function setUp() public {
        vov = new VerifyingOperatorVault();
        vovAddr = address(vov);

        fiatReqForCollateral_RER = 3000; // 1000 USD

        admin = makeAddr("admin");
        nodeOperator = makeAddr("nodeOperator");
        estateOwner = makeAddr("estateOwner");
        slasher = makeAddr("slasher");
        (signer, signerKey) = makeAddrAndKey("signer");

        vm.startPrank(nodeOperator);
        mockToken = new MockERC20();
        MockV3Aggregator aggregator = new MockV3Aggregator(8, 3000e8);
        vm.stopPrank();

        address[] memory token = new address[](1);
        address[] memory dataFeeds = new address[](1);
        token[0] = address(mockToken);
        dataFeeds[0] = address(aggregator);

        vm.prank(admin);
        realEstateRegistry = new RealEstateRegistry(
            slasher,
            signer,
            fiatReqForCollateral_RER,
            token,
            dataFeeds,
            vovAddr,
            address(0),
            address(0)
        );
    }

    function test_DepositCollateralAndRegisterVault() public {
        bytes memory _signature = prepareAndSignSignature(nodeOperator, "meow");

        vm.startPrank(nodeOperator);

        mockToken.approve(address(realEstateRegistry), 1e18);
        realEstateRegistry.depositCollateralAndRegisterVault("meow", address(mockToken), _signature, true);

        vm.stopPrank();

        vm.prank(admin);
        realEstateRegistry.approveOperatorVault("meow");

        address vault = realEstateRegistry.getOperatorVault(nodeOperator);
        bool isApproved = realEstateRegistry.getOperatorInfo(nodeOperator).isApproved;
        require(vault != address(0) && isApproved, "Vault not registered");
        
        assert(ERC1967ProxyAutoUp(payable(vault)).getImplementation() == vovAddr);
        console.log(VerifyingOperatorVault(vault).isAutoUpdateEnabled());
    }

    function test_autoUpgradingChangesImplementation() public {
        bytes memory _signature = prepareAndSignSignature(nodeOperator, "meow");

        vm.startPrank(nodeOperator);

        mockToken.approve(address(realEstateRegistry), 1e18);
        realEstateRegistry.depositCollateralAndRegisterVault("meow", address(mockToken), _signature, true);

        vm.stopPrank();

        vm.prank(admin);
        realEstateRegistry.approveOperatorVault("meow");

        address newVovImplementation = address(new VerifyingOperatorVault());

        vm.prank(admin);
        realEstateRegistry.updateVOVImplementation(newVovImplementation);

        console.log("Old:", vovAddr);
        console.log("New:", newVovImplementation);
        
        address vault = realEstateRegistry.getOperatorVault(nodeOperator);
        assertEq(ERC1967ProxyAutoUp(payable(vault)).getImplementation(), newVovImplementation);

        vm.prank(nodeOperator);
        VerifyingOperatorVault(vault).toggleAutoUpdate();

        assert(VerifyingOperatorVault(vault).isAutoUpdateEnabled() == false);
        assertEq(ERC1967ProxyAutoUp(payable(vault)).getImplementation(), newVovImplementation);
    }

    function prepareAndSignSignature(address _nodeOperaror, string memory _ensName) internal view returns (bytes memory _signature) {
        bytes32 digest = realEstateRegistry.prepareRegisterVaultHash(_nodeOperaror, _ensName);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        _signature = abi.encodePacked(r, s, v);
    }
}
