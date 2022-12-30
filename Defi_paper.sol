// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";

contract DefiMain {

    address owner;
    // in seconds
    uint timeInterval;
    // in unix epoch time
    uint nextTimeInterval;
    // bandwidth in Mbps
    uint[] links;
    // marketPrices[link] (in wei)
    uint[] public marketPrices;
    uint[] public budgets;
    // budgetAllocation[link][purchaseId]
    mapping(uint => mapping(uint => uint)) public budgetAllocation;
    // usersRequestedPerResource[link][purchaseIds...]
    uint[][] public usersRequestedPerResource;

    // resourcesRequestedPerUser[purchaseId] = [[link, weight]...]
    uint[][][] public resourcesRequestedPerUser;

    mapping(uint => address) purchaseIdToUserMap;



    event AllocateBandwidth(uint[][] bandwidthAllocated, uint[][] users);
    event PriceUpdated(uint[] prices);

    constructor(uint[] memory _links, uint _timeInterval) {
        owner = msg.sender;
        timeInterval = _timeInterval;
        nextTimeInterval = block.timestamp + _timeInterval;
        uint startingPrice = 1;
        // initialization
        for (uint i = 0; i < _links.length; i++) {
            links.push(_links[i]);
            usersRequestedPerResource.push(new uint[](0));
            marketPrices.push(startingPrice);
        }
        
    }

    // targetResources: [[link, weight] ...]
    function makePurchase(uint budget, uint[][] memory targetResources) external payable {
        require(msg.value >= budget, "Ether sent must be at least your budget");
        
        uint purchaseId = budgets.length;
        budgets.push(budget);
        purchaseIdToUserMap[purchaseId] = msg.sender;
        resourcesRequestedPerUser.push(targetResources);

        uint totalPrice = 0;
        for (uint i = 0; i < targetResources.length; i++) {
            totalPrice += marketPrices[targetResources[i][0]] * targetResources[i][1];
        }
        uint accumulatedBudget = 0;
        for (uint i = 0; i < targetResources.length; i++) {
            uint link = targetResources[i][0];
            uint weight = targetResources[i][1];
            usersRequestedPerResource[link].push(purchaseId);
            uint subBudget = 0;
            if (i == targetResources.length - 1) {
                subBudget = budget - accumulatedBudget;
            } else {
                subBudget = marketPrices[link] * budget * weight / totalPrice;
                accumulatedBudget += subBudget;
            }
            budgetAllocation[link][purchaseId] = subBudget;
            marketPrices[link] += subBudget / links[link];
        }
        emit PriceUpdated(marketPrices);  
    }

    function subBudgetUpdate(uint purchaseId, uint[] memory subBudgets) public {
        require(purchaseId < budgets.length && purchaseIdToUserMap[purchaseId] == msg.sender, "Invalid user");
        uint totalBudget = 0;
        for (uint i = 0; i < subBudgets.length; i++) {
            totalBudget += subBudgets[i];
        }
        require(totalBudget <= budgets[purchaseId], "Total budget cannot be more than original budget");
        require(subBudgets.length == resourcesRequestedPerUser[purchaseId].length, "Invalid number of resources to update");
        for (uint i = 0; i < subBudgets.length; i++) {
            uint link = resourcesRequestedPerUser[purchaseId][i][0];
            marketPrices[link] += subBudgets[i] / links[link];
            marketPrices[link] -= budgetAllocation[link][purchaseId] / links[link];
            budgetAllocation[link][purchaseId] = subBudgets[i];
        }
        
        emit PriceUpdated(marketPrices);
    }

    function terminateRound() public {
        require(nextTimeInterval <= block.timestamp, "Time to terminate current round has not been reached");
        uint linksCount = links.length;
        uint[][] memory bandwidthAllocation = new uint[][](linksCount);
        uint[][] memory users = new uint[][](linksCount);
        for (uint i = 0; i < linksCount; i++) {
            uint userCount = usersRequestedPerResource[i].length;
            uint[] memory bandwidthArr = new uint[](userCount);
            uint[] memory userArr = new uint[](userCount);
            for (uint j = 0; j < userCount; j++) {
                uint purchaseId = usersRequestedPerResource[i][j];
                bandwidthArr[j] = budgetAllocation[i][purchaseId] / marketPrices[i];
                userArr[j] = purchaseId;
            }
            bandwidthAllocation[i] = bandwidthArr;
            users[i] = userArr;
        }
        emit AllocateBandwidth(bandwidthAllocation, users);
        // cleanup
        nextTimeInterval = block.timestamp + timeInterval;
        delete budgets;
        delete resourcesRequestedPerUser;
        for (uint i = 0; i < links.length; i++) {
            delete usersRequestedPerResource[i];
        }
    }
}