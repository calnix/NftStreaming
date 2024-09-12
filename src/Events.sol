// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;


event Claimed(address indexed user, uint256 amount);
event Claimed(address indexed user, uint256[] tokenIds, uint256[] amounts);
event ClaimedByDelegate(address indexed delegate, address[] owners, uint256[] tokenIds, uint256[] amounts);
event ClaimedByModule(address indexed module, uint256[] tokenIds, uint256[] amounts);

event ClaimedMultiple(address indexed user, uint128[] rounds, uint128 totalAmount);

event Deposited(address indexed operator, uint256 amount);
event DepositorUpdated(address indexed oldDepositor, address indexed newDepositor);

event ModuleUpdated(address indexed module, bool set);

event Withdrawn(address indexed operator, uint256 amount);

event DeadlineUpdated(uint256 indexed newDeadline);

event StreamsPaused(uint256[] indexed tokenIds);

event Frozen(uint256 indexed timestamp);
event EmergencyExit(address receiver, uint256 balance);

