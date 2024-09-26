// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;


event ClaimedSingle(address indexed user, uint256 tokenId, uint256 amount);
event Claimed(address indexed user, uint256[] tokenIds, uint256[] amounts);
event ClaimedByDelegate(address indexed delegate, address[] owners, uint256[] tokenIds, uint256[] amounts);
event ClaimedByModule(address indexed module, uint256[] tokenIds, uint256[] amounts);

event Deposited(address indexed operator, uint256 amount);
event Withdrawn(address indexed operator, uint256 amount);

event ModuleUpdated(address indexed module, bool set);
event DeadlineUpdated(uint256 indexed newDeadline);
event DepositorUpdated(address indexed oldDepositor, address indexed newDepositor);
event OperatorUpdated(address indexed oldOperator, address indexed newOperator);

event StreamsPaused(uint256[] indexed tokenIds);
event StreamsUnpaused(uint256[] indexed tokenIds);

event Frozen(uint256 indexed timestamp);
event EmergencyExit(address receiver, uint256 balance);


