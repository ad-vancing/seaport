// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    AdvancedOrderLib,
    MatchComponent,
    OrderComponentsLib,
    OrderLib,
    OrderParametersLib
} from "seaport-sol/SeaportSol.sol";

import {
    AdvancedOrder,
    ConsiderationItem,
    Execution,
    OfferItem,
    Order,
    OrderComponents,
    OrderParameters,
    SpentItem,
    ReceivedItem
} from "seaport-sol/SeaportStructs.sol";

import { OrderDetails } from "seaport-sol/fulfillments/lib/Structs.sol";

import { ItemType, Side, OrderType } from "seaport-sol/SeaportEnums.sol";

import {
    _locateCurrentAmount,
    Family,
    FuzzHelpers,
    Structure
} from "./FuzzHelpers.sol";

import { FuzzTestContext } from "./FuzzTestContextLib.sol";

import { FuzzDerivers } from "./FuzzDerivers.sol";

/**
 * @notice Stateless helpers for FuzzEngine.
 */
library FuzzEngineLib {
    using AdvancedOrderLib for AdvancedOrder;
    using AdvancedOrderLib for AdvancedOrder[];
    using OrderComponentsLib for OrderComponents;
    using OrderLib for Order;
    using OrderParametersLib for OrderParameters;

    using FuzzHelpers for AdvancedOrder;
    using FuzzHelpers for AdvancedOrder[];
    using FuzzDerivers for FuzzTestContext;

    /**
     * @dev Select an available "action," i.e. "which Seaport function to call,"
     *      based on the orders in a given FuzzTestContext. Selects a random action
     *      using the context's fuzzParams.seed when multiple actions are
     *      available for the given order config.
     *
     * @param context A Fuzz test context.
     * @return bytes4 selector of a SeaportInterface function.
     */
    function action(
        FuzzTestContext memory context
    ) internal view returns (bytes4) {
        if (context._action != bytes4(0)) return context._action;
        bytes4[] memory _actions = actions(context);
        return (context._action = _actions[
            context.fuzzParams.seed % _actions.length
        ]);
    }

    function actionName(
        FuzzTestContext memory context
    ) internal view returns (string memory) {
        bytes4 selector = action(context);
        if (selector == 0xe7acab24) return "fulfillAdvancedOrder";
        if (selector == 0x87201b41) return "fulfillAvailableAdvancedOrders";
        if (selector == 0xed98a574) return "fulfillAvailableOrders";
        if (selector == 0xfb0f3ee1) return "fulfillBasicOrder";
        if (selector == 0x00000000) return "fulfillBasicOrder_efficient_6GL6yc";
        if (selector == 0xb3a34c4c) return "fulfillOrder";
        if (selector == 0xf2d12b12) return "matchAdvancedOrders";
        if (selector == 0xa8174404) return "matchOrders";

        revert("Unknown selector");
    }

    function withDetectedRemainders(
        FuzzTestContext memory context
    ) internal returns (FuzzTestContext memory) {
        (, , MatchComponent[] memory remainders) = context
            .testHelpers
            .getMatchedFulfillments(
                context.executionState.orders,
                context.executionState.criteriaResolvers
            );

        context.executionState.hasRemainders = remainders.length != 0;

        return context;
    }

    /**
     * @dev Get an array of all possible "actions," i.e. "which Seaport
     *      functions can we call," based on the orders in a given FuzzTestContext.
     *
     * @param context A Fuzz test context.
     * @return bytes4[] of SeaportInterface function selectors.
     */
    function actions(
        FuzzTestContext memory context
    ) internal view returns (bytes4[] memory) {
        Family family = context.executionState.orders.getFamily();

        bool invalidOfferItemsLocated = mustUseMatch(context);

        Structure structure = context.executionState.orders.getStructure(
            address(context.seaport)
        );

        bool hasUnavailable = context.executionState.maximumFulfilled <
            context.executionState.orders.length;
        for (
            uint256 i = 0;
            i < context.expectations.expectedAvailableOrders.length;
            ++i
        ) {
            if (!context.expectations.expectedAvailableOrders[i]) {
                hasUnavailable = true;
                break;
            }
        }

        if (hasUnavailable) {
            if (invalidOfferItemsLocated) {
                revert(
                    "FuzzEngineLib: invalid native token + unavailable combination"
                );
            }

            if (structure == Structure.ADVANCED) {
                bytes4[] memory selectors = new bytes4[](1);
                selectors[0] = context
                    .seaport
                    .fulfillAvailableAdvancedOrders
                    .selector;
                return selectors;
            } else {
                bytes4[] memory selectors = new bytes4[](2);
                selectors[0] = context.seaport.fulfillAvailableOrders.selector;
                selectors[1] = context
                    .seaport
                    .fulfillAvailableAdvancedOrders
                    .selector;
                return selectors;
            }
        }

        if (family == Family.SINGLE && !invalidOfferItemsLocated) {
            if (structure == Structure.BASIC) {
                bytes4[] memory selectors = new bytes4[](6);
                selectors[0] = context.seaport.fulfillOrder.selector;
                selectors[1] = context.seaport.fulfillAdvancedOrder.selector;
                selectors[2] = context.seaport.fulfillBasicOrder.selector;
                selectors[3] = context
                    .seaport
                    .fulfillBasicOrder_efficient_6GL6yc
                    .selector;
                selectors[4] = context.seaport.fulfillAvailableOrders.selector;
                selectors[5] = context
                    .seaport
                    .fulfillAvailableAdvancedOrders
                    .selector;
                return selectors;
            }

            if (structure == Structure.STANDARD) {
                bytes4[] memory selectors = new bytes4[](4);
                selectors[0] = context.seaport.fulfillOrder.selector;
                selectors[1] = context.seaport.fulfillAdvancedOrder.selector;
                selectors[2] = context.seaport.fulfillAvailableOrders.selector;
                selectors[3] = context
                    .seaport
                    .fulfillAvailableAdvancedOrders
                    .selector;
                return selectors;
            }

            if (structure == Structure.ADVANCED) {
                bytes4[] memory selectors = new bytes4[](2);
                selectors[0] = context.seaport.fulfillAdvancedOrder.selector;
                selectors[1] = context
                    .seaport
                    .fulfillAvailableAdvancedOrders
                    .selector;
                return selectors;
            }
        }

        bool cannotMatch = (context.executionState.hasRemainders ||
            hasUnavailable);

        if (cannotMatch && invalidOfferItemsLocated) {
            revert("FuzzEngineLib: cannot fulfill provided combined order");
        }

        if (cannotMatch) {
            if (structure == Structure.ADVANCED) {
                bytes4[] memory selectors = new bytes4[](1);
                selectors[0] = context
                    .seaport
                    .fulfillAvailableAdvancedOrders
                    .selector;
                return selectors;
            } else {
                bytes4[] memory selectors = new bytes4[](2);
                selectors[0] = context.seaport.fulfillAvailableOrders.selector;
                selectors[1] = context
                    .seaport
                    .fulfillAvailableAdvancedOrders
                    .selector;
                //selectors[2] = context.seaport.cancel.selector;
                //selectors[3] = context.seaport.validate.selector;
                return selectors;
            }
        } else if (invalidOfferItemsLocated) {
            if (structure == Structure.ADVANCED) {
                bytes4[] memory selectors = new bytes4[](1);
                selectors[0] = context.seaport.matchAdvancedOrders.selector;
                return selectors;
            } else {
                bytes4[] memory selectors = new bytes4[](2);
                selectors[0] = context.seaport.matchOrders.selector;
                selectors[1] = context.seaport.matchAdvancedOrders.selector;
                return selectors;
            }
        } else {
            if (structure == Structure.ADVANCED) {
                bytes4[] memory selectors = new bytes4[](2);
                selectors[0] = context
                    .seaport
                    .fulfillAvailableAdvancedOrders
                    .selector;
                selectors[1] = context.seaport.matchAdvancedOrders.selector;
                return selectors;
            } else {
                bytes4[] memory selectors = new bytes4[](4);
                selectors[0] = context.seaport.fulfillAvailableOrders.selector;
                selectors[1] = context
                    .seaport
                    .fulfillAvailableAdvancedOrders
                    .selector;
                selectors[2] = context.seaport.matchOrders.selector;
                selectors[3] = context.seaport.matchAdvancedOrders.selector;
                //selectors[4] = context.seaport.cancel.selector;
                //selectors[5] = context.seaport.validate.selector;
                return selectors;
            }
        }
    }

    function mustUseMatch(
        FuzzTestContext memory context
    ) internal view returns (bool) {
        for (uint256 i = 0; i < context.executionState.orders.length; ++i) {
            OrderParameters memory orderParams = context
                .executionState
                .orders[i]
                .parameters;
            if (orderParams.orderType == OrderType.CONTRACT) {
                continue;
            }

            for (uint256 j = 0; j < orderParams.offer.length; ++j) {
                OfferItem memory item = orderParams.offer[j];

                if (item.itemType == ItemType.NATIVE) {
                    return true;
                }
            }
        }

        for (uint256 i = 0; i < context.executionState.orders.length; ++i) {
            OrderParameters memory orderParams = context
                .executionState
                .orders[i]
                .parameters;
            for (uint256 j = 0; j < orderParams.offer.length; ++j) {
                OfferItem memory item = orderParams.offer[j];

                if (
                    item.itemType == ItemType.ERC721 ||
                    item.itemType == ItemType.ERC721_WITH_CRITERIA
                ) {
                    uint256 resolvedIdentifier = item.identifierOrCriteria;

                    if (item.itemType == ItemType.ERC721_WITH_CRITERIA) {
                        if (item.identifierOrCriteria == 0) {
                            bytes32 itemHash = keccak256(
                                abi.encodePacked(
                                    uint256(i),
                                    uint256(j),
                                    Side.OFFER
                                )
                            );
                            resolvedIdentifier = context
                                .testHelpers
                                .criteriaResolverHelper()
                                .wildcardIdentifierForGivenItemHash(itemHash);
                        } else {
                            resolvedIdentifier = context
                                .testHelpers
                                .criteriaResolverHelper()
                                .resolvableIdentifierForGivenCriteria(
                                    item.identifierOrCriteria
                                )
                                .resolvedIdentifier;
                        }
                    }

                    for (
                        uint256 k = 0;
                        k < context.executionState.orders.length;
                        ++k
                    ) {
                        OrderParameters memory comparisonOrderParams = context
                            .executionState
                            .orders[k]
                            .parameters;
                        for (
                            uint256 l = 0;
                            l < comparisonOrderParams.consideration.length;
                            ++l
                        ) {
                            ConsiderationItem
                                memory considerationItem = comparisonOrderParams
                                    .consideration[l];

                            if (
                                considerationItem.itemType == ItemType.ERC721 ||
                                considerationItem.itemType ==
                                ItemType.ERC721_WITH_CRITERIA
                            ) {
                                uint256 considerationResolvedIdentifier = considerationItem
                                        .identifierOrCriteria;

                                if (
                                    considerationItem.itemType ==
                                    ItemType.ERC721_WITH_CRITERIA
                                ) {
                                    if (
                                        considerationItem
                                            .identifierOrCriteria == 0
                                    ) {
                                        bytes32 itemHash = keccak256(
                                            abi.encodePacked(
                                                uint256(k),
                                                uint256(l),
                                                Side.CONSIDERATION
                                            )
                                        );
                                        considerationResolvedIdentifier = context
                                            .testHelpers
                                            .criteriaResolverHelper()
                                            .wildcardIdentifierForGivenItemHash(
                                                itemHash
                                            );
                                    } else {
                                        considerationResolvedIdentifier = context
                                            .testHelpers
                                            .criteriaResolverHelper()
                                            .resolvableIdentifierForGivenCriteria(
                                                considerationItem
                                                    .identifierOrCriteria
                                            )
                                            .resolvedIdentifier;
                                    }
                                }

                                if (
                                    resolvedIdentifier ==
                                    considerationResolvedIdentifier &&
                                    item.token == considerationItem.token
                                ) {
                                    return true;
                                }
                            }
                        }
                    }
                }
            }
        }

        return false;
    }

    function getNativeTokensToSupply(
        FuzzTestContext memory context
    ) internal view returns (uint256) {
        bool isMatch = action(context) ==
            context.seaport.matchAdvancedOrders.selector ||
            action(context) == context.seaport.matchOrders.selector;

        uint256 value = 0;
        uint256 valueToCreditBack = 0;

        for (
            uint256 i = 0;
            i < context.executionState.orderDetails.length;
            ++i
        ) {
            OrderDetails memory order = context.executionState.orderDetails[i];
            OrderParameters memory orderParams = context
                .executionState
                .orders[i]
                .parameters;

            if (isMatch) {
                for (uint256 j = 0; j < order.offer.length; ++j) {
                    SpentItem memory item = order.offer[j];

                    if (
                        item.itemType == ItemType.NATIVE &&
                        orderParams.orderType != OrderType.CONTRACT
                    ) {
                        value += item.amount;
                    }
                }
            } else {
                for (uint256 j = 0; j < order.offer.length; ++j) {
                    SpentItem memory item = order.offer[j];

                    if (item.itemType == ItemType.NATIVE) {
                        if (orderParams.orderType == OrderType.CONTRACT) {
                            valueToCreditBack += item.amount;
                        }
                        value += item.amount;
                    }
                }

                for (uint256 j = 0; j < order.consideration.length; ++j) {
                    ReceivedItem memory item = order.consideration[j];

                    if (item.itemType == ItemType.NATIVE) {
                        value += item.amount;
                    }
                }
            }
        }

        if (valueToCreditBack >= value) {
            value = 0;
        } else {
            value = value - valueToCreditBack;
        }

        uint256 minimum = getMinimumNativeTokensToSupply(context);

        if (minimum > value) {
            return minimum;
        } else {
            return value;
        }
    }

    function getMinimumNativeTokensToSupply(
        FuzzTestContext memory context
    ) internal view returns (uint256) {
        bool isMatch = action(context) ==
            context.seaport.matchAdvancedOrders.selector ||
            action(context) == context.seaport.matchOrders.selector;

        uint256 value = 0;
        uint256 valueToCreditBack = 0;

        for (
            uint256 i = 0;
            i < context.executionState.orderDetails.length;
            ++i
        ) {
            if (!context.expectations.expectedAvailableOrders[i]) {
                continue;
            }

            OrderDetails memory order = context.executionState.orderDetails[i];
            OrderParameters memory orderParams = context
                .executionState
                .orders[i]
                .parameters;

            for (uint256 j = 0; j < order.offer.length; ++j) {
                SpentItem memory item = order.offer[j];

                if (
                    item.itemType == ItemType.NATIVE &&
                    orderParams.orderType == OrderType.CONTRACT
                ) {
                    valueToCreditBack += item.amount;
                }
            }

            if (isMatch) {
                for (uint256 j = 0; j < order.offer.length; ++j) {
                    SpentItem memory item = order.offer[j];

                    if (
                        item.itemType == ItemType.NATIVE &&
                        orderParams.orderType != OrderType.CONTRACT
                    ) {
                        value += item.amount;
                    }
                }
            } else {
                for (uint256 j = 0; j < order.offer.length; ++j) {
                    SpentItem memory item = order.offer[j];

                    if (item.itemType == ItemType.NATIVE) {
                        value += item.amount;
                    }
                }

                for (uint256 j = 0; j < order.consideration.length; ++j) {
                    ReceivedItem memory item = order.consideration[j];

                    if (item.itemType == ItemType.NATIVE) {
                        value += item.amount;
                    }
                }
            }
        }

        // Any time more is received back than is paid out, no native tokens
        // need to be supplied.
        if (valueToCreditBack >= value) {
            return 0;
        }

        value = value - valueToCreditBack;

        return value;
    }
}
