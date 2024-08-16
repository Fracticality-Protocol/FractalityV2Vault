// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "@forge-std/Test.sol";
import {FractalityV2Vault} from "../src/FractalityV2Vault.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {console} from "@forge-std/console.sol";

contract FractalityV2VaultTest is Test {
    //contracts
    FractalityV2Vault public vault;
    MockERC20 public mockToken;
    //addresses
    address public admin = address(0x1);
    address public pnlReporter = address(0x2);
    address public strategy = address(0x3);
    address public redeemFeeCollector = address(0x4);

    address public user1 = address(0x5);
    address public user2 = address(0x6);

    //token settings
    uint256 public initialTokenAmount = 1000000000 * 1e18; // 1 billion$
    uint256 public initialUserMintAmount = 1000000 * 1e18; // 1 million$

    //vault settings
    uint16 public redeemFeeBasisPoints = 20; // 0.20%
    uint32 public claimableDelay = 86400; // 1 day
    uint8 public strategyType = 0; //EOA
    string public strategyName = "Mock Strategy";
    string public strategyURI = "https://mockstrategy.com";
    string public vaultSharesName = "Fractality Vault Shares";
    string public vaultSharesSymbol = "FVS";

    uint128 public maxDepositPerTransaction = 1000000 * 1e18; //100,000$
    uint128 public minDepositPerTransaction = 100 * 1e18; //100$
    uint256 public maxVaultCapacity = 100000000 * 1e18; //100 million$

    struct RedeemRequestData {
        uint256 redeemRequestShareAmount; //256 -> slot
        uint256 redeemRequestAssetAmount; //256 -> slot
        uint96 redeemRequestCreationTime; //96
        address originalSharesOwner; //160 -> slot
        uint16 redeemFeeBasisPoints; //16 -> slot
    }

    function setUp() public {
        // Deploy mock ERC20 token
        mockToken = new MockERC20(initialTokenAmount);

        // Deploy FractalityV2Vault
        FractalityV2Vault.ConstructorParams memory params = FractalityV2Vault
            .ConstructorParams({
                asset: address(mockToken),
                redeemFeeBasisPoints: redeemFeeBasisPoints,
                claimableDelay: claimableDelay,
                strategyType: strategyType,
                strategyAddress: strategy,
                redeemFeeCollector: redeemFeeCollector,
                pnlReporter: pnlReporter,
                maxDepositPerTransaction: maxDepositPerTransaction,
                minDepositPerTransaction: minDepositPerTransaction,
                maxVaultCapacity: maxVaultCapacity,
                strategyName: strategyName,
                strategyURI: strategyURI,
                vaultSharesName: vaultSharesName,
                vaultSharesSymbol: vaultSharesSymbol
            });

        vm.prank(admin);
        vault = new FractalityV2Vault(params);

        // Mint some tokens to users
        mockToken.mint(initialUserMintAmount, user1);
        mockToken.mint(initialUserMintAmount, user2);
    }

    function testInitialState() public {
        (
            address strategyAddress,
            FractalityV2Vault.StrategyAddressType strategyAddressType,
            string memory _strategyURI,
            string memory _strategyName
        ) = vault.strategy();

        assertEq(strategyAddress, strategy);
        assertEq(uint8(strategyAddressType), strategyType);

        assertEq(_strategyURI, strategyURI);
        assertEq(_strategyName, strategyName);

        assertEq(vault.maxDepositPerTransaction(), maxDepositPerTransaction);
        assertEq(vault.minDepositPerTransaction(), minDepositPerTransaction);
        assertEq(vault.maxVaultCapacity(), maxVaultCapacity);
        assertEq(vault.redeemFeeBasisPoints(), redeemFeeBasisPoints);
        assertEq(vault.claimableDelay(), claimableDelay);

        assertEq(vault.redeemFeeCollector(), redeemFeeCollector);

        assertEq(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(vault.hasRole(vault.PNL_REPORTER_ROLE(), pnlReporter), true);
    }

    function testInvalidDeployment_fails_ZeroAddress() public {
        //NOTE: cannot set the asset to the zero address, gets reverted in the erc20 constructor
        // Deploy mock ERC20 token
        mockToken = new MockERC20(initialTokenAmount);

        //correct params
        FractalityV2Vault.ConstructorParams memory params = FractalityV2Vault
            .ConstructorParams({
                asset: address(mockToken),
                redeemFeeBasisPoints: redeemFeeBasisPoints,
                claimableDelay: claimableDelay,
                strategyType: strategyType,
                strategyAddress: strategy,
                redeemFeeCollector: redeemFeeCollector,
                pnlReporter: pnlReporter,
                maxDepositPerTransaction: maxDepositPerTransaction,
                minDepositPerTransaction: minDepositPerTransaction,
                maxVaultCapacity: maxVaultCapacity,
                strategyName: strategyName,
                strategyURI: strategyURI,
                vaultSharesName: vaultSharesName,
                vaultSharesSymbol: vaultSharesSymbol
            });

        //strategy address is the zero address
        params.strategyAddress = address(0);
        vm.expectRevert(FractalityV2Vault.ZeroAddress.selector);
        vm.prank(admin);
        vault = new FractalityV2Vault(params);

        //pnlReporter is the zero address
        params.strategyAddress = strategy;
        params.pnlReporter = address(0);

        vm.expectRevert(FractalityV2Vault.ZeroAddress.selector);
        vm.prank(admin);
        vault = new FractalityV2Vault(params);

        //redeemFeeCollector is the zero address
        params.pnlReporter = pnlReporter;
        params.redeemFeeCollector = address(0);

        vm.expectRevert(FractalityV2Vault.ZeroAddress.selector);
        vm.prank(admin);
        vault = new FractalityV2Vault(params);
    }

    function testInvalidDeployment_fails_InvalidMinDepositPerTransaction()
        public
    {
        // Deploy mock ERC20 token
        mockToken = new MockERC20(initialTokenAmount);

        //correct params
        FractalityV2Vault.ConstructorParams memory params = FractalityV2Vault
            .ConstructorParams({
                asset: address(mockToken),
                redeemFeeBasisPoints: redeemFeeBasisPoints,
                claimableDelay: claimableDelay,
                strategyType: strategyType,
                strategyAddress: strategy,
                redeemFeeCollector: redeemFeeCollector,
                pnlReporter: pnlReporter,
                maxDepositPerTransaction: maxDepositPerTransaction,
                minDepositPerTransaction: minDepositPerTransaction,
                maxVaultCapacity: maxVaultCapacity,
                strategyName: strategyName,
                strategyURI: strategyURI,
                vaultSharesName: vaultSharesName,
                vaultSharesSymbol: vaultSharesSymbol
            });
        //minDepositPerTransaction is greater than maxDepositPerTransaction
        params.minDepositPerTransaction = maxDepositPerTransaction + 1;
        vm.expectRevert(
            FractalityV2Vault.InvalidMinDepositPerTransaction.selector
        );
        vm.prank(admin);
        vault = new FractalityV2Vault(params);
    }

    function testInvalidDeployment_fails_InvalidMaxVaultCapacity() public {
        // Deploy mock ERC20 token
        mockToken = new MockERC20(initialTokenAmount);

        //correct params
        FractalityV2Vault.ConstructorParams memory params = FractalityV2Vault
            .ConstructorParams({
                asset: address(mockToken),
                redeemFeeBasisPoints: redeemFeeBasisPoints,
                claimableDelay: claimableDelay,
                strategyType: strategyType,
                strategyAddress: strategy,
                redeemFeeCollector: redeemFeeCollector,
                pnlReporter: pnlReporter,
                maxDepositPerTransaction: maxDepositPerTransaction,
                minDepositPerTransaction: minDepositPerTransaction,
                maxVaultCapacity: maxVaultCapacity,
                strategyName: strategyName,
                strategyURI: strategyURI,
                vaultSharesName: vaultSharesName,
                vaultSharesSymbol: vaultSharesSymbol
            });
        params.maxVaultCapacity = 0;
        vm.expectRevert(FractalityV2Vault.InvalidMaxVaultCapacity.selector);
        vm.prank(admin);
        vault = new FractalityV2Vault(params);
    }

    function testInvalidDeployment_fails_InvalidRedeemFee() public {
        // Deploy mock ERC20 token
        mockToken = new MockERC20(initialTokenAmount);

        //correct params
        FractalityV2Vault.ConstructorParams memory params = FractalityV2Vault
            .ConstructorParams({
                asset: address(mockToken),
                redeemFeeBasisPoints: redeemFeeBasisPoints,
                claimableDelay: claimableDelay,
                strategyType: strategyType,
                strategyAddress: strategy,
                redeemFeeCollector: redeemFeeCollector,
                pnlReporter: pnlReporter,
                maxDepositPerTransaction: maxDepositPerTransaction,
                minDepositPerTransaction: minDepositPerTransaction,
                maxVaultCapacity: maxVaultCapacity,
                strategyName: strategyName,
                strategyURI: strategyURI,
                vaultSharesName: vaultSharesName,
                vaultSharesSymbol: vaultSharesSymbol
            });
        params.redeemFeeBasisPoints = 10001;
        vm.expectRevert(FractalityV2Vault.InvalidRedeemFee.selector);
        vm.prank(admin);
        vault = new FractalityV2Vault(params);
    }

    function testInvalidDeployment_fails_InvalidStrategyType() public {
        // Deploy mock ERC20 token
        mockToken = new MockERC20(initialTokenAmount);

        //correct params
        FractalityV2Vault.ConstructorParams memory params = FractalityV2Vault
            .ConstructorParams({
                asset: address(mockToken),
                redeemFeeBasisPoints: redeemFeeBasisPoints,
                claimableDelay: claimableDelay,
                strategyType: strategyType,
                strategyAddress: strategy,
                redeemFeeCollector: redeemFeeCollector,
                pnlReporter: pnlReporter,
                maxDepositPerTransaction: maxDepositPerTransaction,
                minDepositPerTransaction: minDepositPerTransaction,
                maxVaultCapacity: maxVaultCapacity,
                strategyName: strategyName,
                strategyURI: strategyURI,
                vaultSharesName: vaultSharesName,
                vaultSharesSymbol: vaultSharesSymbol
            });
        params.strategyType = 4;
        vm.expectRevert(FractalityV2Vault.InvalidStrategyType.selector);
        vm.prank(admin);
        vault = new FractalityV2Vault(params);
    }

    //test setters

    function testSetClaimableDelay() public {
        uint32 newClaimableDelay = 100; // 1 day
        vm.prank(admin);
        vault.setClaimableDelay(newClaimableDelay);
        assertEq(vault.claimableDelay(), newClaimableDelay);
    }

    function testSetHaltStatus() public {
        vm.prank(admin);
        vault.setHaltStatus(true);
        assertEq(vault.halted(), true);
    }

    function testSetHaltStatus_fails_HaltStatusUnchanged() public {
        vm.expectRevert(FractalityV2Vault.HaltStatusUnchanged.selector);
        vm.prank(admin);
        vault.setHaltStatus(false);
    }

    function testSetMaxDepositPerTransaction(
        uint128 newMaxDepositPerTransaction
    ) public {
        vm.assume(newMaxDepositPerTransaction > minDepositPerTransaction);
        vm.assume(newMaxDepositPerTransaction < maxVaultCapacity);
        vm.prank(admin);
        vault.setMaxDepositPerTransaction(newMaxDepositPerTransaction);
        assertEq(vault.maxDepositPerTransaction(), newMaxDepositPerTransaction);
    }

    function testSetMaxDepositPerTransaction_fails_InvalidMaxDepositPerTransaction(
        uint128 newMaxDepositPerTransaction
    ) public {
        vm.assume(newMaxDepositPerTransaction < minDepositPerTransaction);
        vm.expectRevert(
            FractalityV2Vault.InvalidMaxDepositPerTransaction.selector
        );
        vm.prank(admin);
        vault.setMaxDepositPerTransaction(newMaxDepositPerTransaction);
    }

    function testSetMinDepositPerTransaction(
        uint128 newMinDepositPerTransaction
    ) public {
        vm.assume(newMinDepositPerTransaction < maxDepositPerTransaction);
        vm.prank(admin);
        vault.setMinDepositPerTransaction(newMinDepositPerTransaction);
        assertEq(vault.minDepositPerTransaction(), newMinDepositPerTransaction);
    }

    function testSetMinDepositPerTransaction_fails_InvalidMinDepositPerTransaction(
        uint128 newMinDepositPerTransaction
    ) public {
        vm.assume(newMinDepositPerTransaction > maxDepositPerTransaction);
        vm.assume(newMinDepositPerTransaction < maxVaultCapacity);
        vm.expectRevert(
            FractalityV2Vault.InvalidMinDepositPerTransaction.selector
        );
        vm.prank(admin);
        vault.setMinDepositPerTransaction(newMinDepositPerTransaction);
    }

    function testSetMaxVaultCapacity(uint256 newMaxVaultCapacity) public {
        vm.assume(newMaxVaultCapacity > vault.vaultAssets());
        vm.prank(admin);
        vault.setMaxVaultCapacity(newMaxVaultCapacity);
        assertEq(vault.maxVaultCapacity(), newMaxVaultCapacity);
    }

    function testSetMaxVaultCapacity_fails_InvalidMaxVaultCapacity(
        uint256 newMaxVaultCapacity
    ) public {
        uint256 assetsToDeposit = initialUserMintAmount;
        vm.startPrank(user1);
        vault.asset().approve(address(vault), assetsToDeposit);
        vault.deposit(assetsToDeposit, user1);
        vm.stopPrank();

        vm.assume(newMaxVaultCapacity < vault.vaultAssets());
        vm.expectRevert(FractalityV2Vault.InvalidMaxVaultCapacity.selector);
        vm.prank(admin);
        vault.setMaxVaultCapacity(newMaxVaultCapacity);
    }

    function testSetOperator() public {
        vm.startPrank(user1);
        vault.setOperator(user2, true);
        assertEq(vault.isOperator(user1, user2), true);
        vault.setOperator(user2, false);
        assertEq(vault.isOperator(user1, user2), false);
    }

    function testSetOperator_fails_zeroAddress() public {
        vm.startPrank(user1);
        vm.expectRevert(FractalityV2Vault.ZeroAddress.selector);
        vault.setOperator(address(0), true);
    }

    function testSetRedeemFee() public {
        uint16 newRedeemFeeBasisPoints = 10;
        vm.prank(admin);
        vault.setRedeemFee(newRedeemFeeBasisPoints);
        assertEq(vault.redeemFeeBasisPoints(), newRedeemFeeBasisPoints);
    }

    function testSetRedeemFee_fails_InvalidRedeemFee() public {
        uint16 newRedeemFeeBasisPoints = 10001;
        vm.prank(admin);
        vm.expectRevert(FractalityV2Vault.InvalidRedeemFee.selector);
        vault.setRedeemFee(newRedeemFeeBasisPoints);
    }

    function testSetStrategyName() public {
        string memory newStrategyName = "New Strategy";
        vm.prank(admin);
        vault.setStrategyName(newStrategyName);
        (
            address strategyAddress,
            FractalityV2Vault.StrategyAddressType strategyAddressType,
            string memory _strategyURI,
            string memory _strategyName
        ) = vault.strategy();
        assertEq(_strategyName, newStrategyName);
    }

    function testSetStrategyURI() public {
        string memory newStrategyURI = "https://newstrategy.com";
        vm.prank(admin);
        vault.setStrategyURI(newStrategyURI);
        (
            address strategyAddress,
            FractalityV2Vault.StrategyAddressType strategyAddressType,
            string memory _strategyURI,
            string memory _strategyName
        ) = vault.strategy();
        assertEq(_strategyURI, newStrategyURI);
    }

    function testSetRedeemFeeCollector() public {
        address newRedeemFeeCollector = address(0x47);
        vm.prank(admin);
        vault.setRedeemFeeCollector(newRedeemFeeCollector);
        assertEq(vault.redeemFeeCollector(), newRedeemFeeCollector);
    }

    function testSetRedeemFeeCollector_fails_ZeroAddress() public {
        address newRedeemFeeCollector = address(0);
        vm.expectRevert(FractalityV2Vault.ZeroAddress.selector);
        vm.prank(admin);
        vault.setRedeemFeeCollector(newRedeemFeeCollector);
    }

    //Deposit&Mint tests

    function testDeposit(uint256 assetsToDeposit) public {
        vm.assume(assetsToDeposit >= minDepositPerTransaction);
        vm.assume(assetsToDeposit <= maxDepositPerTransaction);
        vm.startPrank(user1);
        vault.asset().approve(address(vault), assetsToDeposit);

        (address strategyAddress, , , ) = vault.strategy();

        uint256 prevVaultAssets = vault.vaultAssets();
        uint256 prevUserShareBalance = vault.balanceOf(user1);
        uint256 prevStrategyAssets = vault.asset().balanceOf(strategyAddress);

        uint256 sharesObtainedPreview = vault.previewDeposit(assetsToDeposit);
        uint256 sharesObtained = vault.deposit(assetsToDeposit, user1);
        vm.stopPrank();

        assertEq(sharesObtained, sharesObtainedPreview);

        _checkDepositOrMint(
            user1,
            assetsToDeposit,
            sharesObtained,
            strategyAddress,
            prevVaultAssets,
            prevUserShareBalance,
            prevStrategyAssets
        );
    }

    function testDeposit_fails_Halted(uint256 assetsToDeposit) public {
        vm.assume(assetsToDeposit >= minDepositPerTransaction);
        vm.assume(assetsToDeposit <= maxDepositPerTransaction);

        vm.prank(admin);
        vault.setHaltStatus(true);

        vm.startPrank(user1);
        vault.asset().approve(address(vault), assetsToDeposit);

        vm.expectRevert(FractalityV2Vault.Halted.selector);
        vault.deposit(assetsToDeposit, user1);
        vm.stopPrank();
    }

    function testDeposit_fails_InsufficientAllowance(
        uint256 assetsToDeposit
    ) public {
        vm.assume(assetsToDeposit >= minDepositPerTransaction);
        vm.assume(assetsToDeposit <= maxDepositPerTransaction);
        vm.startPrank(user1);

        (address strategyAddress, , , ) = vault.strategy();

        uint256 prevVaultAssets = vault.vaultAssets();
        uint256 prevUserShareBalance = vault.balanceOf(user1);
        uint256 prevStrategyAssets = vault.asset().balanceOf(strategyAddress);

        uint256 sharesObtainedPreview = vault.previewDeposit(assetsToDeposit);

        vm.expectRevert(FractalityV2Vault.InsufficientAllowance.selector);
        vault.deposit(assetsToDeposit, user1);
    }

    //Scenario where the vault has been doing very well, and the user is trying to deposit assets so little that they get (truncated)
    function testDeposit_fails_ZeroShares() public {
        uint256 assetsToDeposit = minDepositPerTransaction;
        vm.startPrank(user1);
        vault.asset().approve(address(vault), assetsToDeposit);

        (address strategyAddress, , , ) = vault.strategy();

        uint256 prevVaultAssets = vault.vaultAssets();
        uint256 prevUserShareBalance = vault.balanceOf(user1);
        uint256 prevStrategyAssets = vault.asset().balanceOf(strategyAddress);

        uint256 sharesObtained = vault.deposit(assetsToDeposit, user1);
        vm.stopPrank();

        _checkDepositOrMint(
            user1,
            assetsToDeposit,
            sharesObtained,
            strategyAddress,
            prevVaultAssets,
            prevUserShareBalance,
            prevStrategyAssets
        );

        vm.prank(pnlReporter);
        vault.reportProfits(maxDepositPerTransaction * 20, ""); //Very large profit to trigger the scenario

        vm.prank(admin);
        vault.setMinDepositPerTransaction(0); //no minimum, to be able to trigger this scenario. Can also be a low threshold.
        uint256 smallAmountOfAssetsToDeposit = 10000;

        vm.startPrank(user2);
        vault.asset().approve(address(vault), smallAmountOfAssetsToDeposit);

        prevVaultAssets = vault.vaultAssets();
        prevUserShareBalance = vault.balanceOf(user2);
        prevStrategyAssets = vault.asset().balanceOf(strategyAddress);

        vm.expectRevert(FractalityV2Vault.ZeroShares.selector);
        vault.deposit(smallAmountOfAssetsToDeposit, user2);
    }

    function testDeposit_fails_InvalidDepositAmount_belowMinDeposit() public {
        uint256 assetsToDeposit = minDepositPerTransaction - 1;
        vm.startPrank(user1);
        vault.asset().approve(address(vault), assetsToDeposit);

        (address strategyAddress, , , ) = vault.strategy();

        uint256 prevVaultAssets = vault.vaultAssets();
        uint256 prevUserShareBalance = vault.balanceOf(user1);
        uint256 prevStrategyAssets = vault.asset().balanceOf(strategyAddress);

        vm.expectRevert(
            abi.encodeWithSelector(
                FractalityV2Vault.InvalidDepositAmount.selector,
                assetsToDeposit
            )
        );
        vault.deposit(assetsToDeposit, user1);
    }

    function testDeposit_fails_InvalidDepositAmount_aboveMaxDeposit() public {
        uint256 assetsToDeposit = maxDepositPerTransaction + 1;
        vm.startPrank(user1);
        vault.asset().approve(address(vault), assetsToDeposit);

        (address strategyAddress, , , ) = vault.strategy();

        uint256 prevVaultAssets = vault.vaultAssets();
        uint256 prevUserShareBalance = vault.balanceOf(user1);
        uint256 prevStrategyAssets = vault.asset().balanceOf(strategyAddress);

        vm.expectRevert(
            abi.encodeWithSelector(
                FractalityV2Vault.InvalidDepositAmount.selector,
                assetsToDeposit
            )
        );
        vault.deposit(assetsToDeposit, user1);
    }

    function testDeposit_fails_InvalidDepositAmount_exceedsMaxVaultCapacity()
        public
    {
        uint256 assetsToDeposit = maxDepositPerTransaction;
        vm.startPrank(user1);
        vault.asset().approve(address(vault), assetsToDeposit);

        (address strategyAddress, , , ) = vault.strategy();

        uint256 prevVaultAssets = vault.vaultAssets();
        uint256 prevUserShareBalance = vault.balanceOf(user1);
        uint256 prevStrategyAssets = vault.asset().balanceOf(strategyAddress);

        uint256 sharesObtained = vault.deposit(assetsToDeposit, user1);

        _checkDepositOrMint(
            user1,
            assetsToDeposit,
            sharesObtained,
            strategyAddress,
            prevVaultAssets,
            prevUserShareBalance,
            prevStrategyAssets
        );
        vm.stopPrank();

        //lower the max vault capacity to trigger the scenario
        vm.prank(admin);
        vault.setMaxVaultCapacity(
            maxDepositPerTransaction + (maxDepositPerTransaction / 2)
        );

        vm.startPrank(user2);
        vault.asset().approve(address(vault), assetsToDeposit);
        vm.expectRevert(FractalityV2Vault.ExceedsMaxVaultCapacity.selector);
        vault.deposit(assetsToDeposit, user2);
    }

    function testMint(uint256 sharesToMint) public {
        vm.assume(vault.previewMint(sharesToMint) >= minDepositPerTransaction);
        vm.assume(vault.previewMint(sharesToMint) <= maxDepositPerTransaction);

        uint256 assetsToDepositPreview = vault.previewMint(sharesToMint);

        vm.startPrank(user1);
        vault.asset().approve(address(vault), assetsToDepositPreview);

        (address strategyAddress, , , ) = vault.strategy();

        uint256 prevVaultAssets = vault.vaultAssets();
        uint256 prevUserShareBalance = vault.balanceOf(user1);
        uint256 prevStrategyAssets = vault.asset().balanceOf(strategyAddress);

        uint256 assetsDepositedPrview = vault.previewMint(sharesToMint);

        uint256 assetsDeposited = vault.mint(sharesToMint, user1);

        vm.stopPrank();
        assertEq(assetsDeposited, assetsDepositedPrview);
        _checkDepositOrMint(
            user1,
            assetsDeposited,
            sharesToMint,
            strategyAddress,
            prevVaultAssets,
            prevUserShareBalance,
            prevStrategyAssets
        );
    }

    function testMint_fails_Halted(uint256 sharesToMint) public {
        vm.assume(vault.previewMint(sharesToMint) >= minDepositPerTransaction);
        vm.assume(vault.previewMint(sharesToMint) <= maxDepositPerTransaction);

        uint256 assetsToDepositPreview = vault.previewMint(sharesToMint);

        vm.prank(admin);
        vault.setHaltStatus(true);

        vm.startPrank(user1);
        vault.asset().approve(address(vault), assetsToDepositPreview);

        vm.expectRevert(FractalityV2Vault.Halted.selector);
        uint256 assetsDeposited = vault.mint(sharesToMint, user1);
    }

    function testMaxDeposit() public {
        mockToken.mint(initialUserMintAmount * 100, user1);

        assertEq(
            vault.maxDeposit(address(0)),
            vault.maxDepositPerTransaction()
        );

        uint256 maxAssetDeposit = vault.maxDepositPerTransaction();
        uint256 currentMaxVaultCapacity = vault.maxVaultCapacity();

        vm.prank(admin);
        vault.setHaltStatus(true);
        assertEq(vault.maxDeposit(address(0)), 0);

        vm.prank(admin);
        vault.setHaltStatus(false);

        vm.startPrank(user1);
        vault.asset().approve(address(vault), type(uint256).max);

        for (
            uint256 i = 1;
            i < currentMaxVaultCapacity / maxAssetDeposit;
            i++
        ) {
            vault.deposit(maxAssetDeposit, user1);
        }

        vault.deposit(maxAssetDeposit / 2, user1);

        assertEq(vault.maxDeposit(address(0)), maxAssetDeposit / 2);
    }

    function testMaxMint() public {
        mockToken.mint(initialUserMintAmount * 100, user1);

        assertEq(
            vault.maxMint(address(0)),
            vault.convertToShares(vault.maxDepositPerTransaction())
        );

        uint256 maxAssetDeposit = vault.maxDepositPerTransaction();
        uint256 currentMaxVaultCapacity = vault.maxVaultCapacity();

        vm.prank(admin);
        vault.setHaltStatus(true);
        assertEq(vault.maxMint(address(0)), 0);

        vm.prank(admin);
        vault.setHaltStatus(false);

        vm.startPrank(user1);
        vault.asset().approve(address(vault), type(uint256).max);

        for (
            uint256 i = 1;
            i < currentMaxVaultCapacity / maxAssetDeposit;
            i++
        ) {
            vault.deposit(maxAssetDeposit, user1);
        }

        vault.deposit(maxAssetDeposit / 2, user1);

        assertEq(
            vault.maxMint(address(0)),
            vault.convertToShares(maxAssetDeposit / 2)
        );
    }

    function testReportLosses(uint256 assetsToDeposit, uint256 loss) public {
        vm.assume(loss <= assetsToDeposit);
        testDeposit(assetsToDeposit);

        uint256 prevVaultAssets = vault.vaultAssets();
        uint256 prevTotalShares = vault.totalSupply();
        uint256 prevUserShareBalance = vault.balanceOf(user1);

        vm.prank(pnlReporter);
        vault.reportLosses(loss, "");

        assertEq(vault.vaultAssets(), prevVaultAssets - loss);
        assertEq(vault.totalSupply(), prevTotalShares);
        assertEq(vault.balanceOf(user1), prevUserShareBalance);
    }

    function testRequestRedeem(
        uint256 assetsToDeposit,
        uint256 sharesToRedeem
    ) public {
        testDeposit(assetsToDeposit);

        vm.assume(sharesToRedeem <= vault.balanceOf(user1));
        uint256 assets = vault.convertToAssets(sharesToRedeem);
        vm.assume(assets > 0);

        uint256 prevTotalAssetsInRedemptionProcess = vault
            .totalAssetsInRedemptionProcess();
        uint256 prevTotalSharesInRedemptionProcess = vault
            .totalSharesInRedemptionProcess();
        uint256 prevUserShareBalance = vault.balanceOf(user1);
        uint256 prevVaultAssets = vault.vaultAssets();

        vm.startPrank(user1);
        assertEq(vault.requestRedeem(sharesToRedeem, user1, user1), 0);

        uint256 reqTime = block.timestamp;
        vm.stopPrank();

        _checkRedeemRequest(
            user1,
            user1,
            reqTime,
            sharesToRedeem,
            vault.convertToAssets(sharesToRedeem),
            prevTotalAssetsInRedemptionProcess,
            prevTotalSharesInRedemptionProcess,
            prevUserShareBalance,
            prevVaultAssets
        );
    }

    function testRequestRedeem_fails_ControllerMustBeCaller(
        uint256 assetsToDeposit,
        uint256 sharesToRedeem
    ) public {
        testDeposit(assetsToDeposit);

        vm.assume(sharesToRedeem <= vault.balanceOf(user1));
        uint256 assets = vault.convertToAssets(sharesToRedeem);
        vm.assume(assets > 0);

        vm.startPrank(user1);
        vm.expectRevert(FractalityV2Vault.ControllerMustBeCaller.selector);
        vault.requestRedeem(sharesToRedeem, user2, user1);
    }

    function testRequestRedeem_fails_InsufficientShares(
        uint256 assetsToDeposit
    ) public {
        testDeposit(assetsToDeposit);

        uint256 sharesToRedeem = vault.balanceOf(user1) + 1;

        uint256 assets = vault.convertToAssets(sharesToRedeem);
        vm.assume(assets > 0);

        vm.startPrank(user1);
        vm.expectRevert(FractalityV2Vault.InsufficientShares.selector);
        vault.requestRedeem(sharesToRedeem, user1, user1);
    }

    //Scenario where the vault has been doing badly, and the user is trying to redeem so little shares so little that they get (truncated) to zero assets
    function testRequestRedeem_fails_ZeroAssets() public {
        uint256 assetsToDeposit = maxDepositPerTransaction;
        uint256 sharesToRedeem = 1;

        testDeposit(assetsToDeposit);

        uint256 assets = vault.convertToAssets(sharesToRedeem);

        uint256 assetLossAmount = assetsToDeposit / 2;
        vm.prank(pnlReporter);
        vault.reportLosses(assetLossAmount, "");

        vm.startPrank(user1);
        vm.expectRevert(FractalityV2Vault.ZeroAssets.selector);
        vault.requestRedeem(sharesToRedeem, user1, user1);
    }

    function testRequestRedeem_fails_ExistingRedeemRequest(
        uint256 assetsToDeposit,
        uint256 sharesToRedeem
    ) public {
        vm.assume(sharesToRedeem > 1);

        testRequestRedeem(assetsToDeposit, sharesToRedeem - 1);

        vm.startPrank(user1);

        vm.expectRevert(FractalityV2Vault.ExistingRedeemRequest.selector);
        vault.requestRedeem(1, user1, user1);
    }

    //function pendingRedeemRequest, claimableRedeemRequest

    function testPendingRedeemRequest(
        uint256 assetsToDeposit,
        uint256 sharesToRedeem
    ) public {
        testRequestRedeem(assetsToDeposit, sharesToRedeem);
        uint256 pendingShares = vault.pendingRedeemRequest(0, user1);
        assertEq(pendingShares, sharesToRedeem);

        uint256 delay = vault.claimableDelay();

        vm.warp(block.timestamp + delay);

        pendingShares = vault.pendingRedeemRequest(0, user1);
        assertEq(pendingShares, 0);
    }

    function testPendingRedeemRequest_nonExistant() public {
        uint256 pendingShares = vault.pendingRedeemRequest(0, user1);
        assertEq(pendingShares, 0);
    }

    function testClaimableRedeemRequest(
        uint256 assetsToDeposit,
        uint256 sharesToRedeem
    ) public {
        testRequestRedeem(assetsToDeposit, sharesToRedeem);
        uint256 claimableShares = vault.claimableRedeemRequest(0, user1);
        uint256 assetsToRedeem = vault.convertToAssets(sharesToRedeem);

        //assets are in the vault now
        vm.prank(admin);
        vault.asset().transfer(address(vault), assetsToRedeem);

        assertEq(claimableShares, 0); //time hasn't passed

        uint256 delay = vault.claimableDelay();
        vm.warp(block.timestamp + delay);

        claimableShares = vault.claimableRedeemRequest(0, user1);
        assertEq(claimableShares, sharesToRedeem);
    }

    function testClaimableRedeemRequest_nonExistant(
        uint256 assetsToDeposit,
        uint256 sharesToRedeem
    ) public {
        uint256 claimableShares = vault.claimableRedeemRequest(0, user1);
        uint256 assetsToRedeem = vault.convertToAssets(sharesToRedeem);

        assertEq(claimableShares, 0);
    }

    function testClaimableRedeemRequest_noAssetsInVault(
        uint256 assetsToDeposit,
        uint256 sharesToRedeem
    ) public {
        testRequestRedeem(assetsToDeposit, sharesToRedeem);
        uint256 claimableShares = vault.claimableRedeemRequest(0, user1);
        uint256 assetsToRedeem = vault.convertToAssets(sharesToRedeem);

        assertEq(claimableShares, 0); //time hasn't passed

        uint256 delay = vault.claimableDelay();
        vm.warp(block.timestamp + delay);

        claimableShares = vault.claimableRedeemRequest(0, user1);
        assertEq(claimableShares, 0);
    }

    function testReportLosses_fails_LossExceedsVaultAssets(
        uint256 assetsToDeposit,
        uint256 loss
    ) public {
        vm.assume(loss > assetsToDeposit);
        testDeposit(assetsToDeposit);

        vm.prank(pnlReporter);
        vm.expectRevert(FractalityV2Vault.LossExceedsVaultAssets.selector);
        vault.reportLosses(loss, "");
    }

    function testReportLosses_fails_NotPnlReporter(
        uint256 assetsToDeposit,
        uint256 loss
    ) public {
        vm.assume(loss <= assetsToDeposit);
        testDeposit(assetsToDeposit);

        vm.expectRevert();
        vault.reportLosses(loss, "");
    }

    function testReportProfits(uint256 assetsToDeposit, uint256 profit) public {
        vm.assume(profit <= assetsToDeposit);
        testDeposit(assetsToDeposit);

        uint256 prevVaultAssets = vault.vaultAssets();
        uint256 prevTotalShares = vault.totalSupply();
        uint256 prevUserShareBalance = vault.balanceOf(user1);

        vm.prank(pnlReporter);
        vault.reportProfits(profit, "");

        assertEq(vault.vaultAssets(), prevVaultAssets + profit);
        assertEq(vault.totalSupply(), prevTotalShares);
        assertEq(vault.balanceOf(user1), prevUserShareBalance);
    }

    function testReportProfits_fails_NotPnlReporter(
        uint256 assetsToDeposit,
        uint256 profit
    ) public {
        vm.assume(profit <= assetsToDeposit);
        testDeposit(assetsToDeposit);

        uint256 prevVaultAssets = vault.vaultAssets();
        uint256 prevTotalShares = vault.totalSupply();
        uint256 prevUserShareBalance = vault.balanceOf(user1);

        vm.expectRevert();
        vault.reportProfits(profit, "");
    }

    function testReportProfits_fails_ExceedsMaxVaultCapacity(
        uint256 assetsToDeposit
    ) public {
        testDeposit(assetsToDeposit);

        uint256 profits = vault.maxVaultCapacity();

        vm.prank(pnlReporter);
        vm.expectRevert(FractalityV2Vault.ExceedsMaxVaultCapacity.selector);
        vault.reportProfits(profits, "");
    }

    //Boilerplate functions

    function testPreviewWithdraw() public {
        uint256 assetsToWithdraw = 100;
        vm.expectRevert(
            FractalityV2Vault.NotAvailableInAsyncRedeemVault.selector
        );
        vault.previewWithdraw(assetsToWithdraw);
    }

    function testPreviewRedeem() public {
        uint256 sharesToRedeem = 100;
        vm.expectRevert(
            FractalityV2Vault.NotAvailableInAsyncRedeemVault.selector
        );
        vault.previewRedeem(sharesToRedeem);
    }

    function testRequestDeposit() public {
        uint256 assets = 100;
        vm.expectRevert(
            FractalityV2Vault.NotAvailableInAsyncRedeemVault.selector
        );
        vault.requestDeposit(assets);
    }

    function testPendingDepositRequest() public view {
        assertEq(vault.pendingDepositRequest(0, user1), 0);
    }

    function testClaimableDepositRequest() public view {
        assertEq(vault.claimableDepositRequest(0, user1), 0);
    }

    function testMaxWithdraw() public view {
        assertEq(vault.maxWithdraw(user1), 0);
    }

    function testWithdraw() public {
        vm.expectRevert(
            FractalityV2Vault.NotAvailableInAsyncRedeemVault.selector
        );
        vault.withdraw(0, user1, user1);
    }

    //Check functions
    function _checkDepositOrMint(
        address receiver,
        uint256 assets,
        uint256 shares,
        address strategyAddress,
        uint256 prevVaultAssets,
        uint256 prevUserShareBalance,
        uint256 prevStrategyAssets
    ) internal view {
        assertEq(vault.vaultAssets(), prevVaultAssets + assets);
        assertEq(vault.balanceOf(receiver), prevUserShareBalance + shares);
        assertEq(
            vault.asset().balanceOf(strategyAddress),
            prevStrategyAssets + assets
        );
    }

    function _checkRedeemRequest(
        address controller,
        address owner,
        uint256 reqTime,
        uint256 sharesToRedeem,
        uint256 assetsToRedeem,
        uint256 prevTotalAssetsInRedemptionProcess,
        uint256 prevTotalSharesInRedemptionProcess,
        uint256 prevUserShareBalance,
        uint256 prevVaultAssets
    ) internal view {
        RedeemRequestData memory redeemRequest = _getRedeemRequest(controller);

        assertEq(redeemRequest.redeemRequestShareAmount, sharesToRedeem);
        assertEq(redeemRequest.redeemRequestAssetAmount, assetsToRedeem);
        assertEq(redeemRequest.redeemRequestCreationTime, reqTime);
        assertEq(redeemRequest.originalSharesOwner, owner);
        assertEq(redeemRequest.redeemFeeBasisPoints, redeemFeeBasisPoints);

        assertEq(
            vault.totalAssetsInRedemptionProcess(),
            prevTotalAssetsInRedemptionProcess + assetsToRedeem
        );
        assertEq(
            vault.totalSharesInRedemptionProcess(),
            prevTotalSharesInRedemptionProcess + sharesToRedeem
        );

        assertEq(vault.balanceOf(owner), prevUserShareBalance - sharesToRedeem);

        assertEq(vault.vaultAssets(), prevVaultAssets - assetsToRedeem);
    }

    function _getRedeemRequest(
        address controller
    ) internal view returns (RedeemRequestData memory) {
        (
            uint256 redeemRequestShareAmount,
            uint256 redeemRequestAssetAmount,
            uint96 redeemRequestCreationTime,
            address originalSharesOwner,
            uint16 redeemFee
        ) = vault.redeemRequests(controller);
        return
            RedeemRequestData(
                redeemRequestShareAmount,
                redeemRequestAssetAmount,
                redeemRequestCreationTime,
                originalSharesOwner,
                redeemFee
            );
    }
}
