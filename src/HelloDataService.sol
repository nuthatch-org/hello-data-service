// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DataService} from "@graphprotocol/horizon/data-service/DataService.sol";
import {DataServiceFees} from "@graphprotocol/horizon/data-service/extensions/DataServiceFees.sol";
import {DataServicePausable} from "@graphprotocol/horizon/data-service/extensions/DataServicePausable.sol";
// Payment interfaces live in the interfaces package, not horizon/payments/
import {IGraphTallyCollector} from "@graphprotocol/horizon/interfaces/IGraphTallyCollector.sol";
import {IGraphPayments} from "@graphprotocol/horizon/interfaces/IGraphPayments.sol";

/// @title HelloDataService
/// @notice Minimal Horizon data service — built following the guide.
contract HelloDataService is Ownable, DataService, DataServiceFees, DataServicePausable {

    uint256 public constant MIN_PROVISION      = 10_000e18;
    uint64  public constant MIN_THAWING_PERIOD = 14 days;
    uint256 public constant STAKE_TO_FEES_RATIO = 5;

    IGraphTallyCollector public immutable GRAPH_TALLY_COLLECTOR;

    mapping(address => bool)    public registeredProviders;
    mapping(address => address) public paymentsDestination;

    event ProviderRegistered(address indexed provider, string greeting);
    event ProviderDeregistered(address indexed provider);
    event PaymentsDestinationSet(address indexed provider, address indexed destination);

    error ProviderAlreadyRegistered(address provider);
    error ProviderNotRegistered(address provider);
    error InvalidPaymentType();
    error InvalidServiceProvider(address expected, address got);

    constructor(
        address owner_,
        address controller,
        address graphTallyCollector,
        address pauseGuardian
    ) Ownable(owner_) DataService(controller) {
        GRAPH_TALLY_COLLECTOR = IGraphTallyCollector(graphTallyCollector);
        _setProvisionTokensRange(MIN_PROVISION, type(uint256).max);
        _setThawingPeriodRange(MIN_THAWING_PERIOD, type(uint64).max);
        _setVerifierCutRange(0, uint32(1_000_000));
        _setPauseGuardian(pauseGuardian, true);
    }

    function register(address serviceProvider, bytes calldata data)
        external override whenNotPaused onlyAuthorizedForProvision(serviceProvider)
    {
        if (registeredProviders[serviceProvider]) revert ProviderAlreadyRegistered(serviceProvider);
        _checkProvisionTokens(serviceProvider);
        _checkProvisionParameters(serviceProvider, false);

        (string memory greeting, address dest) = abi.decode(data, (string, address));
        registeredProviders[serviceProvider] = true;
        paymentsDestination[serviceProvider] = dest == address(0) ? serviceProvider : dest;
        emit ProviderRegistered(serviceProvider, greeting);
    }

    function startService(address, bytes calldata) external override whenNotPaused {}
    function stopService(address, bytes calldata)  external override whenNotPaused {}

    // deregister is NOT in IDataService — no override keyword
    function deregister(address serviceProvider, bytes calldata)
        external onlyAuthorizedForProvision(serviceProvider)
    {
        if (!registeredProviders[serviceProvider]) revert ProviderNotRegistered(serviceProvider);
        registeredProviders[serviceProvider] = false;
        emit ProviderDeregistered(serviceProvider);
    }

    function acceptProvisionPendingParameters(address serviceProvider, bytes calldata)
        external override onlyAuthorizedForProvision(serviceProvider)
    {
        _acceptProvisionParameters(serviceProvider);
    }

    function collect(
        address serviceProvider,
        IGraphPayments.PaymentTypes paymentType,
        bytes calldata data
    ) external override whenNotPaused returns (uint256 fees) {
        if (paymentType != IGraphPayments.PaymentTypes.QueryFee) revert InvalidPaymentType();
        if (!registeredProviders[serviceProvider]) revert ProviderNotRegistered(serviceProvider);

        (IGraphTallyCollector.SignedRAV memory signedRav, uint256 tokensToCollect) =
            abi.decode(data, (IGraphTallyCollector.SignedRAV, uint256));

        if (signedRav.rav.serviceProvider != serviceProvider)
            revert InvalidServiceProvider(serviceProvider, signedRav.rav.serviceProvider);

        _releaseStake(serviceProvider, 0);

        fees = GRAPH_TALLY_COLLECTOR.collect(
            paymentType,
            abi.encode(signedRav, uint256(0), paymentsDestination[serviceProvider]),
            tokensToCollect
        );

        if (fees > 0)
            _lockStake(serviceProvider, fees * STAKE_TO_FEES_RATIO, block.timestamp + MIN_THAWING_PERIOD);
    }

    function slash(address, bytes calldata) external pure override {
        revert("slashing not supported");
    }

    function setPaymentsDestination(address destination) external {
        if (!registeredProviders[msg.sender]) revert ProviderNotRegistered(msg.sender);
        paymentsDestination[msg.sender] = destination == address(0) ? msg.sender : destination;
        emit PaymentsDestinationSet(msg.sender, paymentsDestination[msg.sender]);
    }
}
